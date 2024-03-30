# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
import tiles, ffi
export NBlendMode

# -------------------
# Layer Basic Objects
# -------------------

type
  # Layer Binding
  NLayerProc* = distinct pointer
  NLayerHook* = object
    fn*: NLayerProc
    ext*: pointer
  NLayerOwner* {.borrow.} =
    distinct ptr cint
  # Layer Properties
  NLayerKind* = enum
    lkColor
    lkMask
    lkStencil
    # Layer Tree
    lkFolder
  NLayerFlags* = enum
    lpVisible
    # Clipping
    lpProtectAlpha
    lpClipping
    # GUI Hint
    lpDraft
    lpTarget
    lpLock
  NLayerProps* = object
    opacity*: cfloat
    mode*: NBlendMode
    flags*: set[NLayerFlags]
    # GUI Hint
    label*: string
  # Layer Properties Tag
  NLayerTagMode = enum
    ltAttachNext
    ltAttachPrev
    ltAttachFolder
    ltUnknown
  NLayerTag* = object
    id, loc: cint
    mode: NLayerTagMode
  # -- Layer Tree Object --
  NLayer* = ptr object
    next*, prev*: NLayer
    # Folder Nesting
    folder*: NLayer
    level*: cint
    # Layer Properties
    hook*: NLayerHook
    owner*: NLayerOwner
    props*: NLayerProps
    tag*: NLayerTag
    # Layer Data
    case kind*: NLayerKind
    of lkColor, lkMask, lkStencil:
      tiles*: NTileImage
    of lkFolder:
      first*, last*: NLayer

# ---------------------------
# Layer Creation/Deallocation
# ---------------------------

proc createLayer*(kind: NLayerKind, owner: NLayerOwner): NLayer =
  # Alloc New Layer
  result = create(result[].type)
  result[] = default(result[].type)
  # Prepare Tiled Image
  if kind != lkFolder:
    let bpp: cint = # Bytes-per-pixel
      if kind == lkColor: 4 else: 1
    # Create Tiled Image
    result.tiles = createTileImage(bpp)
  # Define Initial Properties
  result.owner = owner
  result.kind = kind
  # Define Layer ID from Owner
  let own = cast[ptr cint](owner)
  result.tag.id = own[]

# -----------------
# Layer Destruction
# -----------------

proc deallocBase(layer: NLayer) =
  # Dealloc Tiles and Layer
  if layer.kind != lkFolder:
    destroy(layer.tiles)
  # Dealloc Layer
  `=destroy`(layer[])
  dealloc(layer)

proc deallocFolder(folder: NLayer) =
  assert folder.kind == lkFolder
  # Dealloc Recursively Layers
  var c = folder.first
  while not isNil(c):
    # Dealloc Folder
    if c.kind == lkFolder:
      c.deallocFolder()
    # Dealloc Base
    let next = c.next
    c.deallocBase()
    c = next

proc destroy*(layer: NLayer) =
  # Dealloc Recursive
  if layer.kind == lkFolder:
    layer.deallocFolder()
  # Dealloc Base
  layer.deallocBase()

# -------------------
# Layer Tree Updating
# -------------------

proc updateTag(layer: NLayer) =
  let
    next = layer.next
    prev = layer.prev
    folder = layer.folder
    tag = addr layer.tag
  # Attach Prev
  if not isNil(next):
    tag.loc = next.tag.id
    tag.mode = ltAttachPrev
  # Attach Next
  elif not isNil(prev):
    tag.loc = prev.tag.id
    tag.mode = ltAttachNext
  # Inside Folder
  elif not isNil(folder):
    tag.loc = folder.tag.id
    tag.mode = ltAttachFolder
  else: # unreached
    tag.loc = tag.id
    tag.mode = ltUnknown

proc updateLevel(layer: NLayer) =
  var level: cint
  # Update Folder Status
  let folder = layer.folder
  if not isNil(folder):
    let
      first = folder.first
      last = folder.last
    # Check Ending Points
    if isNil(first) or first.prev == layer:
      folder.first = layer
    if isNil(last) or last.next == layer:
      folder.last = layer
    # Set Next Nesting
    level = folder.level + 1
  # Set Current Level
  layer.level = level

# --------------------
# Layer Tree Attaching
# --------------------

proc attachPrev*(pivot, layer: NLayer) =
  let prev = pivot.prev
  # Replace Pivot Prev
  if not isNil(prev):
    prev.next = layer
  pivot.prev = layer
  # Set Current Position
  layer.next = pivot
  layer.prev = prev
  # Update Layer Status
  layer.folder = pivot.folder
  layer.updateLevel()
  layer.updateTag()

proc attachNext*(pivot, layer: NLayer) =
  let next = pivot.next
  # Replace Pivot Next
  if not isNil(next):
    next.prev = layer
  pivot.next = layer
  # Set Current Position
  layer.prev = pivot
  layer.next = next
  # Update Layer Status
  layer.folder = pivot.folder
  layer.updateLevel()
  layer.updateTag()

proc attachInside*(folder, layer: NLayer) =
  assert folder.kind == lkFolder
  let first = folder.first
  # Attach To First
  if not isNil(first):
    first.attachPrev(layer)
  else: # Configure First
    layer.folder = folder
    layer.updateLevel()
    layer.updateTag()

# --------------------
# Layer Tree Detaching
# --------------------

proc detach*(layer: NLayer) =
  let
    next = layer.next
    prev = layer.prev
    folder = layer.folder
  # Deatach Layer
  if not isNil(prev):
    prev.next = next
  if not isNil(next):
    next.prev = prev
  # Remove Slibings
  layer.next = nil
  layer.prev = nil
  # Detach Folder
  if isNil(folder): return
  if folder.first == layer:
    folder.first = next  
  if folder.last == layer:
    folder.last = prev
  # Remove Folder
  layer.folder = nil
  layer.level = 0
