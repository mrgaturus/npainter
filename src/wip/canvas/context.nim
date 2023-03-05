# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>

type
  NCanvasMemory = ref UncheckedArray[byte]
  NCanvasMap = ptr UncheckedArray[byte]
  NCanvasContext* = object
    chunk: cint
    # Canvas Dimensions
    w*, w64*, rw64*: cint 
    h*, h64*, rh64*: cint
    # Canvas Layers
    memory: NCanvasMemory
    # Memory Block Sections
    buffer0*, buffer1*: NCanvasMap
    mask*, selection*: NCanvasMap
    original, mipmaps: NCanvasMap

# ------------------------
# Canvas Buffer Allocation
# ------------------------

proc createCanvasContext*(w, h: cint): NCanvasContext =
  # Canvas Dimensions
  result.w = w
  result.h = h
  # Canvas Tiled Dimensions
  result.rw64 = (64 - w) and 63
  result.rh64 = (64 - h) and 63
  result.w64 = w + result.rw64
  result.h64 = h + result.rh64
  # Calculate Memory Size
  let
    chunk = result.w64 * result.h64
    chunkColor = chunk shl 2
    chunkMask = chunk shl 1
    chunkMipmap =
      (chunkColor shr 2) + 
      (chunkColor shr 4) +
      (chunkColor shr 6) +
      (chunkColor shr 8) +
      (chunkColor shr 10)
    chunkTotal =
      chunkColor * 3 +
      chunkMask * 2 +
      chunkMipmap
  # Allocate New Canvas
  unsafeNew(result.memory, chunkTotal)
  zeroMem(addr result.memory[0], chunkTotal)
  # Locate Buffer Pointers
  result.buffer0 = cast[NCanvasMap](addr result.memory[0])
  result.buffer1 = cast[NCanvasMap](addr result.buffer0[chunkColor])
  result.mask = cast[NCanvasMap](addr result.buffer1[chunkColor])
  result.selection = cast[NCanvasMap](addr result.mask[chunkMask])
  result.original = cast[NCanvasMap](addr result.selection[chunkMask])
  result.mipmaps = cast[NCanvasMap](addr result.original[chunkColor])
  # Store Buffer Size
  result.chunk = chunk

# ---------------------
# Canvas Pointer Lookup
# ---------------------

proc composed*(canvas: var NCanvasContext; level: cint): NCanvasMap =
  var 
    idx = 0
    lvl = min(level, 5)
  let chunk = canvas.chunk
  # Locate Current Pointer
  if lvl == 0:
    return canvas.original
  while lvl > 0:
    let l = lvl - 1
    idx += chunk shr (l + l)
    # Next Level
    dec(lvl)
  # Return Current Pointer
  result = cast[NCanvasMap](addr canvas.mipmaps[idx])

template region*(canvas: var NCanvasContext; field: untyped; size: typedesc; index: cint): NCanvasMap =
  cast[NCanvasMap](addr canvas.field[canvas.chunk * sizeof(size) * index])
