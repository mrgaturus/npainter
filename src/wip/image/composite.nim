# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
import ffi, context, layer

type
  NCompositorCmd* = enum
    cmDiscard
    # Layer Blending
    cmBlendLayer
    cmBlendScope
    cmBlendClip
    # Layer Scoping
    cmScopeRoot
    cmScopeImage
    cmScopePass
    cmScopeClip
  NCompositorScope* = object
    cmd*: NCompositorCmd
    mode*: NBlendMode
    clip*: bool
    # Layer Attributes
    layer*: NLayer
    alpha0*: cfloat
    alpha1*: cfloat
    # Scope Image Buffer
    buffer*: NImageBuffer
  # -- Compositor State Machine --
  NCompositorStep = object
    root, folder: NLayer
    # Step Command
    layer: NLayer
    cmd, cmd0: NCompositorCmd
  NCompositorStack = object
    x, y: cint
    # Scope Lists
    scopes: seq[NCompositorScope]
    buffers: seq[pointer]
    # Scope Indexes
    buf: cint

type
  # 128x128 Compositor Blocks
  NCompositorBlock = object
    com*: ptr NCompositor
    # Tiled Location
    x128*, y128*: cshort
    dirty*, unused: cushort
  # -- Compositor Dispatch --
  NCompositorState* = object
    layer*: NLayer
    fn, ext*: pointer
    # Dispatch Command
    cmd*: NCompositorCmd
    mode*: NBlendMode
    clip*: bool
    mipmap*: int8
    # Dispatch 128x128 Scopes
    scope*: ptr NCompositorScope
    lower*: ptr NCompositorScope
    # Dispatch 128x128 Block
    stack*: NCompositorStack
    chunk*: ptr NCompositorBlock
  NCompositorProc* =  # NLayerProc.fn
    proc(state: ptr NCompositorState) {.nimcall.}
  # -- Compositor Manager --
  NCompositor* = object
    ctx*: ptr NImageContext
    # Image Content
    root*: NLayer
    fn*: NCompositorProc
    # Compositor Blocks
    mipmap*: cint
    w128, h128: cint
    blocks: seq[NCompositorBlock]

# ---------------------
# Compositor Block Step
# ---------------------

proc checkClip(layer: NLayer): bool =
  let
    kind = layer.kind
    # Check Clipping or Mask
    check0 = kind in {lkMask, lkStencil}
    check1 = lpClipping in layer.props.flags
  # Check if has Clipping
  check0 or check1

proc commandClip(layer: NLayer): NCompositorCmd =
  let
    prev = layer.prev
    clip0 = layer.checkClip()
  # Check Clipping Scope
  if not isNil(prev):
    let clip = prev.checkClip()
    # Check Clipping Scoping
    if not clip0 and clip:
      result = cmScopeClip
    elif clip0 and not clip:
      result = cmBlendClip
  # Check Clipping Ending
  elif clip0:
    result = cmBlendClip

proc command(layer: NLayer, leave: bool): NCompositorCmd =
  let
    kind = layer.kind
    props = addr layer.props
    pass = props.mode == bmPassthrough
  # Check Layer Kind
  if lpVisible in props.flags:
    if leave: result = cmBlendScope
    elif kind in {lkColor, lkMask, lkStencil}:
      result = cmBlendLayer
    # Enter Folder
    elif kind == lkFolder:
      result = if not pass:
        cmScopeImage
      else: cmScopePass

# -- Compositor Walking --
proc createStep(root: NLayer): NCompositorStep =
  result.root = root
  result.layer = root
  # Initial Compositor State
  result.cmd = cmScopeRoot

proc next(step: var NCompositorStep): bool =
  const cmEnter = cmScopeRoot..cmScopePass
  let layer0 = step.layer
  # Current State
  var
    layer = layer0.prev
    folder = step.folder
    leave = false
  # Enter Scope
  if step.cmd in cmEnter:
    layer = layer0.last
    folder = layer0
  elif layer0 == step.root:
    return leave
  # Leave Scope
  if isNil(layer):
    layer = folder
    folder = layer.folder
    leave = true
  # Layer Command
  var cmd = layer.command(leave)
  if cmd notin cmEnter:
    let clip = layer.commandClip()
    # Replace as Clipping Command
    if clip != cmDiscard:
      step.cmd0 = cmd
      cmd = clip
  # Replace Command
  step.cmd = cmd
  step.layer = layer
  step.folder = folder
  # Step Command
  result = true

# ------------------------
# Compositor Block Scoping
# ------------------------

# -- Stack Buffer --
proc pushBuffer*(stack: var NCompositorStack): NImageBuffer =
  let idx = stack.buf
  # 128x128 Image Buffer
  const
    bpp = sizeof(cushort) shl 2
    stride = bpp * 128
  result = NImageBuffer(
    x: stack.x,
    y: stack.y,
    w: 128, h: 128,
    # Buffer Information
    stride: stride,
    bpp: bpp
  )
  # Needs New Buffer?
  if idx == len(stack.buffers):
    const bytes = stride * 128
    # Allocate New Buffer And Add to Stack
    result.buffer = alloc(bytes)
    stack.buffers.add(result.buffer)
  else: # Lookup Current Buffer
    result.buffer = stack.buffers[idx]
  # Next Buffer Index
  stack.buf = idx + 1

proc popBuffer*(stack: var NCompositorStack) =
  let idx = stack.buf - 1
  assert idx >= 0
  stack.buf = idx

# -- Stack Scoping --
proc elevate(stack: var NCompositorStack, step: NCompositorStep) =
  let
    layer = step.layer
    props = addr layer.props
    # Layer Checks
    visible = lpVisible in props.flags
    clip = step.cmd == cmScopeClip
  # Create New Scope
  var scope = NCompositorScope(
    cmd: step.cmd,
    mode: props.mode,
    # Layer Attributes
    layer: layer,
    alpha0: props.opacity
  )
  # Prepare Clipping Scope
  if clip and visible:
    let last = addr stack.scopes[^1]
    # Optimize Leave Folder
    if layer.kind == lkFolder:
      if last.cmd == cmScopeImage:
        last.cmd = scope.cmd
        last.clip = clip
      # No Scope
      return
    # Optimize First Layer of Scope when is not Passthrough
    elif isNil(layer.next) and last.cmd notin {cmScopePass, cmScopeRoot}:
      scope.mode = bmPassthrough
  # Create Passthrough Scope
  if scope.mode == bmPassthrough:
    let last = addr stack.scopes[^1]
    # Pass Opacity and Clipping from Last
    scope.clip = clip or last.clip
    scope.alpha1 = scope.alpha0 * last.alpha1
    scope.buffer = last.buffer
  # Create Buffer Scope
  elif visible:
    scope.clip = clip
    scope.alpha1 = 1.0
    scope.buffer = stack.pushBuffer()
  # Create Discard Scope
  else:
    scope.cmd = cmDiscard
    scope.mode = bmPassthrough
  # Add Created Scope
  stack.scopes.add(scope)

proc lower(stack: var NCompositorStack) =
  let
    l = len(stack.scopes)
    idx = l - 1
  if idx == 0: return
  # Buffer Lowering
  if stack.scopes[idx].mode != bmPassthrough:
    stack.popBuffer()
  # Remove Scope
  setLen(stack.scopes, idx)

# -- Stack Destroy --
proc destroy(stack: var NCompositorStack) =
  # Dealloc Scopes
  for buffer in items(stack.buffers):
    dealloc(buffer)
  # Reset Scopes
  setLen(stack.scopes, 0)
  setLen(stack.buffers, 0)
  stack.buf = 0

# ----------------------
# Compositor Block State
# ----------------------

proc scope(state: var NCompositorState) =
  let
    stack = addr state.stack
    last = high(stack.scopes)
    last1 = max(last - 1, 0)
    # Scope Pointers
    scope = addr stack.scopes[last]
    lower = addr stack.scopes[last1]
  # Prepare Layer Scopes
  state.scope = scope
  state.lower = lower

proc dispatch(state: var NCompositorState, step: NCompositorStep) =
  let
    layer = step.layer
    hook = layer.hook
    scope = state.scope
  # Discard Scope Command
  if scope.cmd == cmDiscard:
    return
  # Prepare Command
  block prepare:
    state.layer = layer
    state.cmd = step.cmd
    state.mode = layer.props.mode
    # Prepare Command Clipping
    const check = {cmScopeClip, cmBlendClip}
    state.clip = scope.clip and (step.cmd notin check)
  # Prepare Layer Rendering
  var fn = cast[NCompositorProc](hook.fn)
  if isNil(fn): fn = state.chunk.com.fn
  else: state.ext = hook.ext
  # Dispatch Layer Rendering
  if state.mode != bmPassthrough:
    fn(addr state)

proc scoping(state: var NCompositorState, step: NCompositorStep) =
  case step.cmd
  # Dispatch Elevate Scope
  of cmScopeRoot..cmScopeClip:
    elevate(state.stack, step)
    state.scope()
    # after Elevate
    state.dispatch(step)
  # Dispatch Lower Scope
  of cmBlendScope, cmBlendClip:
    state.dispatch(step)
    # after Dispatch
    lower(state.stack)
    state.scope()
  # No Scoping Involved
  else: discard

proc createState(chunk: ptr NCompositorBlock): NCompositorState =
  let
    com = chunk.com
    stack = addr result.stack
  # Locate Stack Scopes
  stack.x = chunk.x128 shl 7
  stack.y = chunk.y128 shl 7
  # Prepare State Chunk
  result.chunk = chunk
  result.mipmap = int8(com.mipmap)

# --------------------------
# Compositor Block Rendering
# --------------------------

proc render(chunk: ptr NCompositorBlock) =
  var
    walking = true
    # Create State Machine
    state = createState(chunk)
    step = createStep(chunk.com.root)
  # Walk Layer Tree
  while walking:
    # Dispatch Scoping
    case step.cmd:
    of cmDiscard: discard
    of cmBlendLayer:
      state.dispatch(step)
    of cmBlendClip:
      let scope = state.scope
      # Dispatch Clipped Last
      step.cmd = step.cmd0
      state.dispatch(step)
      # Dispatch Clipped Scope
      if scope.cmd in {cmDiscard, cmScopeClip}:
        let layer0 = step.layer
        # Prepare Scoping Layer
        step.cmd = cmBlendClip
        step.layer = scope.layer
        # Dispatch Scoping Layer
        state.scoping(step)
        step.layer = layer0
    else:
      state.scoping(step)
    # Next Layer Step
    walking = step.next()
  # Destroy Stack and Dirty
  state.stack.destroy()
  chunk.dirty = 0

# --------------------------
# Compositor Block Configure
# --------------------------

proc configure*(com: var NCompositor) =
  # Locate 128x128 Blocks
  let
    ctx = com.ctx
    # Context Dimensions
    w = ctx.w32
    h = ctx.h32
    # 128x128 Grid Dimensions
    w128 = (w + 0x7F) shr 7
    h128 = (h + 0x7F) shr 7
    l = w128 * h128
  # Initialize Blocks
  setLen(com.blocks, l)
  # Locate Blocks
  var i: cint
  for y in 0 ..< h128:
    for x in 0 ..< w128:
      let b = addr com.blocks[i]
      # Initialize Block
      b.com = addr com
      b.x128 = cshort(x)
      b.y128 = cshort(y)
      # Next Block
      inc(i)
  # Store Size
  com.w128 = w128
  com.h128 = h128

proc mark*(com: var NCompositor, tx, ty: cint) =
  let
    bw = com.w128
    bx = tx shr 2
    by = ty shr 2
    # Lookup Compositor Block
    b = addr com.blocks[by * bw + bx]
    # Dirty Position
    dx = tx and 0x3
    dy = ty and 0x3
    # Bit Position
    bit = 1 shl (dy shl 2 + dx)
  # Mark Block To Render
  b.dirty = b.dirty or cushort(bit)

# ----------------------------
# Compositor Block Dispatching
# ----------------------------

# Instant TODO: Multithreading
proc dispatch*(com: var NCompositor) =
  # Render Prepared Blocks
  for b in mitems(com.blocks):
    if b.dirty > 0:
      render(addr b)
