# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
import ../image/[tiles, context]
import stream

type
  NUndoRegion* = object
    x*, y*, w*, h*: int32
  NUndoTile = object
    ux, uy: int32
    cell: uint64
  NUndoIndex = object
    next: int64
    count, cap: int32
    tiles: UncheckedArray[NUndoTile]
  # Undo Buffer Pagination
  NUndoBook* = object
    slabs: int64 # slabs count
    bpp: int32 # bytes per pixel
    bpt: int32 # bytes per tile
    pages: seq[NUndoBuffer]
  # Undo Book Codec
  NUndoStage* = object
    stream*: ptr NUndoStream
    tiles*: ptr NTileImage
    status*: ptr NImageStatus
    # Capturing Status
    stencil*: ptr NUndoBook
    before*: ptr NUndoBook
    after*: ptr NUndoBook
  NUndoCodec = object
    bytes, cap: int
    count, idx: int
    book: ptr NUndoBook
    list: ptr NUndoIndex
    # Streaming Buffers
    stream: ptr NUndoStream
    buffer: NUndoBuffer
    chunk: pointer
  NBookWrite {.borrow.} = distinct NUndoCodec
  NBookRead {.borrow.} = distinct NUndoCodec
  NBookTransfer* = object
    stream: ptr NUndoStream
    book: ptr NUndoBook
    idx, count: int

# ----------------------
# Undo Book Tile Manager
# ----------------------

proc uniform(tile: ptr NUndoTile): bool =
  (tile.ux and tile.uy and 1) == 0

proc point(tile: ptr NUndoTile): tuple[x, y: int32] =
  result.x = tile.ux shr 1
  result.y = tile.uy shr 1

proc point(tile: ptr NUndoTile, x, y: int32) =
  tile.ux = (x shl 1) or (tile.ux and 1)
  tile.uy = (y shl 1) or (tile.uy and 1)

proc asIndex(tile: ptr NUndoTile, idx: uint64) =
  tile.ux = tile.ux or 1
  tile.uy = tile.uy or 1
  # Store Cell as Index
  tile.cell = idx

proc asUniform(tile: ptr NUndoTile, value: uint64) =
  tile.ux = tile.ux and not 1
  tile.uy = tile.uy and not 1
  # Store Cell as Uniform
  tile.cell = value

# -----------------------------
# Undo Book Writter: Pagination
# -----------------------------

proc nextPage(codec: var NBookWrite) =
  let book = codec.book
  let buffer = cast[NUndoBuffer](alloc codec.bytes)
  # Make Buffer as Current
  book.pages.add(buffer)
  codec.buffer = buffer

proc nextSlab(codec: var NBookWrite): int =
  var idx = codec.idx
  if idx >= codec.cap:
    codec.nextPage()
    idx = 0
  # Configure Slab Pointer
  let bpt = codec.book.bpt
  let buffer = codec.buffer
  codec.chunk = addr buffer[idx * bpt]
  # Step Current Index
  result = codec.count
  codec.count = result + 1
  codec.book.slabs = result + 1
  codec.idx = idx + 1

proc nextList(codec: var NBookWrite) =
  let next = codec.nextSlab()
  if next > 0:
    codec.list.next = next
  # Configure List Capacity
  let bpt = codec.book.bpt
  let cap = (bpt - sizeof NUndoIndex) div sizeof(NUndoTile)
  let list = cast[ptr NUndoIndex](codec.chunk)
  # Replace Current List
  list.cap = int32(cap)
  codec.list = list

proc writeBook(stream: ptr NUndoStream, book: ptr NUndoBook): NBookWrite =
  let bytes = stream.bytes
  let cap = bytes div book.bpt
  # Define Writer Properties
  result.bytes = bytes
  result.cap = cap
  result.book = book
  result.stream = stream
  # Create First Page and List
  assert book.slabs == 0
  result.nextPage()
  result.nextList()

# ---------------------------
# Undo Book Writter: Encoding
# ---------------------------

proc write(codec: var NBookWrite, tile: NTile) =
  var list = codec.list
  if list.count == list.cap:
    codec.nextList()
    list = codec.list
  # Add Tile to List
  let idx = list.count
  let t0 = addr list.tiles[idx]
  # Configure Tile
  t0.point(tile.x, tile.y)
  if not tile.uniform:
    let idx = codec.nextSlab()
    t0.asIndex(uint64 idx)
    # Copy Tile Buffer
    copyMem(codec.chunk,
      tile.data.buffer, tile.bytes)
  else: t0.asUniform(tile.data.color)
  # Next Tile from List
  inc(list.count)

proc writeCopy0*(stage: ptr NUndoStage) =
  let book = stage.after
  assert book == stage.before
  assert book.slabs == 0
  # Prepare Tile Book Codec
  var codec = writeBook(stage.stream, book)
  let tiles = stage.tiles
  # Copy Tiles to Codec
  for tile in tiles[]:
    codec.write(tile)

proc writeMark0*(stage: ptr NUndoStage) =
  let book = stage.before
  assert book != stage.after
  assert book.slabs == 0
  # Prepare Tile Book Codec
  var codec = writeBook(stage.stream, book)
  let tiles = stage.tiles
  let status = stage.status
  # Copy Dirty Tiles to Codec
  for c in status[].checkAux():
    let tile = tiles[].find(c.tx, c.ty)
    codec.write(tile)

proc writeMark1*(stage: ptr NUndoStage) =
  let before = stage.before
  let book = stage.after
  assert book != before
  assert book.slabs == 0
  # Prepare Tile Book Codec
  var codec = writeBook(stage.stream, book)
  let tiles = stage.tiles
  # Copy Marked Tiles to Codec
  var page = before.pages[0]
  var list = cast[ptr NUndoIndex](page)
  while not isNil(list):
    let count = list.count
    for idx in 0 ..< count:
      let (x, y) = point(list.tiles[idx].addr)
      let tile = tiles[].find(x, y)
      codec.write(tile)
    # Step Next List
    let next = list.next
    if next == 0:
      wasMoved(list)
      continue
    # Calculate Next Chunk Page
    let idxPage = next div codec.cap
    let idxChunk = next mod codec.cap
    page = before.pages[idxPage]
    list = cast[ptr NUndoIndex](
      page[idxChunk * book.bpt].addr)

# -----------------------------
# Undo Book Reading: Pagination
# -----------------------------

proc nextPage(codec: var NBookRead) =
  let
    idx = codec.count
    book = codec.book
  if book.slabs == 0: return
  let page = book.pages[idx]
  # Read Book Page
  codec.buffer = page
  codec.count = idx + 1

proc nextList(codec: var NBookRead, next: int64) =
  let cap = codec.cap
  if next >= codec.count * cap:
    codec.nextPage()
  # Lookup List from Current Page
  let loc = (next mod cap) * codec.book.bpt
  let chunk = addr codec.buffer[loc]
  codec.list = cast[ptr NUndoIndex](chunk)
  codec.chunk = chunk
  codec.idx = 0

proc nextTile(codec: var NBookRead): ptr NUndoTile =
  let cap = codec.cap
  var idx = codec.idx
  var list = codec.list
  # Jump To Next List
  if idx >= list.cap:
    if list.next == 0:
      return
    codec.nextList(list.next)
    list = codec.list
    idx = codec.idx
  # Lookup Current Tile
  result = addr list.tiles[idx]
  if not result.uniform:
    var cell = cast[int64](result.cell)
    if cell >= codec.count * cap:
      codec.nextPage()
    # Lookup Current Tile Chunk
    cell = (cell mod cap) * codec.book.bpt
    codec.chunk = addr codec.buffer[cell]
  # Next Tile Index
  codec.idx = idx + 1

proc readBook(stream: ptr NUndoStream, book: ptr NUndoBook): NBookRead =
  let bytes = stream.bytes
  let cap = bytes div book.bpt
  # Define Writer Properties
  result.bytes = bytes
  result.cap = cap
  result.book = book
  result.stream = stream
  # Locate First Page and List
  assert book.slabs >= 0
  result.nextList(0)

# ---------------------------
# Undo Book Reading: Decoding
# ---------------------------

proc commit(codec: var NBookRead, stage: ptr NUndoStage) =
  let tiles = stage.tiles
  let status = stage.status
  # Read Codec Tiles
  while true:
    let t0 = nextTile(codec)
    if isNil(t0): return
    # Lookup Current Tile
    let (x, y) = t0.point()
    var tile = tiles[].find(x, y)
    # Apply Tile Changes
    if not t0.uniform:
      tile.toBuffer()
      copyMem(tile.data.buffer,
        codec.chunk, tile.bytes)
    else: tile.toColor(t0.cell)
    # Apply Dirty Changes
    status[].mark32(x, y)

proc readBefore*(stage: ptr NUndoStage) =
  var codec = readBook(stage.stream, stage.before)
  commit(codec, stage)

proc readAfter*(stage: ptr NUndoStage) =
  var codec = readBook(stage.stream, stage.after)
  commit(codec, stage)
