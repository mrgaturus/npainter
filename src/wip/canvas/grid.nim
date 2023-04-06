# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
from ../../libs/gl import GLuint

type
  # Canvas Dirty Region
  NCanvasDirty* = tuple[x, y, w, h: cint]
  NCanvasAligned = tuple[x0, y0, x1, y1: uint8]
  # Canvas Texture Tile
  NCanvasTile = object
    texture: GLuint
    # Dirty Region
    x0, y0: uint8
    x1, y1: uint8
  NCanvasBuffer = ref UncheckedArray[byte]
  NCanvasTiles = ptr UncheckedArray[NCanvasTile]
  # Canvas Tile Grid
  NCanvasGrid* = object
    w, h, lod: cint
    # Tile Grid Count
    count, unused: cint
    # Tile Grid Buffer
    buffer: NCanvasBuffer
    tiles, cache: NCanvasTiles
    
# --------------------
# Canvas Grid Creation
# --------------------

proc createCanvasGrid*(w256, h256: cint): NCanvasGrid =
  result.w = w256
  result.h = h256
  # Configure Grid
  let chunk = w256 * h256 * sizeof(NCanvasTile)
  # Allocate Viewport Locations
  unsafeNew(result.buffer, chunk shl 1)
  zeroMem(addr result.buffer[0], chunk shl 1)
  # Configure Grid Pointers
  result.tiles = cast[NCanvasTiles](addr result.buffer[0])
  result.cache = cast[NCanvasTiles](addr result.buffer[chunk])

# ------------------------
# Canvas Tile Dirty Region
# ------------------------

func clean*(tile: ptr NCanvasTile) =
  tile.x0 = 0xFF; tile.y0 = 0xFF
  tile.x1 = 0x00; tile.y1 = 0x00

func whole*(tile: ptr NCanvasTile) =
  tile.x0 = 0x00; tile.y0 = 0x00
  tile.x1 = 0x80; tile.y1 = 0x80

func align(dirty: NCanvasDirty): NCanvasAligned =
  var
    x0 = dirty.x
    y0 = dirty.y
    x1 = x0 + dirty.w
    y1 = y0 + dirty.h
  # Clamp Values
  x0 = clamp(x0, 0, 256)
  y0 = clamp(y0, 0, 256)
  x1 = clamp(x1, 0, 256)
  y1 = clamp(y1, 0, 256)
  # Return Values
  result.x0 = cast[uint8](x0 shr 1)
  result.y0 = cast[uint8](y0 shr 1)
  result.x1 = cast[uint8](x1 shr 1)
  result.y1 = cast[uint8](y1 shr 1)

func mark*(tile: ptr NCanvasTile, dirty: NCanvasDirty) =
  let (x0, y0, x1, y1) = dirty.align()
  # Extends Region
  tile.x0 = min(tile.x0, x0)
  tile.y0 = min(tile.y0, y0)
  tile.x1 = max(tile.x1, x1)
  tile.y1 = max(tile.y1, y1)

func dirty*(tile: ptr NCanvasTile): bool {.inline.} =
  tile.x0 < tile.x1 and tile.y0 < tile.y1

func invalid*(tile: ptr NCanvasTile): bool {.inline.} =
  (tile.x0 or tile.x1 or tile.y0 or tile.y1) == 0xFF

func region*(tile: ptr NCanvasTile): NCanvasDirty =
  let
    x0 = cast[cint](tile.x0) shl 1
    y0 = cast[cint](tile.y0) shl 1
    x1 = cast[cint](tile.x1) shl 1
    y1 = cast[cint](tile.y1) shl 1
  # Aligned Region
  result.x = x0
  result.y = y0
  result.w = x1 - x0
  result.h = y1 - y0

# -------------------
# Canvas Grid Manager
# -------------------

proc lookup*(grid: var NCanvasGrid; tx, ty: cint): ptr NCanvasTile =
  let 
    tiles = grid.tiles
    stride = grid.w
  # Return Located Tile
  addr tiles[ty * stride + tx]

proc clear*(grid: var NCanvasGrid) =
  let
    l = grid.w * grid.h
    cache = cast[NCanvasTiles](grid.tiles)
    tiles = cast[NCanvasTiles](grid.cache)
  # Swap Grid and Cache
  grid.tiles = tiles
  grid.cache = cache
  # Clear Grid
  zeroMem(tiles, l * NCanvasTile.sizeof)
  # Reset Cache Counter
  grid.count = 0
  grid.unused = 0

proc activate*(grid: var NCanvasGrid, x, y: cint) =
  if grid.count == 0:
    let
      # Tiled Position
      tx = x shr 8
      ty = y shr 8
      stride = grid.w
      idx = ty * stride + tx
      # Located Tile
      tile = addr grid.tiles[idx]
      prev = addr grid.cache[idx]
    var
      x0 = cast[uint8](tx)
      y0 = cast[uint8](ty)
    # Set Tile Position
    tile.x0 = x0
    tile.y0 = y0
    # Check Tile Texture
    if prev.texture > 0:
      tile.texture = prev.texture
    else:
      x0 = not x0
      y0 = not y0
    # Set Tile Invalid
    tile.x1 = x0
    tile.y1 = y0

proc recycle*(grid: var NCanvasGrid) =
  let
    caches = grid.cache
    tiles = grid.tiles
    # Buffer Size
    l = grid.w * grid.h
  # Reuse Unuse Tiles
  var 
    idx, cursor: cint
    tile, prev: ptr NCanvasTile
  while idx < l:
    tile = addr tiles[idx]
    prev = addr caches[idx]
    # Check if texture is not needed
    if prev.texture != tile.texture:
      tile = addr caches[cursor]
      tile.texture = prev.texture
      # Next Unused
      inc(cursor)
    # Next Tile
    inc(idx)
  # Set Unused Count
  grid.unused = cursor

proc prepare*(grid: var NCanvasGrid) =
  let
    caches = grid.cache
    tiles = grid.tiles
    # Buffer Size
    l = grid.w * grid.h
  # Locate Tiles
  var
    tex: GLuint
    idx, cursor: cint
    tile: ptr NCanvasTile
  while idx < l:
    tile = addr tiles[idx]
    tex = tile.texture
    # Check if there is a tile
    if tex > 0 or tile.invalid:
      caches[cursor] = tile[]
      # Next Cache
      inc(cursor)
    # Next Tile
    inc(idx)
  # Set Cached Count
  grid.count = cursor

# --------------------
# Canvas Dirty Manager
# --------------------

proc mark32*(grid: var NCanvasGrid; x32, y32: cint) =
  let
    tx = x32 shr 3
    ty = x32 shr 3
    # Dirty Region
    x0 = (x32 and not 0x7) shl 5
    y0 = (y32 and not 0x7) shl 5
    x1 = x0 + 32
    y1 = x1 + 32
    # Create Dirty Region
    dirty = (x0, y0, x1, y1)
    tile = grid.lookup(tx, ty)
  # Invalidate Tile
  tile.mark(dirty)

proc mark*(grid: var NCanvasGrid; dirty: sink NCanvasDirty) =
  let
    tx0 = dirty.x shr 8
    ty0 = dirty.y shr 8
    tx1 = (dirty.x + dirty.w + 255) shr 8
    ty1 = (dirty.x + dirty.w + 255) shr 8
  # Iterate Each Vertical
  for y in ty0 ..< ty1:
    var dirty0 = dirty
    # Iterate Each Horizontal
    for x in tx0 ..< tx1:
      let tile = grid.lookup(x, y)
      tile.mark(dirty0)
      # Step Region X
      dirty0.x -= 256
    # Step Region Y
    dirty0.y -= 256

# ----------------
# Canvas Iterators
# ----------------

iterator garbage*(grid: var NCanvasGrid): GLuint =
  let 
    l = grid.unused
    caches = grid.cache
  # Iterate Each Unuses
  var cursor: cint
  while cursor < l:
    yield caches[cursor].texture
    # Next Tile
    inc(cursor)

iterator caches*(grid: var NCanvasGrid): ptr NCanvasTile =
  let 
    l = grid.count
    caches = grid.cache
  # Iterate Each Cached
  var cursor: cint
  while cursor < l:
    yield addr caches[cursor]
    # Next Tile
    inc(cursor)
