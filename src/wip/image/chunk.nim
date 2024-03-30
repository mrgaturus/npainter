# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
import ffi
from tiles import NTile
from context import NImageMap
# Mipmap Level Buffer Location
const miplocs = [0, 1024, 1280, 1344, 1360, 1376]

# ------------------------
# Compositor Buffer Chunks
# ------------------------

proc chunk*(tile: NTile): NImageBuffer =
  # TODO: MIPMAPPING
  let data = tile.data
  # Configure Map Chunk
  result = NImageBuffer(
    x: cint(tile.x) shl 5,
    y: cint(tile.y) shl 5,
    w: 32, h: 32,
    # Buffer Information
    stride: tile.bpp,
    bpp: tile.bpp,
    buffer: data
  )
  # Check Allocated
  if not tile.uniform:
    result.stride *= 32
    result.buffer = data.buffer

proc chunk*(map: NImageMap): NImageBuffer =
  # Configure Map Chunk
  NImageBuffer(
    w: map.w,
    h: map.h,
    # Buffer Information
    stride: map.stride,
    bpp: map.bpp,
    buffer: map.buffer
  )

# -------------------
# Layer Buffer Chunks
# -------------------

proc chunk*(tile: NTile, lod: cint): NImageBuffer =
  result = tile.chunk()
  if lod == 0 or tile.uniform:
    return result
  # Locate LOD Buffer
  let idx = miplocs[lod] * tile.bpp
  {.emit: "`result.buffer` += `idx`;".}
  # Reduce Buffer Sizes to LOD
  {.emit: "`result.w` >>= `lod`;".}
  {.emit: "`result.h` >>= `lod`;".}
  {.emit: "`result.stride` >>= `lod`;".}

proc mipmaps*(tile: var NTile) =
  if tile.uniform: return
  # Calculate Mipmaps to LODs
  for lod in 0'i32 ..< 5'i32:
    let
      src = tile.chunk(lod)
      dst = tile.chunk(lod + 1)
    # Calculate Mipmap LOD
    var co = combine(src, dst)
    mipmap_reduce(addr co)

# ---------------------
# Mapping Buffer Chunks
# ---------------------

proc clip32*(co: NImageCombine, x, y: cint): NImageCombine =
  result = co
  # Source Clipping
  let clip = NImageClip(
    x: result.src.x + (x shl 5),
    y: result.src.y + (y shl 5),
    # Clipping Dimensions
    w: 32, h: 32
  )
  # Apply Clipping
  combine_clip(addr result, clip)

proc clip32*(co: NImageCombine, x, y, lod: cint): NImageCombine =
  result = co.clip32(x, y)
  if lod == 0: return
  # Reduce Combine Region to LOD
  {.emit: "`result.src.w` >>= `lod`;".}
  {.emit: "`result.src.h` >>= `lod`;".}
  {.emit: "`result.dst.w` >>= `lod`;".}
  {.emit: "`result.dst.h` >>= `lod`;".}

proc pack32*(co: NImageCombine, x, y, lod: cint): NImageCombine =
  result = co.clip32(x, y, lod)
  if lod == 0: return
  # Destination Offset
  let
    dst = addr result.dst
    # Position Offset
    x32 = dst.x
    y32 = dst.y
    ox = x32 - (x32 shr lod)
    oy = y32 - (y32 shr lod)
    # Buffer Index Offset
    idx = oy * dst.stride + ox * dst.bpp
  # Apply Destination Offset
  {.emit: "`dst->buffer` -= `idx`;".}
