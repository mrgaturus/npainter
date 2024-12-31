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
    inRAM, inStage
    inTrash, inSwap
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
    # Current Stage
    state: NUndoTransfer
    stage: uint8
  NImageUndo* = ptr object
    swap: NUndoSwap
    stream: NUndoStream
    state: NUndoState
    coro: Coroutine[NUndoTask]
    # Step Linked List
    first, last: NUndoStep
    firs0, las0: NUndoStep
    # Step Cursor
    cursor: NUndoStep
    peak: NUndoSkip
    # Step Cursor Status
    busy, bus0: bool
    swipe: bool

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

proc cutdown(down: NUndoStep): NUndoStep =
  if isNil(down): return down
  result = down.prev
  # Cutdown Steps
  var trunk = down
  while not isNil(trunk):
    let next = trunk.next
    # Destroy or Detach
    case trunk.where
    of inRAM: trunk.destroy()
    of inStage:
      trunk.where = inTrash
      trunk.detach()
    of inTrash, inSwap:
      discard
    # Next Step Trunk
    trunk = next

proc cutswap(swap: NUndoStep): NUndoStep =
  discard cutdown(swap.next)
  let undo = swap.undo
  let skip = swap.skip
  result = swap
  # Cutdown Swap Peak
  if not undo.swipe:
    undo.peak = skip.predictNext()
    return result
  # Cutdown Swap Backwards
  undo.peak = skip
  if skip.pos != skip.prev:
    swap.skip = skip.predictPrev()
    return result
  # Destroy Swap Step
  wasMoved(result)
  swap.destroy()

# ---------------------------
# Undo Step Capture: Creation
# ---------------------------

proc pushed(undo: NImageUndo, cmd: NUndoCommand): NUndoStep =
  var down = undo.cursor
  result = create(result[].typeof)
  result.undo = undo
  result.cmd = cmd
  # Cutdown Swap Tree
  if isNil(down): discard
  elif down.where == inSwap:
    down = cutswap(down)
  elif undo.swipe:
    down = cutdown(down)
  elif not isNil(down.next):
    down = cutdown(down.next)
  # Add Step After Down
  if not isNil(down):
    down.next = result
    result.prev = down
  elif isNil(down):
    undo.first = result
  # Replace Cursors
  undo.cursor = result
  undo.last = result
  # Replace Cursors Status
  undo.swipe = false
  undo.busy = true

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
  result = undo.pushed(cmd)
  result.chained(rev = false)

proc push*(undo: NImageUndo, cmd: NUndoCommand): NUndoStep =
  result = undo.pushed(cmd)
  # End Current Chain
  let prev = result.prev
  if not isNil(prev) and prev.chain == chainStep:
    prev.chain = chainEnd

# ----------------------------
# Undo Step Capture: Recursive
# ----------------------------

proc pass0(step: NUndoStep): NUndoPass =
  result = NUndoPass(
    layer: step.layer,
    stage: step.stage,
    weak: step.weak,
    # Command Data
    cmd: step.cmd,
    data: addr step.data)

proc pass(step: NUndoStep): NUndoPass =
  result = step.pass0()
  inc(step.stage)

proc capture0(step: NUndoStep, layer: NLayer) =
  let state0 = addr step.undo.state
  step.layer = layer.code.id
  # Dispatch Capture Stage
  state0.step = step.pass()
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
    result.skip = move(step.skip)
    # Attach Previous to Step
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
  var target = mask.pass0()
  state0[].stencil(target)
  # Dispatch Capture Stage
  step.capture(layer)
  target.cmd = ucCanvasNone
  state0[].stencil(target)

# --------------------------
# Undo Step Coroutine: Write
# --------------------------

proc stageHeader(task: ptr NUndoTask) =
  let stream = task.state.stream
  let swap = stream.swap
  let step = task.cursor
  # Locate Undo Step
  swap[].setWrite(step.skip)
  swap[].startWrite()
  # Write Undo Step Header
  stream.writeNumber(step.layer)
  stream.writeNumber(step.msg)
  stream.writeNumber(uint32 step.cmd)
  stream.writeNumber(uint16 step.chain)
  stream.writeNumber(uint16 step.weak)

proc stageWrite(task: ptr NUndoTask): bool =
  let step = task.cursor
  let state = addr task.state
  let stage = task.stage
  state[].step = step.pass0()
  state[].step.stage = stage
  # Dispatch Write Stage
  if stage == 0: task.stageHeader()
  result = state[].swap0write()
  inc(task.stage)

proc nextWrite(task: ptr NUndoTask): bool =
  let swap = task.state.stream.swap
  let step = task.cursor
  let next = step.nex0
  # Write Seeking and Step Cursor
  step.skip = swap[].endWrite()
  result = not isNil(next)
  task.cursor = next
  task.stage = 0

# -----------------------------
# Undo Step Coroutine: Ghosting
# -----------------------------

proc swap0book(coro: Coroutine[NUndoTask])
proc swap0coro(coro: Coroutine[NUndoTask])
proc swap0stage(undo: NImageUndo, curso0: NUndoStep) =
  undo.firs0 = undo.first
  undo.las0 = undo.last
  # Ghost Current Stack
  var step = curso0
  while not isNil(step):
    step.nex0 = step.next
    step.pre0 = step.prev
    step.where = inStage
    # Next Undo Step
    step = step.next
  wasMoved(curso0.pre0)
  curso0.skip = undo.peak
  # Configure Coroutine
  let task = undo.coro.data
  task.cursor = curso0
  task.stage = 0
  # Execute Coroutine
  undo.coro.pass(swap0coro)
  undo.coro.spawn()
  undo.bus0 = true

proc swap0check(undo: NImageUndo) =
  var step = default(NUndoStep)
  var peek = undo.last
  # Check Busy Indicator
  undo.bus0 = false
  if undo.busy:
    return
  # Select First inRAM
  while not isNil(peek):
    if peek.where == inRAM:
      step = peek
      peek = peek.prev
    else: break
  # Dispatch Coroutine  
  if not isNil(step):
    undo.swap0stage(step)

proc swap0ghost(undo: NImageUndo, step: NUndoStep) =
  var ghost = undo.first
  if ghost.where != inSwap:
    let first = undo.first
    ghost = create(step[].typeof)
    ghost.where = inSwap
    ghost.undo = undo
    # Change Undo First
    ghost.next = first
    first.prev = ghost
    undo.first = ghost
  # Assert Ghost Valid
  assert step.where == inStage
  assert ghost.where == inSwap
  # Replace Cursor With Ghost
  let cursor = undo.cursor
  if cursor.where == inStage:
    ghost.skip = cursor.skip
    ghost.chain = cursor.chain
    undo.cursor = ghost
  # Locate Ghost at End
  elif cursor != ghost:
    ghost.skip = step.skip
    ghost.chain = step.chain

# TODO: allow keep some steps in RAM
proc swap0clean(undo: NImageUndo) =
  var step = undo.las0
  wasMoved(undo.las0)
  # Destroy Trash Steps
  while not isNil(step):
    if step.where == inTrash:
      let pre0 = step.pre0
      step.destroy()
      step = pre0
    else: break
  # Stamp Next Stage
  if not isNil(step):
    undo.peak = predictNext(step.skip)
    undo.swap0ghost(step)
    # Destroy Stage Steps
    while not isNil(step):
      let pre0 = step.pre0
      step.destroy()
      step = pre0
  # Stage Swap Again
  undo.swap0check()

# -------------------
# Undo Step Coroutine
# -------------------

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
    if task.stageWrite():
      coro.pass(swap0book)
    elif task.nextWrite():
      coro.pass(swap0coro)
    # Send Termination Callback
    else: coro.send CoroCallback(
      data: cast[pointer](task.undo),
      fn: cast[CoroCallbackProc](swap0clean)
    )

# ---------------------------
# Undo Step Manager: Ghosting
# ---------------------------

proc preload(step: NUndoStep) =
  let undo = step.undo
  let stream = addr undo.stream
  let swap = stream.swap
  # Preload Step Position
  let skip = addr step.skip
  skip[] = swap[].setRead(skip.pos)
  # Preload Step Description
  step.layer = readNumber[uint32](stream)
  step.msg = readNumber[uint32](stream)
  step.cmd = cast[NUndoCommand](readNumber[uint32](stream))
  step.chain = cast[NUndoChain](readNumber[uint16](stream))
  step.weak = cast[bool](readNumber[uint16](stream))
  # Preload Step Command
  undo.state.step = step.pass0()
  undo.state.swap0read()

proc prevStep(undo: NImageUndo): NUndoStep =
  let swipe = undo.swipe
  result = undo.cursor
  # Check Step Found
  undo.swipe = true
  if isNil(result) or not swipe:
    return result
  # Check Step Swap
  if result.where == inSwap:
    let skip = addr result.skip
    if skip.pos != skip.prev:
      skip.pos = skip.prev
      return result
    return nil
  # Check Step Target
  result = result.prev
  if not isNil(result):
    undo.cursor = result

proc nextStep(undo: NImageUndo): NUndoStep =
  let swipe = undo.swipe
  result = undo.cursor
  # Check Step Found
  undo.swipe = false
  if isNil(result) or swipe:
    return result
  # Check Step Swap
  if result.where == inSwap:
    let skip = addr result.skip
    # Check Swap Next Step
    if skip.pos != skip.next and
      skip.pos != undo.peak.prev:
        skip.pos = skip.next
        return result
  # Change Current Cursor
  result = result.next
  if not isNil(result):
    undo.cursor = result

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
  undo.busy = false
  if not undo.bus0:
    swap0check(undo)

proc undo*(undo: NImageUndo): set[NUndoEffect] =
  let coro {.cursor.} = undo.coro
  # Step Redo Commands
  result = {}
  while true:
    let step = undo.prevStep()
    if isNil(step): break
    # Process Undo Step
    if step.where != inSwap:
      result.incl effect(step.cmd)
      undo.state.step = step.pass0()
      undo.state.undo()
    else: coro.lock():
      step.preload()
      # Process Undo Step
      result.incl effect(step.cmd)
      undo.state.step = step.pass0()
      undo.state.undo()
      # Destroy Temporal Data
      destroy(step.data, step.cmd)
    # Check Undo Step Chain
    if step.chain in {chainNone, chainStart}:
      break

proc redo*(undo: NImageUndo): set[NUndoEffect] =
  let coro {.cursor.} = undo.coro
  # Step Redo Commands
  result = {}
  while true:
    let step = undo.nextStep()
    if isNil(step): break
    # Process Redo Step
    if step.where != inSwap:
      result.incl effect(step.cmd)
      undo.state.step = step.pass0()
      undo.state.redo()
    else: coro.lock():
      step.preload()
      # Process Redo Step
      result.incl effect(step.cmd)
      undo.state.step = step.pass0()
      undo.state.redo()
      # Destroy Temporal Data
      destroy(step.data, step.cmd)
    # Check Redo Step Chain
    if step.chain in {chainNone, chainEnd}:
      break
