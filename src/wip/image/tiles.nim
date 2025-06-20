# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2025 Cristian Camilo Ruiz <mrgaturus>

type
  NTileStatus* {.pure, size: 4.} = enum
    tsInvalid, tsZero, tsColor, tsBuffer
  NTileCells = ptr UncheckedArray[NTileCell]
  NTileCell* {.union.} = object
    color*: uint64
    buffer*: pointer
  # -- Tiled Grid --
  NTileReserved* = object
    x*, y*, w*, h*: cint
  NTileRegion = object
    x, y, w, h: cint
    ox, oy: cint
  NTileGrid = object
    ox, oy: cint
    w, h, len: cint
    cells: NTileCells
  # -- Tiled Image --
  NTileDepth* {.pure size: 4.} = enum
    depth0bpp
    depth2bpp
    depth4bpp
    depth8bpp
  NTileImage* = object
    bits*: NTileDepth
    bpp*, bytes*: cshort
    grid: NTileGrid

type
  NTile* = object
    x*, y*: cint
    # Tile Information
    status*: NTileStatus
    bpp*, bytes*: cshort
    # Tile Pointers
    data*: ptr NTileCell
    grid: ptr NTileGrid

# -------------------------
# Tile Image Grid: Creation
# -------------------------

# XXX: only works for 48-bit virtual pointers
const POINTER_MASK = 0xFFFFFFFFFFFF'u64
const ALPHA_MASK = not POINTER_MASK

proc createTileGrid(w, h: cint): NTileGrid =
  let count = w * h
  let cells = alloc0(NTileCell.sizeof * count)
  result.cells = cast[NTileCells](cells)
  # Store Dimensions
  result.w = w
  result.h = h
  result.len = count

proc destroy(grid: var NTileGrid) =
  let cells = grid.cells
  let l = grid.len  
  # Dealloc Buffers
  for i in 0 ..< l:
    var cell = cells[i]
    if (cell.color and ALPHA_MASK) == 0:
      if not isNil(cell.buffer):
        dealloc(cell.buffer)
  # Dealloc Grid Buffer
  dealloc(cells)

# -------------------------
# Tile Image Grid: Bounding
# -------------------------

proc region(grid: var NTileGrid, x, y: cint): NTileRegion =
  result.w = grid.w
  result.h = grid.h
  # Region Copy Offset
  result.ox = max(grid.ox - x, 0)
  result.oy = max(grid.oy - y, 0)

proc bounds(grid: var NTileGrid): NTileRegion =
  let
    w = grid.w
    h = grid.h
    # Grid Cells
    cells = grid.cells
  # Grid Bounds
  var
    x0, y0: cint = w
    x1, y1: cint
    # Grid Index
    idx: cint
  # Find Grid Bounds
  for y in 0 ..< h:
    for x in 0 ..< w:
      # Check Bounds
      if cells[idx].color > 0:
        x0 = min(x0, x)
        y0 = min(y0, y)
        x1 = max(x1, x + 1)
        y1 = max(y1, y + 1)
      # Next Index
      inc(idx)
  # Return Bounds
  result.x = x0
  result.y = y0
  result.w = x1 - x0
  result.h = y1 - y0

# ----------------------
# Tile Image Grid: Cells
# ----------------------

proc migrate(src, dst: var NTileGrid, r: NTileRegion) =
  let
    s0 = src.w
    s1 = dst.w
    # Copy Lane Byte Size
    bytes = r.w * sizeof(NTileCell)
    rows = r.h
    # Cell Buffers
    cells0 = src.cells
    cells1 = dst.cells
  # Migrate Cells to Region
  var
    idx0 = r.y * s0 + r.x
    idx1 = r.oy * s1 + r.ox
  for _ in 0 ..< rows:
    copyMem(addr cells1[idx1],
      addr cells0[idx0], bytes)
    # Next Row
    idx0 += s0
    idx1 += s1

proc index(grid: var NTileGrid, x, y: cint): cint =
  let
    x0 = x - grid.ox
    y0 = y - grid.oy
    # Grid Dimensions
    w = grid.w
    h = grid.h
    # Inside Check
    check0 = x0 >= 0 and y0 >= 0
    check1 = x0 < w and y0 < h
  # Calculate Index if is Inside
  if check0 and check1:
    y0 * w + x0
  else: grid.len

# -------------------
# Tile Image Creation
# -------------------

proc createTileImage*(bits: NTileDepth): NTileImage =
  let bpp = cshort(1 shl bits.ord)
  result = default(NTileImage)
  result.bits = bits
  # Define Tile Bytes
  if bits > depth0bpp:
    result.bytes = bpp * 1024
    result.bpp = bpp

proc region*(tiles: var NTileImage): NTileReserved =
  assert tiles.bits > depth0bpp
  let grid = addr tiles.grid
  # Return Reserved Grid Region
  result.x = grid.ox
  result.y = grid.oy
  result.w = grid.w
  result.h = grid.h

proc clear*(tiles: var NTileImage) =
  if tiles.grid.len > 0:
    destroy(tiles.grid)
    wasMoved(tiles.grid)

# ---------------------
# Tile Image Dimensions
# ---------------------

proc ensure*(tiles: var NTileImage, x, y, w, h: cint) =
  assert tiles.bits > depth0bpp
  # Source Copy Region
  let src = addr tiles.grid
  let r = src[].region(x, y)
  let w0 = max(src.w, x + w - src.ox) + r.ox
  let h0 = max(src.h, y + h - src.oy) + r.oy
  # Create Expanded Grid
  if src.len == 0:
    src[] = createTileGrid(w, h)
    # Adjust Offset
    src.ox = x
    src.oy = y
  elif w0 > src.w or h0 > src.h:
    var dst = createTileGrid(w0, h0)
    # Migrate to Destination
    src[].migrate(dst, r)
    dealloc(src.cells)
    # Adjust Offsets
    dst.ox = src.ox - r.ox
    dst.oy = src.oy - r.oy
    # Replace Grid
    src[] = dst

proc shrink*(tiles: var NTileImage) =
  assert tiles.bits > depth0bpp
  let src = addr tiles.grid
  let r = src[].bounds()
  # Deallocate Grid if there is nothing
  if (r.w or r.h) <= 0 and src.len > 0:
    dealloc(src.cells)
    src[] = default(NTileGrid)
  # Create Shrunk Grid
  elif r.w < src.w or r.h < src.h:
    var dst = createTileGrid(r.w, r.h)
    # Migrate to Destination
    src[].migrate(dst, r)
    dealloc(src.cells)
    # Adjust Offsets
    dst.ox = src.ox + r.x
    dst.oy = src.oy + r.y
    # Replace Grid
    src[] = dst

# ----------------------
# Tile Image Tile Lookup
# ----------------------

proc lookup(tiles: var NTileImage, idx: cint): NTile {.inline.} =
  result = default(NTile)
  let grid = addr tiles.grid
  var test = uint32(idx < grid.len)
  # Tile Information
  result.bpp = tiles.bpp
  result.bytes = tiles.bytes
  result.grid = grid
  # Tile Content
  if test > 0:
    result.data = addr grid.cells[idx]
    let color = result.data.color
    test += uint32 color > 0
    test += uint32 color > 0 and
      (color and ALPHA_MASK) == 0
  result.status = cast[NTileStatus](test)

proc find*(tiles: var NTileImage, x, y: cint): NTile =
  let idx = tiles.grid.index(x, y)
  # Lookup Tile and Store Position
  result = tiles.lookup(idx)
  result.x = x
  result.y = y

iterator items*(tiles: var NTileImage): var NTile =
  let
    grid = addr tiles.grid
    cells = grid.cells
    # Allocated Region
    ox = grid.ox
    oy = grid.oy
    w = ox + grid.w
    h = oy + grid.h
  var
    idx: cint
    tile: NTile
  # Explore Tiles
  for y in oy ..< h:
    for x in ox ..< w:
      # Check if Has Something
      if cells[idx].color > 0:
        tile = tiles.lookup(idx)
        tile.x = x
        tile.y = y
        # Yield Current Tile
        yield (addr tile)[]
      # Next Tile
      inc(idx)

# --------------------------
# Tile Image Tile Converters
# --------------------------

proc toColor*(tile: var NTile, color: uint64) =
  let data = tile.data
  assert not isNil(data) and not isNil(tile.grid)
  assert not (color > 0 and (color and ALPHA_MASK) == 0)
  # Deallocate Previous Buffer
  if (data.color and ALPHA_MASK) == 0:
    if not isNil(data.buffer):
      deallocShared(data.buffer)
  # Update Tile Data
  data.color = color
  let test = uint32(tsZero) + uint32(color > 0)
  tile.status = cast[NTileStatus](test)

proc toBuffer*(tile: var NTile) =
  let data = tile.data
  assert not isNil(data)
  assert not isNil(tile.grid)
  # Allocate Tile Buffer
  if isNil(data.buffer) or (data.color and ALPHA_MASK) > 0:
    let p = allocShared(tile.bytes shl 1)
    data.buffer = p
  # Update Tile Data
  tile.status = tsBuffer
