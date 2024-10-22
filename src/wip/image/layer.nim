# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
import nogui/bst
import tiles, ffi
export NBlendMode

# -------------------
# Layer Basic Objects
# -------------------

type
  NLayerCode* = NBinaryKey
  NLayerOwner* = NBinaryTree
  # Layer Properties Hook
  NLayerUser* = distinct pointer
  NLayerProc* = distinct pointer
  NLayerHook* = object
    fn*: NLayerProc
    ext*: pointer
  # Layer Properties
  NLayerKind* = enum
    lkColor
    lkMask
    lkStencil
    # Layer Tree
    lkFolder
  NLayerFlag* = enum
    lpVisible
    # Layer Props
    lpClipping
    lpProtectAlpha
    lpTarget
    lpLock
    # Layer Tree
    lpDraft
    lpFolded
  NLayerProps* = object
    mode*: NBlendMode
    flags*: set[NLayerFlag]
    opacity*: cfloat
    # GUI Labeling
    label*: string
  NLayerLevel* = object
    depth*: cint
    # Visible Checks
    hidden*: bool
    folded*: bool
  # Layer Properties Attaching
  NLayerAttach* {.size: 4, pure.} = enum
    ltAttachUnknown
    ltAttachNext
    ltAttachPrev
    ltAttachFolder
  NLayerTag* = object
    code: uint32
    mode: NLayerAttach
  NLayerOrder* = object
    target*: NLayer
    layer*: NLayer
    mode*: NLayerAttach
  # -- Layer Tree Object --
  NLayer* = ptr object
    next*, prev*: NLayer
    folder*: NLayer
    # Layer Properties
    code*: NLayerCode
    user*: NLayerUser
    hook*: NLayerHook
    props*: NLayerProps
    # Layer Data
    case kind*: NLayerKind
    of lkColor, lkMask, lkStencil:
      tiles*: NTileImage
    of lkFolder:
      first*, last*: NLayer

# ---------------------------
# Layer Creation/Deallocation
# ---------------------------

proc createLayer*(kind: NLayerKind): NLayer =
  result = create(result[].typeof)
  result.kind = kind
  # Prepare Tiled Image
  if kind != lkFolder:
    let bpp: cint = # Bytes-per-pixel
      if kind == lkColor: 4 else: 1
    result.tiles = createTileImage(bpp)

proc deallocBase(layer: NLayer) =
  let code = addr layer.code
  if not isNil(code.tree):
    discard remove(code.tree[], code)
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
  if layer.kind == lkFolder:
    layer.deallocFolder()
  layer.deallocBase()

# -------------------
# Layer Tree Location
# -------------------

proc layer*(code: ptr NLayerCode): NLayer =
  let p0 = cast[uint](addr result.code)
  let p1 = cast[uint](code) - p0
  # Return Layer from Code
  result = cast[NLayer](p1)

proc tag*(layer: NLayer): NLayerTag =
  let
    next = layer.next
    prev = layer.prev
    folder = layer.folder
  # Invalid Attachment
  result.code = layer.code.id
  result.mode = ltAttachUnknown
  # Attach Prev
  if not isNil(next):
    result.code = next.code.id
    result.mode = ltAttachPrev
  # Attach Next
  elif not isNil(prev):
    result.code = prev.code.id
    result.mode = ltAttachNext
  # Inside Folder
  elif not isNil(folder):
    result.code = folder.code.id
    result.mode = ltAttachFolder

proc level*(layer: NLayer): NLayerLevel =
  var folder = layer.folder
  # Walk to Outermost Levels
  while not isNil(folder):
    inc(result.depth)
    # Check Folder Status
    let flags = folder.props.flags
    if lpVisible notin flags:
      result.hidden = true
    if lpFolded in flags:
      result.folded = true
    # Next Outside Folder
    folder = folder.folder

# -----------------
# Layer Tree Folder
# -----------------

proc updateFolder(layer: NLayer) =
  let folder = layer.folder
  if isNil(folder): return
  # Update Folder Endpoints
  let
    first = folder.first
    last = folder.last
  # Check Ending Points
  if isNil(first) or first.prev == layer:
    folder.first = layer
  if isNil(last) or last.next == layer:
    folder.last = layer

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
  layer.updateFolder()

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
  layer.updateFolder()

proc attachInside*(folder, layer: NLayer) =
  assert folder.kind == lkFolder
  let first = folder.first
  # Attach To First
  if not isNil(first):
    first.attachPrev(layer)
  else: # Configure First
    layer.folder = folder
    layer.updateFolder()

proc attachCheck*(pivot, layer: NLayer, mode: NLayerAttach): bool =
  var outer {.cursor.} = pivot
  if mode == ltAttachNext:
    outer = outer.prev
  elif mode == ltAttachPrev:
    outer = outer.next
  # Check quick self-attachments
  if pivot == layer or outer == layer:
    return false
  # Check deep self-attachments
  outer = layer.folder
  while not isNil(outer):
    if outer == pivot:
      return false
    # Next Outermost
    outer = outer.folder
  # This is Attachable
  return true

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
