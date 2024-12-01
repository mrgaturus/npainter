# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
from typetraits import supportsCopyMem
import nogui/libs/zstd
import swap

type
  NUndoNumberF = float32|float64
  NUndoNumberI = int8|int16|int32|int64
  NUndoNumberU = uint8|uint16|uint32|uint64
  NUndoNumber* = NUndoNumberI | NUndoNumberU | NUndoNumberF
  # Undo Streaming Buffer
  NUndoBuffer* = ptr UncheckedArray[byte]
  NUndoRaw* = object
    buffer*: NUndoBuffer
    bytes*: int64
  # Undo Streaming Swap
  NUndoBlock* = object
    buffer*: NUndoBuffer
    bytes*: int64
    pos*: int64
  NUndoStream* = object
    swap*: ptr NUndoSwap
    bytes*, shift*, mask*: int
    # ZSTD Streaming
    seekRead: NUndoSeek
    auxRead: ZSTD_inBuffer
    zstdRead: ptr ZSTD_DStream
    zstdWrite: ptr ZSTD_CStream
    # Streaming Buffers
    buffer*: NUndoBuffer
    aux*: NUndoBuffer

proc builtin_ctz*(x: uint32): int32
  {.importc: "__builtin_ctz", cdecl.}

proc `=destroy`(raw: NUndoRaw) =
  if not isNil(raw.buffer):
    dealloc(raw.buffer)

# --------------------------------
# Undo Stream Creation/Destruction
# --------------------------------

proc configure*(stream: var NUndoStream, swap: ptr NUndoSwap) =
  let
    bytes0 = uint32 ZSTD_CStreamInSize()
    bytes1 = uint32 ZSTD_DStreamOutSize()
    shift = builtin_ctz max(bytes0, bytes1)
    bytes = 1 shl shift
    mask = bytes - 1
  # Configure Stream Buffer Sizes
  stream.swap = swap
  stream.bytes = bytes
  stream.shift = shift
  stream.mask = mask
  # Allocate Stream Buffers
  stream.buffer = cast[NUndoBuffer](alloc bytes)
  stream.aux = cast[NUndoBuffer](alloc bytes * 2)
  # Configure ZSTD Streaming
  stream.zstdRead = ZSTD_createDStream()
  stream.zstdWrite = ZSTD_createCStream()

proc destroy*(stream: var NUndoStream) =
  discard ZSTD_freeDStream(stream.zstdRead)
  discard ZSTD_freeCStream(stream.zstdWrite)
  # Dealloc Buffers
  dealloc(stream.buffer)
  dealloc(stream.aux)
  `=destroy`(stream)

# ---------------
# Undo Raw Buffer
# ---------------

proc createRaw*(bytes: int): NUndoRaw =
  let raw0 = alloc(bytes)
  result.buffer = cast[NUndoBuffer](raw0)
  result.bytes = bytes

proc createRaw*(src: pointer, bytes: int): NUndoRaw =
  result = createRaw(bytes)
  copyMem(result.buffer, src, bytes)

proc read*(raw: NUndoRaw, dst: pointer) =
  copyMem(dst, raw.buffer, raw.bytes)

# --------------------
# Undo Streaming Write
# --------------------

proc writeObject*[T: object](stream: ptr NUndoStream, value: T) =
  when supportsCopyMem(T):
    stream.swap[].write(addr value, sizeof T)
  else: {.error: "attempted write gc'ed type".}

proc writeNumber*(stream: ptr NUndoStream, value: NUndoNumber) =
  stream.swap[].write(addr value, sizeof value)

proc writeString*(stream: ptr NUndoStream, value: string) =
  let swap = stream.swap
  swap[].startSeek()
  swap[].write(cstring value, value.len)
  discard swap[].endSeek()

proc writeRaw*(stream: ptr NUndoStream, raw: var NUndoRaw) =
  let swap = stream.swap
  swap[].startSeek()
  swap[].write(raw.buffer, raw.bytes)
  discard swap[].endSeek()

# -------------------
# Undo Streaming Read
# -------------------

proc readObject*[T: object](stream: ptr NUndoStream): T =
  when supportsCopyMem(T):
    stream.swap[].read(addr result, sizeof T)
  else: {.error: "attempted read gc'ed type".}

proc readNumber*[T: NUndoNumber](stream: ptr NUndoStream): T =
  stream.swap[].read(addr result, sizeof T)

proc readString*(stream: ptr NUndoStream): string =
  let swap = stream.swap
  let seek = swap[].readSeek()
  # Read String Data
  result.setLen(seek.bytes)
  swap[].read(cstring result, seek.bytes)

proc readRaw*(stream: ptr NUndoStream, seek: NUndoSeek): NUndoRaw =
  let swap = stream.swap
  let raw0 = alloc(seek.bytes)
  # Allocate Raw Buffer
  result.bytes = seek.bytes
  result.buffer = cast[NUndoBuffer](raw0)
  # Read Raw Buffer
  swap[].setRead(seek)
  swap[].read(raw0, seek.bytes)

proc readRaw*(stream: ptr NUndoStream): NUndoRaw =
  let seek = stream.swap[].readSeek()
  result = stream.readRaw(seek)

# ------------------------------
# Undo Streaming Write: Compress
# ------------------------------

proc compressStart*(stream: ptr NUndoStream) =
  let code = ZSTD_initCStream(stream.zstdWrite, 4)
  if ZSTD_isError(code) > 0:
    echo ZSTD_getErrorName(code)
  # Start Compress Seeking
  stream.swap[].startSeek()

proc compressBlock*(stream: ptr NUndoStream,
    data: pointer, size: int, mode = ZSTD_e_continue) =
  let swap = stream.swap
  let ctx = stream.zstdWrite
  let chunk = stream.bytes
  # Prepare Buffer Accessors
  var src = ZSTD_inBuffer(src: data, size: size)
  var dst = ZSTD_outBuffer(dst: stream.aux, size: chunk)
  # Compress Buffer Block
  while src.pos < src.size:
    let r = ZSTD_compressStream2(ctx,
      addr dst, addr src, mode)
    # Stream Buffer to Swap File
    if r == 0 or dst.pos >= dst.size:
      swap[].write(dst.dst, dst.pos)
      dst.dst = stream.aux
      dst.pos = 0

proc compressEnd*(stream: ptr NUndoStream,
    data: pointer, size: int) =
  # Stream Last Block and End Compress Seeking
  stream.compressBlock(data, size, ZSTD_e_end)
  discard stream.swap[].endSeek()

proc compressRaw*(stream: ptr NUndoStream, raw: NUndoRaw) =
  stream.writeNumber(raw.bytes)
  stream.compressStart()
  stream.compressEnd(
    raw.buffer, raw.bytes)

# -------------------------------
# Undo Streaming Read: Decompress
# -------------------------------

proc decompressStart*(stream: ptr NUndoStream, seek: NUndoSeek) =
  let code = ZSTD_initDStream(stream.zstdRead)
  if ZSTD_isError(code) > 0:
    echo ZSTD_getErrorName(code)
  # Start Decompress Aux
  stream.auxRead = ZSTD_inBuffer(
    src: stream.aux)
  # Start Decompress Seeking
  stream.swap[].setRead(seek)
  stream.seekRead.bytes = seek.bytes
  stream.seekRead.pos = 0

proc decompressStart*(stream: ptr NUndoStream) =
  let seek = stream.swap[].readSeek()
  stream.decompressStart(seek)

proc decompressBlock*(stream: ptr NUndoStream): NUndoBlock =
  let swap = stream.swap
  let ctx = stream.zstdRead
  let chunk = stream.bytes
  # Prepare Buffer Accessors
  let seek = addr stream.seekRead
  let src = addr stream.auxRead
  var dst = ZSTD_outBuffer(
    dst: stream.buffer, size: chunk)
  # Decompress Buffer Block
  while true:
    if src.pos >= src.size:
      let bytes = min(seek.bytes, chunk)
      if bytes == 0: return result
      # Read Compressed Buffer
      swap[].read(stream.aux, bytes)
      src.src = stream.aux
      src.size = bytes
      src.pos = 0
      # Step Seek Bytes
      seek.bytes -= bytes
    # Decompress Current Chunk
    while src.pos < src.size:
      let r = ZSTD_decompressStream(ctx, addr dst, src)
      if r == 0 or dst.pos == dst.size:
        result.buffer = stream.buffer
        result.bytes = dst.pos
        # Current Position
        result.pos = seek.pos
        seek.pos += dst.pos
        return result

proc decompressRaw*(stream: ptr NUndoStream): NUndoRaw =
  let bytes = readNumber[int64](stream)
  let raw0 = cast[NUndoBuffer](alloc bytes)
  result.bytes = bytes
  result.buffer = raw0
  # Decompress Blocks
  stream.decompressStart(); while true:
    let chunk = stream.decompressBlock()
    if chunk.bytes == 0: break
    # Copy Decompress to Data
    copyMem(addr raw0[chunk.pos],
      chunk.buffer, chunk.bytes)
