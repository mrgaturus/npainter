# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
from ../image/chunk import mipmaps
import ../image/[tiles, context]
import stream, swap

type
  NUndoTile = object
    ux, uy: int32
    cell: uint64
  NUndoIndex = object
    next: int64
    count, cap: int32
    tiles: UncheckedArray[NUndoTile]
  # Undo Buffer Pagination
  NUndoRegion = NTileReserved
  NUndoBook* = object
    slabs: int64 # slabs count
    bpp: int32 # bytes per pixel
    bpt: int32 # bytes per tile
    region: NUndoRegion
    seek: NUndoSeek
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
  NBookStream* = object
    idx, step, count: int
    stream: ptr NUndoStream
    book: ptr NUndoBook

proc `=destroy`(book: NUndoBook) =
  for page in book.pages:
    dealloc(page)
  `=destroy`(book.pages)

# ------------------------
# Undo Book Region Manager
# ------------------------

proc regionTiles(stage: ptr NUndoStage): NUndoRegion =
  stage.tiles[].region()

proc regionMark(stage: ptr NUndoStage): NUndoRegion =
  let s = stage.status
  let c = s[].scale(s.clip)
  # Calculate Region Mark
  result.x = c.x0
  result.y = c.y0
  result.w = c.x1 - c.x0
  result.h = c.y1 - c.y0

proc regionTiles(stage: ptr NUndoStage, r: NUndoRegion) =
  stage.tiles[].ensure(r.x, r.y, r.w, r.h)

proc regionMark(stage: ptr NUndoStage, r: NUndoRegion) =
  let c = addr stage.status.clip
  # Set Status Clipping
  c.x0 = r.x shl 5
  c.y0 = r.y shl 5
  c.x1 = c.x0 + (r.w shl 5)
  c.y1 = c.y0 + (r.h shl 5)

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
  zeroMem(list, bpt)
  list.cap = int32(cap)
  codec.list = list

proc writeBook(stage: ptr NUndoStage, book: ptr NUndoBook): NBookWrite =
  let
    stream = stage.stream
    tiles = stage.tiles
    bytes = stream.bytes
    cap = bytes div tiles.bytes
  # Define Book Properties
  book.bpt = tiles.bytes
  book.bpp = tiles.bpp
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
  t0.point(tile.x, tile.y)
  # Define Tile Data
  if not tile.found:
    discard
  elif not tile.uniform:
    let idx = codec.nextSlab()
    t0.asIndex(uint64 idx)
    # Copy Tile Buffer
    copyMem(codec.chunk,
      tile.data.buffer, tile.bytes)
  else: t0.asUniform(tile.data.color)
  # Next Tile from List
  inc(list.count)

proc writeCopy0*(stage: ptr NUndoStage) =
  let book = stage.before
  assert book.slabs == 0
  # Prepare Tile Book Codec
  book.region = stage.regionTiles()
  var codec = writeBook(stage, book)
  let tiles = stage.tiles
  # Copy Tiles to Codec
  for tile in tiles[]:
    codec.write(tile)

proc writeMark0*(stage: ptr NUndoStage) =
  let book = stage.before
  assert book != stage.after
  assert book.slabs == 0
  # Prepare Tile Book Codec
  book.region = stage.regionMark()
  var codec = writeBook(stage, book)
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
  book.region = before.region
  var codec = writeBook(stage, book)
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

# ----------------------------
# Undo Book Writter: Streaming
# ----------------------------

proc streamBook*(stream: ptr NUndoStream, book: ptr NUndoBook): NBookStream =  
  result = NBookStream(
    step: stream.bytes div book.bpt,
    count: book.slabs,
    stream: stream,
    book: book
  )
  # Write Book Header
  stream.writeNumber(book.slabs)
  stream.writeNumber(book.bpp)
  stream.writeNumber(book.bpt)
  stream.writeObject(book.region)
  # Prepare Book Streaming
  if result.count > 0:
    stream.compressStart()
  else: stream.swap[].startSeek()

proc compressPage*(codec: var NBookStream): bool =
  let
    stream = codec.stream
    book = codec.book
    # Current Index
    step = codec.step
    count = codec.count
  result = count > 0
  if not result:
    return result
  # Calculate Byte Size
  let dabs = min(step, count)
  let bytes = dabs * book.bpt
  let page = book.pages[codec.idx]
  # Compress Current Page
  if count > dabs:
    stream.compressBlock(page, bytes)
  else: stream.compressEnd(page, bytes)
  # Next Book Page
  codec.count -= step
  inc(codec.idx)

# -----------------------------
# Undo Book Reading: Pagination
# -----------------------------

proc nextPage(codec: var NBookRead) =
  let
    idx = codec.count
    book = codec.book
  # Lookup Current Page
  if book.slabs == 0: return
  elif len(book.pages) > 0:
    codec.buffer = book.pages[idx]
    codec.count = idx + 1
  elif book.seek.bytes > 0:
    let chunk = codec.stream.decompressBlock()
    codec.buffer = chunk.buffer
    codec.count = idx + 1

proc nextList(codec: var NBookRead, next: int64) =
  let cap = codec.cap
  if next >= codec.count * cap:
    codec.nextPage()
  # Lookup List from Current Page
  let book = codec.book
  let bpt = book.bpt
  let loc = (next mod cap) * bpt
  var chunk = addr codec.buffer[loc]
  # Copy List when Streaming
  if book.seek.bytes > 0:
    let stream = codec.stream
    let idx = stream.bytes * 2 - bpt
    let ensure = addr stream.aux[idx]
    # Copy List in Stream Buffer
    copyMem(ensure, chunk, bpt)
    chunk = ensure
  # Define Current List
  codec.list = cast[ptr NUndoIndex](chunk)
  codec.chunk = chunk
  codec.idx = 0

proc nextTile(codec: var NBookRead): ptr NUndoTile =
  let cap = codec.cap
  var idx = codec.idx
  var list = codec.list
  # Jump To Next List
  if idx >= list.count:
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
  # Start Decompression if Stream
  if book.seek.bytes > 0:
    stream.decompressStart(book.seek)
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
      tile.mipmaps()
    else: tile.toColor(t0.cell)
    # Apply Dirty Changes
    status[].mark32(x, y)

proc readBook(stage: ptr NUndoStage, book: ptr NUndoBook) =
  if book.slabs > 0:
    stage.regionTiles(book.region)
    stage.regionMark(book.region)
    # Commit Book Tiles to Stage Tiles
    var codec = readBook(stage.stream, book)
    commit(codec, stage)

proc readRegion(stage: ptr NUndoStage) =
  let r0 = stage.before.region
  let r1 = stage.after.region
  # Check Stage Region
  if r0 != r1:
    var m: NImageMark
    m.expand(r0.x, r0.y, r0.w, r0.h)
    m.expand(r1.x, r1.y, r1.w, r1.h)
    m.x0 *= 32; m.y0 *= 32
    m.x1 *= 32; m.y1 *= 32
    # Mark Status Tiles
    stage.status[].clip = m
    stage.status[].mark(m)

proc readBefore*(stage: ptr NUndoStage) =
  stage.readBook(stage.before)
  stage.readRegion()

proc readAfter*(stage: ptr NUndoStage) =
  stage.readBook(stage.after)
  stage.readRegion()

# ----------------------------
# Undo Book Reading: Streaming
# ----------------------------

proc peekBook*(stream: ptr NUndoStream, book: ptr NUndoBook) =
  book.slabs = readNumber[int64](stream)
  book.bpp = readNumber[int32](stream)
  book.bpt = readNumber[int32](stream)
  # Peek Book Buffer Streaming
  book.region = readObject[NUndoRegion](stream)
  book.seek = stream.swap[].skipSeek()
