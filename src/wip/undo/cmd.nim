# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
from nogui/bst import search
import book, stream, swap
import ../image/[layer, tiles]
import ../image

type
  NUndoCopy = object
    kind: NLayerKind
    props: NLayerProps
    tag: NLayerTag
    # Layer Tiles Copy
    region: NUndoRegion
    book: NUndoBook
  NUndoMark = object
    region: NUndoRegion
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
  NUndoCommand* {.pure.} = enum
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
    layer*: uint32
    stage*: uint8
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

proc effect*(cmd: NUndoCommand): NUndoEffect =
  const effects = [
    ucCanvasNone: ueCanvasProps,
    ucCanvasProps: ueCanvasProps,
    # Layer Commands Effects
    ucLayerCreate: ueLayerList,
    ucLayerDelete: ueLayerList,
    ucLayerTiles: ueLayerTiles,
    ucLayerMark: ueLayerTiles,
    ucLayerProps: ueLayerProps,
    ucLayerReorder: ueLayerList
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

# -------------------------
# Undo Command RAM: Capture
# -------------------------

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
  if not isNil(layer) and layer.kind != lkFolder:
    stage.tiles = addr layer.tiles

proc capture*(state: var NUndoState) =
  let step = addr state.step
  let stage = addr state.stage
  # Canvas Capture Commands
  case step.cmd
  of ucCanvasNone: discard
  of ucCanvasProps: discard
  # Layer Capture Commands
  of ucLayerCreate: discard
  of ucLayerDelete: discard
  of ucLayerTiles: discard
  of ucLayerMark:
    stage.before = addr step.data.mark.before
    stage.after = addr step.data.mark.after
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
  of ucLayerProps: discard
  of ucLayerReorder: discard

# --------------------------
# Undo Command RAM: Dispatch
# --------------------------

proc undo*(state: var NUndoState) =
  let step = addr state.step
  let stage = addr state.stage
  # Canvas Undo Commands
  case step.cmd
  of ucCanvasNone: discard
  of ucCanvasProps: discard
  # Layer Undo Commands
  of ucLayerCreate: discard
  of ucLayerDelete: discard
  of ucLayerTiles, ucLayerMark:
    stage.before = addr step.data.mark.before
    stage.after = addr step.data.mark.after
    stage.readBefore()
  of ucLayerProps: discard
  of ucLayerReorder: discard

proc redo*(state: var NUndoState) =
  let step = addr state.step
  let stage = addr state.stage
  # Canvas Redo Commands
  case step.cmd
  of ucCanvasNone: discard
  of ucCanvasProps: discard
  # Layer Redo Commands
  of ucLayerCreate: discard
  of ucLayerDelete: discard
  of ucLayerTiles, ucLayerMark:
    stage.before = addr step.data.mark.before
    stage.after = addr step.data.mark.after
    stage.readAfter()
  of ucLayerProps: discard
  of ucLayerReorder: discard
