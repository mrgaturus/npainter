# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>

from ffi import NImageBuffer
type NImageContext* = object
    w*, h*: cint
    # Image Padded
    w32*, h32*: cint
    s32*: cint
    # Image Buffers
    flat: array[6, pointer]
    aux: seq[pointer]

# ------------------------------------
# Image Context Creation & Destruction
# ------------------------------------

proc createImageContext*(w, h: cint): NImageContext =
  let
    w32 = (w + 0x1F) and not 0x1F
    h32 = (h + 0x1F) and not 0x1F
  # Image Bytes per Pixel
  const bpp = sizeof(uint8) shl 2
  # Image Dimensions
  result.w = w
  result.h = h
  # Image Dimensions Padded
  result.w32 = w32
  result.h32 = h32
  result.s32 = w32 * bpp
  # Allocate Flat Buffers
  var
    s0 = int(result.s32)
    s1 = int(h32)
  for i in 0 ..< 6:
    result.flat[i] = alloc(s0 * s1)
    # Reduce Mipmap Size
    s0 = s0 shr 1
    s1 = s1 shr 1
    # Align to 32 Boundarie
    s0 = (s0 + 0x1F) and not 0x1F

proc destroy*(ctx: var NImageContext) =
  # Dealloc Auxiliars
  for buffer in ctx.aux:
    dealloc(buffer)
  # Dealloc Flat Image
  for buffer in ctx.flat:
    dealloc(buffer)

# -------------------------
# Image Buffer Manipulation
# -------------------------

proc mapFlat*(ctx: var NImageContext, level = 0): NImageBuffer =
  let
    i = clamp(level, 0, 5)
    s32 = ctx.s32 shr i
  # Reduce Buffer Size
  result = default(NImageBuffer)
  result.w = max(ctx.w32 shr i, 1)
  result.h = max(ctx.h32 shr i, 1)
  # Configure Buffer Atributtes
  result.stride = (s32 + 0x1F) and not 0x1F
  result.bpp = sizeof(uint8) shl 2
  result.buffer = ctx.flat[i]

proc mapAux*(ctx: var NImageContext, bpp: cint): NImageBuffer =
  let
    w = ctx.w32
    h = ctx.h32
    # Allocate Buffer
    s = w * bpp
    b = alloc(s * h)
  # Add Buffer Auxiliar
  result = default(NImageBuffer)
  ctx.aux.add(b)
  # Dimensions
  result.w = w
  result.h = h
  # Buffer Attributes
  result.stride = s
  result.bpp = bpp
  result.buffer = b

proc clearAux*(ctx: var NImageContext) =
  # Dealloc Auxiliar Buffers
  for p in items(ctx.aux):
    dealloc(p)
  # Clear Auxiliar List
  setLen(ctx.aux, 0)

# ----------------------------
# Image Status Grid Operations
# ----------------------------

type
  NImageDirty* = uint8
  NImageCheck = object
    tx*, ty*: cint
    check*: ptr NImageDirty
  # Image Status
  NImageMark* = object
    x0*, y0*: cint
    x1*, y1*: cint
    # Mark Stride
    stride: cint
  NImageStatus* = object
    w, h: cint
    # Status Grid 32x32
    flat*: seq[NImageDirty] # Compositor
    aux*: seq[NImageDirty] # Proxy
    # Status Clipping
    clip*: NImageMark

proc createImageStatus*(w, h: cint): NImageStatus =
  # Change Grid Size
  let
    w32 = (w + 0x1F) shr 5
    h32 = (h + 0x1F) shr 5
    # Buffer Sizes
    l0 = w32 * h32
  # Store Dirty Dimensions
  result.w = w32
  result.h = h32
  # Set Grid Buffer and Clear
  setLen(result.flat, l0)
  setLen(result.aux, l0)

proc prepare*(status: var NImageStatus) =
  # Clear Grid Buffer
  let l = len(status.aux) * sizeof(NImageDirty)
  zeroMem(addr status.aux[0], l)

# -------------------------
# Image Status Mark: Region
# -------------------------

proc mark*(x, y, w, h: cint): NImageMark =
  result.x0 = x
  result.y0 = y
  result.x1 = x + w
  result.y1 = y + h

proc expand*(m: var NImageMark, x, y, w, h: cint) =
  let
    x1 = x + w
    y1 = y + h
  # First Mark Clipping
  if m.x0 >= m.x1 or m.y0 >= m.y1:
    m = mark(x, y, w, h)
    return
  # Expand Mark Clipping
  m.x0 = min(m.x0, x)
  m.y0 = min(m.y0, y)
  m.x1 = max(m.x1, x1)
  m.y1 = max(m.y1, y1)

proc intersect*(m: var NImageMark, x, y, w, h: cint) =
  let
    x1 = x + w
    y1 = y + h
  # First Mark Clipping
  if m.x0 >= m.x1 or m.y0 >= m.y1:
    m = mark(x, y, w, h)
    return
  # Expand Mark Clipping
  m.x0 = max(m.x0, x)
  m.y0 = max(m.y0, y)
  m.x1 = min(m.x1, x1)
  m.y1 = min(m.y1, y1)

proc complete*(m: var NImageMark) =
  m.x0 = 0
  m.y0 = 0
  # Clipped to Grid Size
  m.x1 = high(cshort)
  m.y1 = high(cshort)
  # Reset Expand Count
  m.stride = 0

# -----------------------
# Image Status Mark: Grid
# -----------------------

proc scale(m: var NImageMark, w, h: cint) =
  m.x0 = clamp(m.x0 shr 5, 0, w)
  m.y0 = clamp(m.y0 shr 5, 0, h)
  m.x1 = clamp(m.x1 shr 5, 0, w)
  m.y1 = clamp(m.y1 shr 5, 0, h)

proc scale*(status: NImageStatus, m: NImageMark): NImageMark =
  let
    w32 = status.w
    h32 = status.h
  # Calculate Dirty Region
  result = m
  result.x1 += 0x1F
  result.y1 += 0x1F
  # Scale and Clamp Sizes
  result.scale(w32, h32)
  result.stride = w32

# -----------------
# Image Status Mark
# -----------------

iterator cells(m: NImageMark): cint =
  let stride = m.stride
  # Iterate Tile Flags
  for ty in m.y0 ..< m.y1:
    for tx in m.x0 ..< m.x1:
      yield ty * stride + tx

proc mark32*(status: var NImageStatus, x32, y32: cint) =
  let w32 = status.w
  let h32 = status.h
  # Mark if is Inside Boundaries
  if x32 >= 0 and y32 >= 0 and x32 < w32 and y32 < h32:
    let idx = y32 * w32 + x32
    let check = status.aux[idx]
    status.aux[idx] += uint8(check == 0)
    status.flat[idx] = 0

proc mark*(status: var NImageStatus, m: NImageMark) =
  let r = status.scale(m)
  # Mark Dirty Grids
  for idx in r.cells():
    let check = status.aux[idx]
    status.aux[idx] += uint8(check == 0)
    status.flat[idx] = 0

proc mark*(status: var NImageStatus, x, y, w, h: cint) =
  status.mark mark(x, y, w, h)

# ---------------------
# Image Status Checking
# ---------------------

iterator checkFlat*(status: var NImageStatus, mipmap: cint): NImageCheck =
  let r = status.scale(status.clip)
  var idx0 = r.y0 * r.stride + r.x0
  # Check Tile Dirties
  let lvl = 1'u8 shl mipmap
  for ty in r.y0 ..< r.y1:
    var idx = idx0
    for tx in r.x0 ..< r.x1:
      # Lookup Current Flags
      let check = addr status.flat[idx]
      if (check[] and lvl) == 0:
        yield NImageCheck(tx: tx, ty: ty, check: check)
      # Next Tile
      inc(idx)
    # Next Row
    idx0 += r.stride
    
iterator checkAux*(status: var NImageStatus): NImageCheck =
  let r = status.scale(status.clip)
  var idx0 = r.y0 * r.stride + r.x0
  # Check Tile Dirties
  for ty in r.y0 ..< r.y1:
    var idx = idx0
    for tx in r.x0 ..< r.x1:
      # Lookup Current Flags
      let check = addr status.aux[idx]
      if check[] > 0:
        yield NImageCheck(tx: tx, ty: ty, check: check)
      # Next Tile
      inc(idx)
    # Next Row
    idx0 += r.stride
