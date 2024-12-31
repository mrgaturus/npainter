# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>

type
  NTileStatus* {.pure, size: 4.} = enum
    tsInvalid, tsZero, tsColor, tsBuffer
  NTileCell* {.union.} = object
    color*: uint64
    buffer*: pointer
  # Tile Grid Pointers
  NTileCells = ptr UncheckedArray[NTileCell]
  NTileBits = ptr UncheckedArray[uint32]
  # -- Tiled Grid --
  NTileReserved* = object
    x*, y*, w*, h*: cint
  NTileRegion = object
    x, y, w, h: cint
    ox, oy: cint
  NTileGrid = object
    ox, oy: cint
    w, h, len: cint
    # Grid Buffers
    cells: NTileCells
    bits: NTileBits
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

# ------------------------
# Tile Image Grid Creation
# ------------------------

proc createTileGrid(w, h: cint): NTileGrid =
  let
    l0 = w * h
    l1 = (l0 + 0x1F) shr 5
    # Grid Buffers
    cells = alloc0(l0 * NTileCell.sizeof)
    bits = alloc0(l1 * uint32.sizeof)
  # Store Buffer Pointers
  result.cells = cast[NTileCells](cells)
  result.bits = cast[NTileBits](bits)
  # Store Dimensions
  result.w = w
  result.h = h
  result.len = l0

proc destroy(grid: var NTileGrid) =
  # Destroy Allocated Buffers
  let
    l = grid.len
    cells = grid.cells
    bits = grid.bits
  for i in 0 ..< l:
    let
      tile = cells[i]
      bit = bits[i shr 5] shr (i and 0x1F)
    # Allocated Buffer?
    if (bit and 1) > 0:
      dealloc(tile.buffer)
  # Dealloc Buffers
  dealloc(cells)
  dealloc(bits)

# ------------------------
# Tile Image Grid Bounding
# ------------------------

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

# -------------------------
# Tile Image Grid Migration
# -------------------------

proc copyCells(src, dst: var NTileGrid, r: NTileRegion) =
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
    # Copy Source Row to Destination Row
    copyMem(addr cells1[idx1], addr cells0[idx0], bytes)
    # Next Row
    idx0 += s0
    idx1 += s1

proc copyBits(src, dst: var NTileGrid, r: NTileRegion) =
  let 
    s0 = src.w
    s1 = dst.w
    # Bit Buffers
    bits0 = src.bits
    bits1 = dst.bits
  var
    sdx0, idx0: int32
    sdx1, idx1: int32
  # Locate Index
  sdx0 = r.y * s0 + r.x
  sdx1 = r.oy * s1 + r.ox
  # Migrate Bit Rows
  for _ in 0 ..< r.h:
    idx0 = sdx0
    idx1 = sdx1
    # Migrate Lane
    for _ in 0 ..< r.w:
      # Nim Integer Inference is Annoying
      {.emit: "unsigned int bit = `idx0` & 0x1F;".}
      {.emit: "bit = `bits0`[`idx0` >> 5] >> bit & 1;".}
      {.emit: "bit = bit << (`idx1` & 0x1F);".}
      {.emit: "`bits1`[`idx1` >> 5] |= bit;".}
      # Next Index
      inc(idx0)
      inc(idx1)
    # Next Row
    sdx0 += s0
    sdx1 += s1

# ---------------------
# Tile Image Grid Cells
# ---------------------

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

# --------------------
# Tile Image Grid Bits
# --------------------

# -- Bit Manipulation --
proc mark(grid: var NTileGrid, cell: ptr NTileCell) =
  let
    cells = grid.cells
    bits = grid.bits
  # Nim Integer Inference is Annoying
  {.emit: "int idx = `cell` - `cells`;".}
  {.emit: "unsigned int bit = 1 << (`idx` & 0x1F);".}
  {.emit: "`bits`[`idx` >> 5] |= bit;".}

proc blank(grid: var NTileGrid, cell: ptr NTileCell) =
  let
    cells = grid.cells
    bits = grid.bits
  # Nim Integer Inference is Annoying
  {.emit: "int idx = `cell` - `cells`;".}
  {.emit: "unsigned int bit = 1 << (`idx` & 0x1F);".}
  {.emit: "`bits`[`idx` >> 5] &= ~bit;".}

# -- Bit Lookup --
proc mask(grid: var NTileGrid, idx: cint): uint32 =
  result = grid.bits[idx shr 5]
  result = result shr (idx and 0x1F) and 1

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
    src[].copyCells(dst, r)
    src[].copyBits(dst, r)
    # Deallocate Source
    dealloc(src.cells)
    dealloc(src.bits)
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
    dealloc(src.bits)
    # Restore to Default
    src[] = default(NTileGrid)
  # Create Shrunk Grid
  elif r.w < src.w or r.h < src.h:
    var dst = createTileGrid(r.w, r.h)
    # Migrate to Destination
    src[].copyCells(dst, r)
    src[].copyBits(dst, r)
    # Deallocate Source
    dealloc(src.cells)
    dealloc(src.bits)
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
    test += uint32 result.data.color > 0
    test += uint32 grid[].mask(idx) > 0
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
  let grid = tile.grid
  let status = tile.status
  assert status > tsInvalid
  # Deallocate Previous Buffer
  if status == tsBuffer:
    deallocShared(data.buffer)
    grid[].blank(data)
  # Update Tile Data
  data.color = color
  const test = [false: tsZero, true: tsColor]
  tile.status = test[color > 0]

proc toBuffer*(tile: var NTile) =
  let data = tile.data
  let grid = tile.grid
  let status = tile.status
  assert status > tsInvalid
  # Allocate Buffer
  if status == tsBuffer: return
  let p = allocShared(tile.bytes shl 1)
  data.buffer = p
  grid[].mark(data)
  # Update Tile Data
  tile.status = tsBuffer
