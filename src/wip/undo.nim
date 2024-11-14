# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
import undo/[cmd, stream, swap]
import image/layer
import image
# Export Undo Command Enum
export NUndoCommand

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
    # Command Descriptor
    chain: NUndoChain
    cmd: NUndoCommand
    seek: NUndoSeek
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
  configure(result.swap)
  configure(result.stream)
  # Configure Dispatchers
  let stream = addr result.stream
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

# ------------------
# Undo Step Creation
# ------------------

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

proc chain*(undo: NImageUndo, cmd: NUndoCommand): NUndoStep =
  result = undo.push(cmd)
  # Check Chain Step
  let prev = result.prev
  if isNil(prev) or prev.chain notin
      {chainStart, chainStep}:
    prev.chain = chainStart
  else: prev.chain = chainStep

# -----------------
# Undo Step Capture
# -----------------

converter target(step: NUndoStep): NUndoTarget =
  result.layer = step.layer
  result.stage = step.stage
  result.cmd = step.cmd
  result.data = addr step.data
  # Next Stage Dispatch
  inc(step.stage)

proc capture*(step: NUndoStep, layer: NLayer) =
  let state0 = addr step.undo.state0
  step.layer = layer.code.id
  # Dispatch Capture Stage
  state0.step = step
  state0[].tiles(layer)
  state0[].capture()

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
    undo.state0.step = step
    undo.state0.redo()
    if step.chain in {chainNone, chainEnd}: break
    else: step = step.next
  # Change Undo Cursor
  undo.cursor = step
