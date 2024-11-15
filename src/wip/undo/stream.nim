# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
import nogui/libs/zstd

type
  NUndoBuffer* = ptr UncheckedArray[byte]
  NUndoRaw* = object
    buffer0*: NUndoBuffer
    bytes0*: int64
  # Undo Streaming Pages
  NUndoStream* = object
    bytes*, shift*, mask*: int
    # Streaming Buffers
    buffer*: NUndoBuffer
    swap*: NUndoBuffer

proc builtin_ctz*(x: uint32): int32
  {.importc: "__builtin_ctz", cdecl.}

# --------------------------------
# Undo Stream Creation/Destruction
# --------------------------------

proc configure*(stream: var NUndoStream) =
  let
    bytes0 = uint32 ZSTD_CStreamInSize()
    bytes1 = uint32 ZSTD_DStreamOutSize()
    shift = builtin_ctz max(bytes0, bytes1)
    bytes = 1 shl shift
    mask = bytes - 1
  # Configure Stream Buffer Sizes
  stream.bytes = bytes
  stream.shift = shift
  stream.mask = mask
  # Allocate Stream Buffers
  stream.buffer = cast[NUndoBuffer](alloc bytes)
  stream.swap = cast[NUndoBuffer](alloc bytes * 2)

proc destroy*(stream: var NUndoStream) =
  dealloc(stream.buffer)
  dealloc(stream.swap)
  `=destroy`(stream)

# ---------------
# Undo Stream Raw
# ---------------

proc writeRaw*(src: pointer, bytes: int): NUndoRaw =
  let raw0 = alloc(bytes)
  copyMem(raw0, src, bytes)
  # Store Raw Buffer
  result.buffer0 = cast[NUndoBuffer](raw0)
  result.bytes0 = bytes

proc readRaw*(stream: var NUndoStream, raw: NUndoRaw, dst: pointer) =
  copyMem(dst, raw.buffer0, raw.bytes0)
