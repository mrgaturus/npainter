# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
from nogui/libs/gl import GLuint

type
  # Canvas Texture Tile
  NCanvasDirty* = tuple[x, y, w, h: cint]
  NCanvasSample = array[4, GLuint]
  NCanvasTile* = object
    texture*: GLuint
    tx*, ty*: uint8
    # Dirty Region
    dx, dy: uint8
  NCanvasBatch = object
    tile*: ptr NCanvasTile
    sample*: ptr NCanvasSample
  # Canvas Buffer Pointers
  NCanvasBuffer = ref UncheckedArray[byte]
  NCanvasTiles = ptr UncheckedArray[NCanvasTile]
  NCanvasLocs = ptr UncheckedArray[ptr NCanvasTile]
  NCanvasSamples = ptr UncheckedArray[NCanvasSample]
  # Canvas Tile Grid
  NCanvasGrid* = object
    w, h: cint
    # Tile Grid Count
    count*, unused: cint
    # Tile Grid Buffer
    buffer: NCanvasBuffer
    tiles, aux: NCanvasTiles
    cache: NCanvasSamples
    
# --------------------
# Canvas Grid Creation
# --------------------

proc createCanvasGrid*(w256, h256: cint): NCanvasGrid =
  result.w = w256
  result.h = h256
  # Configure Grid
  let
    l = w256 * w256
    chunk = l * sizeof(NCanvasSample)
    half = l * sizeof(NCanvasTile)
  # Allocate Viewport Locations
  unsafeNew(result.buffer, chunk shl 1)
  zeroMem(addr result.buffer[0], chunk shl 1)
  # Configure Grid Pointers
  result.tiles = cast[NCanvasTiles](addr result.buffer[0])
  result.aux = cast[NCanvasTiles](addr result.buffer[half])
  result.cache = cast[NCanvasSamples](addr result.buffer[chunk])

# ----------------------
# Canvas Tile Dirty Mark
# ----------------------

func clean*(tile: ptr NCanvasTile) =
  tile.dx = 0x08
  tile.dy = 0x08

func whole*(tile: ptr NCanvasTile) =
  tile.dx = 0x80
  tile.dy = 0x80

func mark*(tile: ptr NCanvasTile, x, y: cint) =
  let
    x32 = cast[uint8](x shr 5 and 0x7)
    y32 = cast[uint8](y shr 5 and 0x7)
    # Dirty Region
    dx = tile.dx
    dy = tile.dy
  var
    x0 = dx and 0xF
    y0 = dy and 0xF
    x1 = dx shr 4
    y1 = dy shr 4
  # Expand Dirty Region
  x0 = min(x0, x32)
  y0 = min(y0, y32)
  x1 = max(x1, x32 + 1)
  y1 = max(y1, y32 + 1)
  # Pack Dirty Region
  tile.dx = x0 or (x1 shl 4)
  tile.dy = y0 or (y1 shl 4)

# -----------------------
# Canvas Tile Dirty Check
# -----------------------

func dirty*(tile: ptr NCanvasTile): bool {.inline.} =
  (tile.dx or tile.dy) != 0x08

func invalid*(tile: ptr NCanvasTile): bool {.inline.} =
  (tile.dx or tile.dy) > 0x88

func region*(tile: ptr NCanvasTile): NCanvasDirty =
  let
    dx = cast[cint](tile.dx)
    dy = cast[cint](tile.dy)
  # Check if is Actually Dirty
  if tile.dirty and tile.texture > 0:
    result.x = (dx and 0xF) shl 5
    result.y = (dy and 0xF) shl 5
    # Dirty 32x32 Dimensions
    result.w = (dx shr 4) shl 5 - result.x
    result.h = (dy shr 4) shl 5 - result.y

# -------------------
# Canvas Grid Manager
# -------------------

proc clear*(grid: var NCanvasGrid) =
  let
    l = grid.w * grid.h
    prev = cast[NCanvasTiles](grid.tiles)
    tiles = cast[NCanvasTiles](grid.aux)
  # Swap Grid and Cache
  grid.tiles = tiles
  grid.aux = prev
  # Clear Grid
  zeroMem(tiles, l * NCanvasTile.sizeof)
  # Reset Cache Counter
  grid.count = 0
  grid.unused = 0

proc activate*(grid: var NCanvasGrid, tx, ty: cint) =
  if grid.count == 0:
    let
      # Tiled Position
      stride = grid.w
      idx = ty * stride + tx
      # Located Tile
      tile = addr grid.tiles[idx]
      prev = addr grid.aux[idx]
    # Set Tile Position
    tile.tx = cast[uint8](tx)
    tile.ty = cast[uint8](ty)
    # Check Tile Texture
    if prev.texture > 0:
      tile[] = prev[]
    else:
      tile.dx = 0xFF
      tile.dy = 0xFF

proc recycle*(grid: var NCanvasGrid) =
  let
    prevs = grid.aux
    tiles = grid.tiles
    # Buffer Size
    l = grid.w * grid.h
  # Reuse Unuse Tiles
  var 
    idx, cursor: cint
    tile, prev: ptr NCanvasTile
  while idx < l:
    tile = addr tiles[idx]
    prev = addr prevs[idx]
    # Check if texture is not needed
    if prev.texture != tile.texture:
      tile = addr prevs[cursor]
      tile.texture = prev.texture
      # Next Unused
      inc(cursor)
    # Next Tile
    inc(idx)
  # Set Unused Count
  grid.unused = cursor

proc prepare*(grid: var NCanvasGrid) =
  let
    locs = cast[NCanvasLocs](grid.aux)
    tiles = grid.tiles
    # Buffer Size
    l = grid.w * grid.h
  # Locate Tiles
  var
    idx, cursor: cint
    tile: ptr NCanvasTile
  while idx < l:
    tile = addr tiles[idx]
    # Check if there is a tile
    if tile.texture > 0 or tile.invalid:
      locs[cursor] = tile
      # Next Cache
      inc(cursor)
    # Next Tile
    inc(idx)
  # Set Cached Count
  grid.count = cursor

# -------------------
# Canvas Grid Sampler
# -------------------

proc sample(grid: var NCanvasGrid; tx, ty: cint): GLuint =
  let 
    tiles = grid.tiles
    w = grid.w
    h = grid.h
  # Check if is inside grid
  if tx >= 0 and ty >= 0 and tx < w and ty < h:
    let idx = ty * w + tx
    result = tiles[idx].texture

proc sample*(grid: var NCanvasGrid; dummy: GLuint; tx, ty: cint): NCanvasSample =
  let
    tx1 = tx + 1
    ty1 = ty + 1
  result[0] = grid.sample(tx, ty)
  result[1] = grid.sample(tx1, ty)
  result[2] = grid.sample(tx, ty1)
  result[3] = grid.sample(tx1, ty1)
  # Replace Zeros With Dummy
  for tex in mitems(result):
    if tex == 0: tex = dummy

# ---------------------
# Canvas Grid Iterators
# ---------------------

iterator garbage*(grid: var NCanvasGrid): GLuint =
  let 
    l = grid.unused
    prev = grid.aux
  # Iterate Garbage
  var idx: cint
  while idx < l:
    yield prev[idx].texture
    # Next Tile
    inc(idx)

iterator batches*(grid: var NCanvasGrid): NCanvasBatch =
  let 
    l = grid.count
    locs = cast[NCanvasLocs](grid.aux)
    cache = grid.cache
  # Iterate Each Batch
  var
    idx: cint
    result: NCanvasBatch
  # Iterate Samples
  while idx < l:
    result.tile = locs[idx]
    result.sample = addr cache[idx]
    # Yield Render Batch
    yield result
    # Next Tile
    inc(idx)

iterator tiles*(grid: var NCanvasGrid): ptr NCanvasTile =
  let 
    l = grid.count
    locs = cast[NCanvasLocs](grid.aux)
  # Iterate Each Batch
  var idx: cint
  # Iterate Samples
  while idx < l:
    yield locs[idx]
    # Next Tile
    inc(idx)

iterator samples*(grid: var NCanvasGrid): NCanvasSample =
  let 
    l = grid.count
    cache = grid.cache
  # Iterate Each Batch
  var idx: cint
  # Iterate Samples
  while idx < l:
    yield cache[idx]
    # Next Tile
    inc(idx)
