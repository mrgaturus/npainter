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
    inRAM, inStage, inTrash
    inSwap, inSkip
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
    coro: Coroutine[NUndoTask]
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
    elif trunk.where in {inSwap, inSkip}:
      trunk.where = inSkip
      result = trunk
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
    cursor = cutdown(cursor)
    if cursor.where == inSkip:
      result.skip = cursor.skip
  elif cursor != undo.last:
    cursor = cutdown(cursor.next)
  # Add Step After Cursor
  if not isNil(cursor):
    cursor.next = result
    result.prev = cursor
  else: undo.first = result
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

proc stageHeader(task: ptr NUndoTask) =
  let stream = task.state.stream
  let swap = stream.swap
  let step = task.cursor
  # Locate to Current Skip
  if step.skip.bytes > 0:
    swap[].setWrite(step.skip)
  # Write Undo Step Header
  swap[].startWrite()
  stream.writeNumber(step.layer)
  stream.writeNumber(step.msg)
  stream.writeNumber(uint32 step.cmd)
  stream.writeNumber(uint16 step.chain)
  stream.writeNumber(uint16 step.weak)

proc stageWrite(task: ptr NUndoTask): bool =
  let step = task.cursor
  let stage = step.stage
  task.state.step = step
  # Dispatch Write Stage
  if stage == 0: task.stageHeader()
  result = task.state.swap0write()

proc nextWrite(task: ptr NUndoTask): bool =
  let swap = task.state.stream.swap
  let step = task.cursor
  let next = step.nex0
  # Write Seeking and Step Cursor
  step.skip = swap[].endWrite()
  result = not isNil(next)
  if result: task.cursor = next

# -----------------------------
# Undo Step Coroutine: Ghosting
# -----------------------------

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
  wasMoved(data.cursor.pre0)
  # Execute Coroutine
  undo.coro.pass(swap0coro)
  undo.coro.spawn()
  undo.busy = true

proc swap0check(undo: NImageUndo) =
  var step = default(NUndoStep)
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
    echo step.where
    undo.swap0stage()

proc swap0ghost(undo: NImageUndo) =
  let cursor = undo.cursor
  if undo.firs0.where == inStage:
    let ghost = create(cursor[].typeof)
    let first = undo.first
    ghost.where = inSwap
    ghost.undo = undo
    # Change Undo First
    ghost.next = first
    first.prev = ghost
    undo.first = ghost
    undo.firs0 = ghost
  # Change Cursor if Staged
  if cursor.where == inStage:
    let ghost = undo.first
    ghost.skip = cursor.skip
    ghost.where = inSwap
    # Destroy Cursor
    undo.cursor = ghost
    undo.las0 = ghost
    cursor.destroy()

# TODO: allow keep some steps in RAM
proc swap0clean(undo: NImageUndo) =
  var skip = default(NUndoSkip)
  var step = undo.las0
  # Destroy Trash Steps
  while not isNil(step):
    if step.where == inTrash:
      skip = step.skip
      step.destroy()
    else: break
    step = step.pre0
  # Stamp Next Stage
  if isNil(step): return
  elif not isNil(step.next):
    step.next.skip = skip
  # Destroy Stage Steps
  let cursor = undo.cursor
  while not isNil(step):
    if step != cursor:
      step.destroy()
    step = step.pre0
  # Check Swap Ghost
  undo.swap0ghost()
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
  echo skip[].repr
  # Preload Step Description
  step.layer = readNumber[uint32](stream)
  step.msg = readNumber[uint32](stream)
  step.cmd = cast[NUndoCommand](readNumber[uint32](stream))
  step.chain = cast[NUndoChain](readNumber[uint16](stream))
  step.weak = cast[bool](readNumber[uint16](stream))
  # Preload Step Command
  undo.state.step = step
  undo.state.swap0read()
  step.stage = 0

proc prevStep(undo: NImageUndo): NUndoStep =
  let cursor = undo.cursor
  let swipe = undo.swipe
  result = cursor
  # Check Step Found
  undo.swipe = true
  if isNil(result) or not swipe:
    return result
  # Check Step Swap
  if cursor.where == inSwap:
    let skip = addr cursor.skip
    skip.pos = skip.prev
    return cursor
  # Check Step Target
  result = cursor.prev
  if isNil(result):
    return cursor
  elif result.where == inSkip:
    let skip = addr result.skip
    if skip.pos != skip.prev:
      skip.pos = skip.prev
      result.where = inSwap
    else: return cursor
  # Change Current Cursor
  undo.cursor = result

proc nextStep(undo: NImageUndo): NUndoStep =
  let cursor = undo.cursor
  let swipe = undo.swipe
  result = cursor
  # Check Step Found
  undo.swipe = false
  if isNil(result) or swipe:
    return result
  # Check Step Swap
  if cursor.where == inSwap:
    let skip = addr result.skip
    if skip.pos != skip.next:
      skip.pos = skip.next
    else: result = result.next
  else: result = result.next
  # Change Current Cursor
  if not isNil(result):
    undo.cursor = cursor

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
  let coro {.cursor.} = undo.coro
  # Step Redo Commands
  result = {}
  while true:
    let step = undo.prevStep()
    if isNil(step): break
    # Process Undo Step
    if step.where != inSwap:
      result.incl effect(step.cmd)
      undo.state.step = step
      undo.state.redo()
    else: coro.lock():
      step.preload()
      # Process Undo Step
      result.incl effect(step.cmd)
      undo.state.step = step
      undo.state.undo()
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
      undo.state.step = step
      undo.state.redo()
    else: coro.lock():
      step.preload()
      # Process Redo Step
      result.incl effect(step.cmd)
      undo.state.step = step
      undo.state.redo()
    # Check Redo Step Chain
    if step.chain in {chainNone, chainEnd}:
      break
