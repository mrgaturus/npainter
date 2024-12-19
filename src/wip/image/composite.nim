# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
import nogui/async/pool
import ffi, layer

type
  NCompositorCmd* = enum
    cmBlendDiscard
    cmBlendLayer
    cmBlendScope
    # Layer Scoping
    cmScopeImage
    cmScopePass
    cmScopeMask
    cmScopeClip
  NCompositorStep* = object
    layer*: NLayer
    # Step Information
    cmd*: NCompositorCmd
    mode*: NBlendMode
    alpha*: uint8
    clip*: bool
  # -- Compositor Scoping --
  NCompositorScope* = object
    step*: NCompositorStep
    buffer*: NImageBuffer
  NCompositorStack = object
    x, y, buf: cint
    # Compositor Scoping Buffers
    scopes: seq[NCompositorScope]
    buffers: seq[pointer]

type
  # 128x128 Compositor Blocks
  NCompositorBlock = object
    com*: ptr NCompositor
    # Tiled Location
    x128*, y128*: cshort
    dirty*, unused: cushort
  # -- Compositor Dispatch --
  NCompositorState* = object
    step*: NCompositorStep
    ext*: pointer
    mipmap*: int32
    idx: uint32
    # Dispatch 128x128 Scopes
    scope*: ptr NCompositorScope
    lower*: ptr NCompositorScope
    # Dispatch 128x128 Block
    stack*: NCompositorStack
    chunk*: ptr NCompositorBlock
  # -- Compositor Manager --
  NCompositorProc* =  # NLayerProc.fn
    proc(state: ptr NCompositorState) {.nimcall.}
  NCompositor* = object
    fn*: NCompositorProc
    ext*: pointer
    # Compositor Blocks
    mipmap*: cint
    w128, h128: cint
    blocks: seq[NCompositorBlock]
    stack: seq[NCompositorStep]
    steps: seq[NCompositorStep]

proc step*(layer: NLayer): NCompositorStep =
  let props = addr layer.props
  let clip = lpClipping in props.flags
  # Check Step Visibility
  var alpha = uint8(props.opacity * 255.0)
  if lpVisible notin props.flags:
    alpha = 0
  # Check Step Mask
  var mode = props.mode
  if layer.kind == lkMask and
      mode != bmStencil:
    mode = bmMask
  # Prepare Compositor Step
  NCompositorStep(
    layer: layer,
    # Step Information
    cmd: cmBlendDiscard,
    mode: mode,
    alpha: alpha,
    clip: clip
  )

# --------------------------------
# Compositor Step Machine: Scoping
# --------------------------------

proc stepPushScope(com: var NCompositor, layer: NLayer): bool =
  var step = layer.step()
  # Check Scope Visibility
  result = step.alpha > 0
  if not result:
    com.steps.add(step)
    return result
  # Configure Scoping
  step.cmd = cmScopeImage
  if step.mode == bmPassthrough:
    step.cmd = cmScopePass
  # Add Scope to Stack
  com.steps.add(step)
  com.stack.add(step)

proc stepPopScope(com: var NCompositor) =
  var step = com.stack.pop()
  # Add Scope Blending
  step.cmd = cmBlendScope
  com.steps.add(step)

proc stepPopScope(com: var NCompositor, cmd: NCompositorCmd) =
  {.push checks: off.}
  if len(com.stack) > 0 and
      com.stack[^1].cmd == cmd:
    com.stepPopScope()
  {.pop.}

proc stepClipScope(com: var NCompositor) =
  var peek = com.steps[^1]
  let next = peek.layer.prev
  # Check Next Clipping
  var nextClip = false
  var nextMask = false
  if not isNil(next):
    nextClip = lpClipping in next.props.flags
    nextMask = next.kind == lkMask
  # Check Clipping Scopes
  let peekClip = peek.clip
  let peekMask = peek.layer.kind == lkMask
  if peekClip and not nextClip:
    com.stepPopScope(cmScopeMask)
    com.stepPopScope(cmScopeClip)
    com.stepPopScope(cmScopeClip)
    return
  elif not peekClip and nextClip:
    let cmd = peek.cmd
    peek.cmd = cmScopeClip
    # Add Clipping Scope
    com.steps[^1] = peek
    com.stack.add(peek)
    if cmd == cmBlendScope:
      com.stack.add(peek)
    # Add Mask Scope
    if nextMask:
      peek.cmd = cmScopeMask
      com.steps.add(peek)
      com.stack.add(peek)
    return
  # Check Mask Sub-Scopes
  if not peekClip: return
  if peekMask and not nextMask:
    com.stepPopScope(cmScopeMask)
  elif not peekMask and nextMask:
    peek.cmd = cmScopeMask
    com.steps[^1] = peek
    com.stack.add(peek)

# -----------------------
# Compositor Step Machine
# -----------------------

proc stepClear*(com: var NCompositor) =
  com.stack.setLen(0)
  com.steps.setLen(0)

proc stepUnsafe*(com: var NCompositor, step: NCompositorStep) =
  com.steps.add(step)

proc stepLayer*(com: var NCompositor, layer: NLayer) =
  if layer.kind != lkFolder:
    var step = layer.step()
    if step.alpha > 0:
      step.cmd = cmBlendLayer
    # Add Simple Command
    com.steps.add(step)
    return
  # Enter Layer Scope
  if com.stepPushScope(layer):
    var layer = layer.last
    # Add Layer Commands
    while not isNil(layer):
      com.stepLayer(layer)
      com.stepClipScope()
      layer = layer.prev
    com.stepPopScope()

# ---------------------------------
# Compositor State Machine: Buffers
# ---------------------------------

proc pushBuffer*(stack: var NCompositorStack): NImageBuffer =
  let idx = stack.buf
  # 128x128 Image Buffer
  const
    bpp = sizeof(uint16) * 4
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
    # Allocate New Buffer
    result.buffer = alloc(bytes)
    stack.buffers.add(result.buffer)
  else: result.buffer = stack.buffers[idx]
  # Buffer Stack Index
  stack.buf = idx + 1

proc popBuffer*(stack: var NCompositorStack) =
  let idx = stack.buf - 1
  assert idx >= 0
  stack.buf = idx

# ---------------------------------
# Compositor State Machine: Scoping
# ---------------------------------

proc pushScope(stack: var NCompositorStack, step: NCompositorStep) =
  var scope = NCompositorScope(step: step)
  # Optimize Scope Buffer
  if len(stack.scopes) > 0:
    let lower = stack.scopes[^1]
    let mask = step.mode in {bmMask, bmStencil}
    let pass = step.mode == bmPassthrough
    # Check Same Layer or Cancel Clip
    if step.layer == lower.step.layer:
      scope.buffer = lower.buffer
    elif step.cmd == cmScopeClip and (pass or mask):
      scope.buffer = lower.buffer
      scope.step.mode = bmPassthrough
    elif step.cmd == cmScopeMask and mask:
      scope.buffer = lower.buffer
      scope.step.alpha = 0
    # Check Scope Optimized Buffer
    if scope.buffer == lower.buffer:
      stack.scopes.add(scope)
      return
  # Create Scope Buffer
  scope.buffer = stack.pushBuffer()
  stack.scopes.add(scope)

proc popScope(stack: var NCompositorStack) =
  let scope = stack.scopes.pop()
  # Optimize Scope Buffer
  if len(stack.scopes) > 0:
    let lower = stack.scopes[^1]
    if scope.buffer == lower.buffer:
      return
  # Remove Scope Buffer
  stack.popBuffer()

# ----------------------------------
# Compositor State Machine: Dispatch
# ----------------------------------

proc next(state: var NCompositorState): bool =
  let com = state.chunk.com
  var idx = int(state.idx)
  result = idx < len(com.steps)
  # Step Current Index
  if result:
    state.step = com.steps[idx]
    inc(state.idx)

proc scope(state: var NCompositorState): bool =
  let stack = addr state.stack
  let idx0 = high(stack.scopes)
  let idx1 = max(0, idx0 - 1)
  # Define Current Scope
  let scope = addr stack.scopes[idx0]
  let lower = addr stack.scopes[idx1]
  state.scope = scope
  state.lower = lower
  # Check Scope Clipping
  case scope.step.cmd
  of cmScopeClip:
    state.step.clip =
      state.step.clip and
      scope.step.mode != bmPassthrough
  of cmScopePass:
    state.step.clip =
      (state.step.clip or scope.step.clip) and
      lower.step.mode != bmPassthrough
  else: discard
  # Check Current Scope
  if scope != lower and
    scope.step.layer == lower.step.layer and
    state.step.cmd >= cmBlendScope: false
  elif state.step.cmd == cmBlendDiscard: false
  elif state.step.alpha == 0: false
  elif scope.step.alpha == 0: false
  else: true

proc dispatch(state: var NCompositorState) =
  if not state.scope():
    return
  # Prepare Dispatch Hook
  let step = state.step
  let hook = step.layer.hook
  var fn = cast[NCompositorProc](hook.fn)
  state.ext = hook.ext
  # Default Dispatch Hook
  if isNil(fn):
    let com = state.chunk.com
    state.ext = com.ext
    fn = com.fn
  # Dispatch Rendering
  fn(addr state)

# ------------------------------------
# Compositor State Machine: Processing
# ------------------------------------

proc createState(chunk: ptr NCompositorBlock): NCompositorState =
  result = default(NCompositorState)
  # Locate Stack Scopes
  let com = chunk.com
  let stack = addr result.stack
  stack.x = chunk.x128 shl 7
  stack.y = chunk.y128 shl 7
  # Prepare State Chunk
  result.mipmap = int32(com.mipmap)
  result.chunk = chunk

proc process(state: var NCompositorState) =
  case state.step.cmd
  of cmBlendDiscard, cmBlendLayer:
    state.dispatch()
  of cmScopeImage..cmScopeClip:
    state.stack.pushScope(state.step)
    state.dispatch()
  of cmBlendScope:
    state.dispatch()
    state.stack.popScope()

proc destroy(stack: var NCompositorStack) =
  for buffer in items(stack.buffers):
    dealloc(buffer)

proc render(chunk: ptr NCompositorBlock) =
  var state = createState(chunk)
  while state.next():
    state.process()
  # Destroy Stack and Dirty
  state.stack.destroy()
  chunk.dirty = 0

# --------------------
# Compositor Configure
# --------------------

proc configure*(com: var NCompositor, w, h: int32) =
  let w128 = (w + 0x7F) shr 7
  let h128 = (h + 0x7F) shr 7
  let l = w128 * h128
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

proc mark*(com: var NCompositor, x32, y32: cint) =
  let
    bw = com.w128
    bx = x32 shr 2
    by = y32 shr 2
    # Lookup Compositor Block
    b = addr com.blocks[by * bw + bx]
    # Dirty Position
    dx = x32 and 0x3
    dy = y32 and 0x3
    # Bit Position
    bit = 1 shl (dy shl 2 + dx)
  # Mark Block To Render
  b.dirty = b.dirty or cushort(bit)

# ----------------------------
# Compositor Block Dispatching
# ----------------------------

proc dispatch*(com: var NCompositor, pool: NThreadPool) =
  for b in mitems(com.blocks):
    if b.dirty > 0:
      pool.spawn(render, addr b)
  # Wait Rendering
  pool.sync()
