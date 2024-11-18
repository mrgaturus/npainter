# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
import book, stream, swap
from nogui/bst import insert, search
import ../image/[layer, tiles, context]
import ../image

type
  NUndoCopy = object
    kind: NLayerKind
    props: NLayerProps
    tag: NLayerTag
    book: NUndoBook
  NUndoMark = object
    before: NUndoBook
    after: NUndoBook
  NUndoProps = object
    before: NLayerProps
    after: NLayerProps
  NUndoReorder = object
    before: NLayerTag
    after: NLayerTag
  # Undo Step Command
  NUndoEffect* = enum
    ueCanvasNone
    ueCanvasProps
    ueLayerProps
    ueLayerTiles
    ueLayerList
  NUndoCommand* {.pure, size: 4.} = enum
    ucCanvasNone
    ucCanvasProps
    # Layer Commands
    ucLayerCreate
    ucLayerDelete
    ucLayerTiles
    ucLayerMark
    ucLayerProps
    ucLayerReorder
  NUndoData* {.union.} = object
    copy: NUndoCopy
    mark: NUndoMark
    # Attributes Data
    props: NUndoProps
    reorder: NUndoReorder

type
  NUndoTarget* = object
    node: NLayer
    layer*: uint32
    stage*: uint8
    weak*: bool
    # Undo Step Data
    cmd*: NUndoCommand
    data*: ptr NUndoData
  # Undo State Machine
  NUndoState* = object
    step*: NUndoTarget
    stream: ptr NUndoStream
    # Undo Internal State
    stage: NUndoStage
    image: NImage
  NUndoTransfer* = object
    target*: NUndoTarget
    stream: ptr NUndoStream
    # Undo Internal State
    codec: NBookTransfer
    buffer: NUndoBuffer
    idx, bytes: int

proc destroy*(data: var NUndoData, cmd: NUndoCommand) =
  case cmd # Manual Destroy
  of ucLayerCreate, ucLayerDelete:
    `=destroy`(data.copy)
  of ucLayerTiles, ucLayerMark:
    `=destroy`(data.mark)
  of ucLayerProps:
    `=destroy`(data.props)
  else: discard

proc effect*(cmd: NUndoCommand): set[NUndoEffect] =
  const effects = [
    ucCanvasNone: {ueCanvasProps},
    ucCanvasProps: {ueCanvasProps},
    # Layer Commands Effects
    ucLayerCreate: {ueLayerTiles, ueLayerList, ueLayerProps},
    ucLayerDelete: {ueLayerTiles, ueLayerList, ueLayerProps},
    ucLayerTiles: {ueLayerTiles},
    ucLayerMark: {ueLayerTiles},
    ucLayerProps: {ueLayerTiles, ueLayerProps},
    ucLayerReorder: {ueLayerTiles, ueLayerList}
  ]; effects[cmd]

# -----------------------
# Undo Dispatch Configure
# -----------------------

proc configure*(state: var NUndoState,
    stream: ptr NUndoStream, image: NImage) =
  state.stream = stream
  state.image = image
  # Configure Undo Stage
  let stage = addr state.stage
  stage.status = addr image.status
  stage.stream = stream

proc configure*(state: var NUndoTransfer,
    stream: ptr NUndoStream) =
  state.stream = stream

# --------------------
# Undo Command Prepare
# --------------------

proc stencil*(state: var NUndoState, mask: NUndoTarget) =
  let stage = addr state.stage
  let data = mask.data
  # Decide Stencil Book
  case mask.cmd
  of ucLayerCreate, ucLayerDelete:
    stage.stencil = addr data.copy.book
  of ucLayerTiles, ucLayerMark:
    stage.stencil = addr data.mark.before
  else: wasMoved(stage.stencil)

proc tiles*(state: var NUndoState, layer: NLayer) =
  let stage = addr state.stage
  wasMoved(stage.tiles)
  # Configure Layer Tiles
  state.step.node = layer
  if not isNil(layer) and layer.kind != lkFolder:
    stage.tiles = addr layer.tiles

proc layer(state: var NUndoState, id: uint32) =
  let node = search(state.image.owner, id)
  # Lookup Layer Node
  var no: NLayer
  if not isNil(node):
    no = node.layer()
  # Configure Layer Tiles
  state.tiles(no)

# -------------------------
# Undo Command RAM: Capture
# -------------------------

proc capture0copy(state: var NUndoState) =
  let
    step = addr state.step
    stage = addr state.stage
    copy = addr step.data.copy
    layer = step.node
  # Copy Basic Layer Attributes
  copy.kind = layer.kind
  copy.props = layer.props
  # Copy Layer Tag
  if step.weak:
    copy.tag.code = layer.folder.code.id
    copy.tag.mode = ltAttachFolder
  else: copy.tag = layer.tag()
  # Copy Layer Tiles
  if step.stage == 0 and layer.kind != lkFolder:
    stage.before = addr copy.book
    stage.after = addr copy.book
    stage.writeCopy0()

proc capture*(state: var NUndoState) =
  let step = addr state.step
  let stage = addr state.stage
  # Canvas Capture Commands
  case step.cmd
  of ucCanvasNone: discard
  of ucCanvasProps: discard
  # Layer Capture Commands
  of ucLayerCreate, ucLayerDelete:
    state.capture0copy()
  of ucLayerTiles:
    let mark = addr step.data.mark
    stage.before = addr mark.before
    stage.after = addr mark.after
    if step.stage == 1:
      swap(stage.before, stage.after)
    elif step.stage > 1:
      return
    # Dispatch Tiles Capture
    stage.writeCopy0()
  of ucLayerMark:
    let mark = addr step.data.mark
    stage.before = addr mark.before
    stage.after = addr mark.after
    # Dispatch Tiles Capture
    if step.stage == 0:
      if isNil(stage.stencil):
        stage.writeMark0()
      elif stage.stencil != stage.before:
        stage.after = stage.before
        stage.before = stage.stencil
        stage.writeMark1()
    elif step.stage == 1:
      stage.writeMark1()
  of ucLayerProps:
    let props0 = addr step.node.props
    let props = addr step.data.props
    if step.stage == 0: props.before = props0[]
    elif step.stage == 1: props.after = props0[]
  of ucLayerReorder:
    let tag = step.node.tag()
    let reorder = addr step.data.reorder
    if step.stage == 0: reorder.before = tag
    elif step.stage == 1: reorder.after = tag

# --------------------------
# Undo Command RAM: Dispatch
# --------------------------

proc commit0mark(state: var NUndoState) =
  let
    step = addr state.step
    stage = addr state.stage
    mark = addr step.data.mark
  # Prepare Mark Clipping
  if step.cmd == ucLayerTiles:
    stage.tiles[].clear()
  # Prepare Before/After
  stage.before = addr mark.before
  stage.after = addr mark.after

proc commit0create(state: var NUndoState) =
  let
    step = addr state.step
    copy = addr step.data.copy
    layer = createLayer(copy.kind)
    image = state.image
  # Configure Layer
  layer.code.id = step.layer
  layer.props = copy.props
  image.attachLayer(layer, copy.tag)
  # Transfer Layer Tiles
  state.tiles(layer)
  let stage = addr state.stage
  if not isNil(stage.tiles):
    stage.before = addr copy.book
    stage.after = addr copy.book
    stage.readBefore()
  # Select Created Layer
  if not step.weak:
    image.selectLayer(layer)
  else: complete(image.status.clip)

proc commit0delete(state: var NUndoState) =
  let step = addr state.step
  let image = state.image
  state.layer(step.layer)
  # Destroy Layer and React
  let layer = step.node
  if not isNil(layer):
    complete(image.status.clip)
    image.markLayer(layer)
    # Select Previous Layer
    if not step.weak:
      let node = image.owner.search(layer.tag.code)
      image.selectLayer(node.layer)
    # Destroy Layer
    layer.detach()
    layer.destroy()

proc commit0props(state: var NUndoState, redo: bool) =
  let
    step = addr state.step
    props = addr step.data.props
    image = state.image
  # Lookup Current Layer
  state.layer(step.layer)
  let layer = step.node
  let pro = addr layer.props
  let folded = layer.props.flags * {lpFolded}
  # Apply Layer Props and Adjust Flags
  if redo: pro[] = props.after
  else: pro[] = props.before
  pro.flags = pro.flags - {lpFolded} + folded
  # Mark Layer to Status
  complete(image.status.clip)
  image.markLayer(layer)

proc commit0reorder(state: var NUndoState, redo: bool) =
  let
    step = addr state.step
    reorder = addr step.data.reorder
    image = state.image
  # Lookup Current Layer
  state.layer(step.layer)
  let layer = step.node
  layer.detach()
  # Apply Layer Reordering
  if redo: image.attachLayer(layer, reorder.after)
  else: image.attachLayer(layer, reorder.before)
  # Mark Layer to Status
  complete(image.status.clip)
  image.markLayer(layer)

proc undo*(state: var NUndoState) =
  let
    step = addr state.step
    stage = addr state.stage
  state.layer(step.layer)
  # Canvas Undo Commands
  case step.cmd
  of ucCanvasNone: discard
  of ucCanvasProps: discard
  # Layer Undo Commands
  of ucLayerCreate: state.commit0delete()
  of ucLayerDelete: state.commit0create()
  of ucLayerTiles, ucLayerMark:
    state.commit0mark()
    stage.readBefore()
  of ucLayerProps: state.commit0props(false)
  of ucLayerReorder: state.commit0reorder(false)

proc redo*(state: var NUndoState) =
  let
    step = addr state.step
    stage = addr state.stage
  state.layer(step.layer)
  # Canvas Redo Commands
  case step.cmd
  of ucCanvasNone: discard
  of ucCanvasProps: discard
  # Layer Redo Commands
  of ucLayerCreate: state.commit0create()
  of ucLayerDelete: state.commit0delete()
  of ucLayerTiles, ucLayerMark:
    state.commit0mark()
    stage.readAfter()
  of ucLayerProps: state.commit0props(true)
  of ucLayerReorder: state.commit0reorder(true)
