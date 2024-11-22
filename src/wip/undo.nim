# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
import undo/[cmd, stream, swap]
import image/layer
import image
# Export Undo Command Enum
export NUndoCommand
export NUndoEffect

type
  NUndoChain = enum
    chainNone
    chainStart
    chainStep
    chainEnd
  NUndoStep* = ptr object
    skip: NUndoSkip
    undo: NImageUndo
    prev, next: NUndoStep
    pre0, nex0: NUndoStep
    # Command Code
    layer: uint32
    msg: uint32
    swap: bool
    stage: uint8
    weak: bool
    # Command Descriptor
    chain: NUndoChain
    cmd: NUndoCommand
    data: NUndoData
  # Undo Step Manager
  NImageUndo* = ptr object
    swap: NUndoSwap
    stream: NUndoStream
    state0: NUndoState
    state1: NUndoTransfer
    # Step Linked List
    first, last: NUndoStep
    firs0, las0: NUndoStep
    # Step Cursor
    swipe, busy: bool
    cursor: NUndoStep
    curso0: NUndoStep

# ---------------------------------
# Undo Manager Creation/Destruction
# ---------------------------------

proc createImageUndo*(image: NImage): NImageUndo =
  result = create(result[].typeof)
  let swap = addr result.swap
  let stream = addr result.stream
  # Configure Streaming
  swap[].configure()
  stream[].configure(swap)
  # Configure Dispatchers
  configure(result.state0, stream, image)
  configure(result.state1, stream)

proc destroy*(undo: NImageUndo) =
  destroy(undo.stream)
  destroy(undo.swap)
  # Dealloc Undo History
  `=destroy`(undo[])
  dealloc(undo)

# ---------------------
# Undo Step Destruction
# ---------------------

proc detach(step: NUndoStep) =
  let undo = step.undo
  if step == undo.first:
    undo.first = step.next
  if step == undo.last:
    undo.last = step.prev
  # Detach From Undo
  let prev = step.prev
  let next = step.next
  if not isNil(prev):
    prev.next = step.next
  if not isNil(next):
    next.prev = step.prev
  # Clear Pointers
  wasMoved(step.undo)
  wasMoved(step.next)
  wasMoved(step.prev)

proc destroy(step: NUndoStep) =
  destroy(step.data, step.cmd)
  # Detach & Dealloc
  detach(step)
  dealloc(step)

proc cutdown(step: NUndoStep) =
  var trunk = step.next
  while not isNil(trunk):
    let next = trunk.next
    # Destroy and Step
    trunk.destroy()
    trunk = next

# ---------------------------
# Undo Step Capture: Creation
# ---------------------------

proc push*(undo: NImageUndo, cmd: NUndoCommand): NUndoStep =
  result = create(result[].typeof)
  result.undo = undo
  result.cmd = cmd
  # Get Current Cursor
  var cursor = undo.cursor
  if undo.swipe:
    undo.swipe = false
    cursor = cursor.prev
  # Cutdown Cursor
  if isNil(cursor):
    undo.first = result
  elif cursor != undo.last:
    cursor.cutdown()
  # Add Step After Cursor
  if not isNil(cursor):
    cursor.next = result
    result.prev = cursor
  # Replace Current Cursors
  undo.cursor = result
  undo.last = result

proc chained(step: NUndoStep, rev: bool) =
  let prev = if not rev: step.prev else: step.next
  if isNil(prev) or prev.chain notin
      {chainStart, chainStep}:
    step.chain = chainStart
  elif rev:
    prev.chain = chainStep
    step.chain = chainStart
  else: step.chain = chainStep

proc chain*(undo: NImageUndo, cmd: NUndoCommand): NUndoStep =
  result = undo.push(cmd)
  result.chained(rev = false)

# ----------------------------
# Undo Step Capture: Recursive
# ----------------------------

converter target(step: NUndoStep): NUndoTarget =
  result = NUndoTarget(
    layer: step.layer,
    stage: step.stage,
    weak: step.weak,
    # Command Data
    cmd: step.cmd,
    data: addr step.data
  ); inc(step.stage)

proc capture0(step: NUndoStep, layer: NLayer) =
  let state0 = addr step.undo.state0
  step.layer = layer.code.id
  # Dispatch Capture Stage
  state0.step = step
  state0[].tiles(layer)
  state0[].capture()

proc child(step: NUndoStep, layer: NLayer, rev: bool): NUndoStep =
  result = create(result[].typeof)
  let undo = step.undo
  result.undo = undo
  result.cmd = step.cmd
  result.weak = true
  # Attach to Step
  if not rev:
    let next = step.next
    result.prev = step
    result.next = next
    if not isNil(next):
      next.prev = result
    step.next = result
    # Replace Undo Manager Cursors
    if undo.cursor == step: undo.cursor = result
    if undo.last == step: undo.last = result
  elif rev:
    let prev = step.prev
    result.next = step
    result.prev = prev
    if not isNil(prev):
      prev.next = result
    step.prev = result
  # Dispatch Capture
  result.capture0(layer)
  result.chained(rev)

proc childs(step0: NUndoStep, root: NLayer, rev: bool) =
  var step = step0
  var layer = root.last
  while not isNil(layer):
    step = step.child(layer, rev)
    # Enter/Leave Folder
    if layer.kind == lkFolder:
      if not isNil(layer.last):
        layer = layer.last
        continue
    while isNil(layer.prev) and layer != root:
      layer = layer.folder
    # Step Previous Layer
    if layer != root:
      layer = layer.prev
    else: break

# -----------------
# Undo Step Capture
# -----------------

proc capture*(step: NUndoStep, layer: NLayer) =
  step.capture0(layer)
  # Capture Layer Childrens
  let check0 = step.cmd == ucLayerCreate
  let check1 = step.cmd == ucLayerDelete
  if layer.kind == lkFolder and (check0 or check1):
    step.chained(check1)
    step.childs(layer, check1)

proc stencil*(step, mask: NUndoStep, layer: NLayer) =
  let state0 = addr step.undo.state0
  var target = mask.target()
  state0[].stencil(target)
  dec(mask.stage)
  # Dispatch Capture Stage
  step.capture(layer)
  target.cmd = ucCanvasNone
  state0[].stencil(target)

# -----------------
# Undo Step Manager
# -----------------

proc flush*(undo: NImageUndo) =
  let peek = undo.last
  if isNil(peek): return
  # Check Chain Step
  peek.chain = case peek.chain
  of chainStart: chainNone
  of chainStep: chainEnd
  else: peek.chain

proc undo*(undo: NImageUndo): set[NUndoEffect] =
  var step = undo.cursor
  if undo.swipe:
    step = step.prev
  undo.swipe = true
  if isNil(step):
    return
  # Step Undo Chain
  while true:
    result.incl effect(step.cmd)
    undo.state0.step = step
    undo.state0.undo()
    if step.chain in {chainNone, chainStart}: break
    else: step = step.prev
  # Change Undo Cursor
  undo.cursor = step

proc redo*(undo: NImageUndo): set[NUndoEffect] =
  var step = undo.cursor
  if not undo.swipe:
    step = step.next
  undo.swipe = false
  if isNil(step):
    return
  # Step Undo Chain
  while true:
    result.incl effect(step.cmd)
    undo.state0.step = step
    undo.state0.redo()
    if step.chain in {chainNone, chainEnd}: break
    else: step = step.next
  # Change Undo Cursor
  undo.cursor = step
