# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
import nogui/async/core
import undo/[book, cmd, stream, swap]
import image/layer
import image
# Export Undo Command Enum
export NUndoCommand
export NUndoEffect

type
  NUndoWhere = enum
    inRAM, inSwap
    inStage, inTrash
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
    stage: uint8
    weak: bool
    # Command Descriptor
    where: NUndoWhere
    chain: NUndoChain
    cmd: NUndoCommand
    data: NUndoData
  # Undo Step Manager
  NUndoTask = object
    undo: NImageUndo
    cursor: NUndoStep
    state: NUndoTransfer
  NImageUndo* = ptr object
    swap: NUndoSwap
    stream: NUndoStream
    state: NUndoState
    # Step Linked List
    coro: Coroutine[NUndoTask]
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
  let coro = coroutine(NUndoTask)
  # Configure Streaming
  swap[].configure()
  stream[].configure(swap)
  # Configure Dispatchers
  configure(result.state, stream, image)
  configure(coro.data.state, stream)
  # Configure Coroutine Task
  coro.data.undo = result
  result.coro = coro

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
  if isNil(undo):
    return
  # Change Undo Endpoints
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

proc cutdown(step: NUndoStep): NUndoStep =
  result = step.prev
  # Cutdown Next Steps
  var trunk = step
  while not isNil(trunk):
    let next = trunk.next
    # Destroy or Detach
    if trunk.where == inStage:
      trunk.where = inTrash
      trunk.detach()
    else: trunk.destroy()
    # Next Step Trunk
    trunk = next

# ---------------------------
# Undo Step Capture: Creation
# ---------------------------

proc push*(undo: NImageUndo, cmd: NUndoCommand): NUndoStep =
  result = create(result[].typeof)
  result.undo = undo
  result.cmd = cmd
  # Cutdown Cursor
  var cursor = undo.cursor
  if undo.swipe:
    result.skip = cursor.skip
    cursor = cutdown(cursor)
  elif cursor != undo.last:
    result.skip = cursor.next.skip
    cursor = cutdown(cursor.next)
  # Add Step After Cursor
  if not isNil(cursor):
    cursor.next = result
    result.prev = cursor
  else: undo.first = cursor
  # Replace Current Cursors
  undo.cursor = result
  undo.last = result
  undo.swipe = false

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
  let state0 = addr step.undo.state
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
  let state0 = addr step.undo.state
  var target = mask.target()
  state0[].stencil(target)
  dec(mask.stage)
  # Dispatch Capture Stage
  step.capture(layer)
  target.cmd = ucCanvasNone
  state0[].stencil(target)

# --------------------------
# Undo Step Coroutine: Write
# --------------------------

proc startWrite(task: ptr NUndoTask) =
  let
    stream = task.state.stream
    swap = stream.swap
    step = task.cursor
  # Step Current Stage
  let stage = step.stage
  task.state.step = step
  if stage > 0: return
  # Check Step Position
  if step.skip.bytes > 0:
    swap[].setWrite(step.skip)
  # Write Undo Step Header
  swap[].startWrite()
  stream.writeNumber(step.layer)
  stream.writeNumber(step.msg)
  stream.writeNumber(uint32 step.cmd)
  stream.writeNumber(uint16 step.weak)
  stream.writeNumber(uint16 step.chain)

proc endWrite(task: ptr NUndoTask): bool =
  let stream = task.state.stream
  let step = task.cursor
  let next = step.nex0
  # Write Seeking and Step Cursor
  step.skip = stream.swap[].endWrite()
  result = not isNil(next)
  if result: task.cursor = next

# -------------------
# Undo Step Coroutine
# -------------------

proc swap0book(coro: Coroutine[NUndoTask])
proc swap0coro(coro: Coroutine[NUndoTask])
proc swap0stage(undo: NImageUndo) =
  undo.firs0 = undo.first
  undo.las0 = undo.last
  # Ghost Current Stack
  var step = undo.curso0
  while not isNil(step):
    step.nex0 = step.next
    step.pre0 = step.prev
    step.where = inStage
    step.stage = 0
    # Next Undo Step
    step = step.next
  # Configure Coroutine
  let data = undo.coro.data
  data.cursor = undo.curso0
  # Execute Coroutine
  undo.coro.pass(swap0coro)
  undo.coro.spawn()
  undo.busy = true

proc swap0check(undo: NImageUndo) =
  var step: NUndoStep = nil
  if undo.first != undo.firs0:
    step = undo.first
  elif undo.last != undo.las0:
    step = undo.last
    while true:
      let prev = step.prev
      # Locate at First inRAM
      if isNil(prev): break
      elif prev.where != inRAM:
        break
      step = prev
  # Dispatch Coroutine
  undo.busy = false
  undo.curso0 = step
  if not isNil(step):
    undo.swap0stage()

proc swap0clean(undo: NImageUndo) =
  var step = undo.las0
  wasMoved(undo.curso0.pre0)
  # Destroy Trash Steps
  while not isNil(step):
    if step.where != inTrash:
      step.where = inSwap
    else: step.destroy()
    step = step.pre0
  # Check Swap Ghost
  undo.swap0check()

proc swap0book(coro: Coroutine[NUndoTask]) =
  let data = addr coro.data.state
  var more: bool; coro.lock():
    more = compressPage(data.codec)
  # Check if Streaming is Finalized
  if more: coro.pass(swap0book)
  else: coro.pass(swap0coro)

proc swap0coro(coro: Coroutine[NUndoTask]) =
  let task = coro.data
  coro.lock():
    task.startWrite()
    if task.state.swap0write():
      coro.pass(swap0book)
    elif task.endWrite():
      coro.pass(swap0coro)
    # Send Termination Callback
    else: coro.send CoroCallback(
      data: cast[pointer](task.undo),
      fn: cast[CoroCallbackProc](swap0clean)
    )

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
  # Swap if not Busy
  if not undo.busy:
    swap0check(undo)

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
    undo.state.step = step
    undo.state.undo()
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
    undo.state.step = step
    undo.state.redo()
    if step.chain in {chainNone, chainEnd}: break
    else: step = step.next
  # Change Undo Cursor
  undo.cursor = step
