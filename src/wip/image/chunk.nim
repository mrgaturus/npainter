# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
import ffi
from tiles import NTile, NTileStatus
from context import NImageMap
# Mipmap Level Buffer Location
const miplocs = [0, 1024, 1280, 1344, 1408, 1472]

proc pixel*(src: NImageBuffer): uint64 =
  cast[ptr uint64](src.buffer)[]

# -------------------------
# Compositor Buffer Combine
# -------------------------

proc combine*(src, dst: NImageBuffer): NImageCombine =
  result.src = src
  result.dst = dst
  # Prepare Clipping if is not same
  if src.buffer != dst.buffer:
    combine_intersect(addr result)

proc combine_reduce*(co: ptr NImageCombine, lod: cint) =
  var ro = co[]
  assert ro.src.w == ro.dst.w
  assert ro.src.h == ro.dst.h
  # Select Reduce Function
  let mipmap_reduce =
    case ro.src.bpp
    of 2: mipmap_reduce2
    of 4: mipmap_reduce8
    else: mipmap_reduce16 
  # Apply Mipmap Reduction
  for _ in 0 ..< lod:
    {.emit: "`ro.dst.w` >>= 1;".}
    {.emit: "`ro.dst.h` >>= 1;".}
    mipmap_reduce(addr ro)
    ro.src = ro.dst

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
  # Check Buffer Allocated
  if tile.status == tsBuffer:
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
  # Locate LOD Tile Buffer
  if lod > 0 and tile.status == tsBuffer:
    let idx = miplocs[lod] * tile.bpp
    {.emit: "`result.buffer` += `idx`;".}
    {.emit: "`result.w` >>= `lod`;".}
    {.emit: "`result.h` >>= `lod`;".}
    let stride = result.stride shr lod
    result.stride = max(stride, 16)

proc mipmaps*(tile: var NTile) =
  if tile.status != tsBuffer: return
  # Select Reduce Function
  let mipmap_reduce =
    case tile.bpp
    of 2: mipmap_reduce2
    of 4: mipmap_reduce8
    else: mipmap_reduce16 
  # Calculate Mipmaps to LODs
  for lod in 0 ..< 5'i32:
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
