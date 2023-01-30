# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>

{.compile: "clear.c".}
{.compile: "convert.c".}
{.compile: "floodfill0.c".}
{.compile: "floodfill1.c".}
{.compile: "distance0.c".}
{.compile: "distance1.c".}
{.compile: "smooth.c".}
# ----------------------
{.push header: "binary/binary.h".}

type
  NDistance* {.importc: "distance_t".} = object
    x, y, w, h: cint
    # Buffer Stride
    stride, rows: cint
    # Distance Buffers
    src, dst: pointer
    distances: ptr cuint
    positions: ptr cuint
    # Distance Checks
    check, threshold: cint
  NFloodFill* {.importc: "floodfill_t".} = object
    # Scanline Pivot
    x, y, w, h: cint
    # Scanline Stack
    stack: ptr cshort
    # Scanline Buffer Pointer
    buffer0, buffer1: pointer
    # Scanline AABB
    x1, y1, x2, y2: cint
  # -----------------
  # Binary Conversion
  # -----------------
  NBinary* {.importc: "binary_t".} = object
    # Region Buffer
    x, y, w, h: cint
    # Binary & Color Buffer
    color, buffer: pointer
    # Stride Buffer
    stride, rows: cint
    # Color <-> Binary
    value, threshold: cuint
    rgba, check: cuint
  NBinarySmooth* {.importc: "binary_smooth_t".} = object
    x, y, w, h: cint
    # Buffer Pointers
    binary, magic: pointer
    # Grayscale Buffer
    gray: ptr cushort
    # Buffer Strides
    stride, rows: cint
    rgba, check: cuint
  # ---------------
  # Binary Clearing
  # ---------------
  NBinaryClear* {.importc: "binary_clear_t".} = object
    # Region Buffer
    x, y, w, h: cint
    # Buffer Pointer
    buffer: pointer
    # Buffer Stride & Size
    stride, bytes: cint
    

{.push importc.}

proc distance_prepare(chamfer: ptr NDistance)
proc distance_pass0(chamfer: ptr NDistance)
proc distance_pass1(chamfer: ptr NDistance)
proc distance_convert(chamfer: ptr NDistance)
# Flood Fill Procs
proc floodfill_simple(flood: ptr NFloodFill)
proc floodfill_dual(flood: ptr NFloodFill)

# Color to Binary Convert
proc binary_threshold_color(binary: ptr NBinary)
proc binary_threshold_alpha(binary: ptr NBinary)
# Binary to Color Convert
proc binary_convert_simple(binary: ptr NBinary)
proc binary_smooth_dilate(smooth: ptr NBinarySmooth)
proc binary_smooth_magic(smooth: ptr NBinarySmooth)
proc binary_smooth_apply(smooth: ptr NBinarySmooth)
proc binary_convert_smooth(binary: ptr NBinarySmooth)
# Binary Clearing Fill
proc binary_clear(clear: ptr NBinaryClear)

{.pop.} # End importc
{.pop.} # End header

# --------------------------
# Chamfer Distance Transfrom
# --------------------------

proc region*(chamfer: var NDistance; x, y, w, h: cint) =
  chamfer.x = x; chamfer.y = y;
  chamfer.w = w; chamfer.h = h;

proc bounds*(chamfer: var NDistance; stride, rows: cint) =
  chamfer.stride = stride
  chamfer.rows = rows

proc buffers*(chamfer: var NDistance; src, dst: pointer) =
  chamfer.src = src
  chamfer.dst = dst

proc auxiliars*(chamfer: var NDistance, distances, positions: ptr cuint) =
  chamfer.distances = distances
  chamfer.positions = positions

proc checks*(chamfer: var NDistance; check, threshold: cint) =
  chamfer.check = check
  # Squared Distance Check
  chamfer.threshold = threshold * threshold

proc dispatch_almost*(chamfer: var NDistance) =
  distance_prepare(addr chamfer)
  distance_pass0(addr chamfer)
  distance_pass1(addr chamfer)
  distance_pass0(addr chamfer)
  distance_convert(addr chamfer)

proc dispatch_full*(chamfer: var NDistance) =
  distance_prepare(addr chamfer)
  distance_pass0(addr chamfer)
  distance_pass1(addr chamfer)
  distance_pass0(addr chamfer)
  distance_pass1(addr chamfer)
  distance_convert(addr chamfer)

# -------------------
# Flood Fill Scanline
# -------------------

proc stack*(flood: var NFloodFill, buffer: ptr cshort) =
  flood.stack = buffer

proc target*(flood: var NFloodFill; buffer0, buffer1: pointer; w, h: cint) =
  # Buffer Pointers
  flood.buffer0 = buffer0
  flood.buffer1 = buffer1
  # Buffer Dimensions
  flood.w = w
  flood.h = h

proc dispatch*(flood: var NFloodFill; x, y: cint; dual: bool) =
  flood.x = x
  flood.y = y
  # Dispatch Flood Fill
  if dual: floodfill_dual(addr flood)
  else: floodfill_simple(addr flood)

# -----------------
# Binary Conversion
# -----------------

proc target*(binary: var NBinary; color, buffer: pointer) =
  binary.color = color
  binary.buffer = buffer

proc bounds*(binary: var NBinary; stride, rows: cint) =
  binary.stride = stride
  binary.rows = rows

proc region*(binary: var NBinary, x, y, w, h: cint) =
  binary.x = x
  binary.y = y
  # Binary Region
  binary.w = w
  binary.h = h

proc toBinary*(binary: var NBinary; value, threshold: cuint; color: bool) =
  # Ajust Color and Threshold
  binary.value = value
  binary.threshold = threshold + 1
  # Dispatch To Binary
  let p = addr binary
  if color: binary_threshold_color(p)
  else: binary_threshold_alpha(p)

proc toColor*(binary: var NBinary; rgba, check: cuint) =
  binary.rgba = rgba
  binary.check = check
  # Dispath to Color
  binary_convert_simple(addr binary)

# ------------------------
# Binary Smooth Conversion
# TODO: Use NBinary instead
# ------------------------

proc toSmooth*(smooth: var NBinarySmooth, binary: var NBinary; rgba, check: cuint) =
  smooth.rgba = rgba
  smooth.check = check
  # Copy Arguments to Smooth
  smooth.x = binary.x
  smooth.y = binary.y
  # Binary Region
  smooth.w = binary.w
  smooth.h = binary.h
  # Smooth Buffer Size
  smooth.stride = binary.stride
  smooth.rows = binary.rows
  # Smooth Buffers
  smooth.binary = binary.buffer
  smooth.magic = binary.color

proc auxiliar*(smooth: var NBinarySmooth, gray: ptr cushort) =
  smooth.gray = gray

proc dispatch*(smooth: var NBinarySmooth) =
  let p = addr smooth
  binary_smooth_dilate(p)
  binary_smooth_magic(p)
  binary_smooth_apply(p)
  # Convert to Color
  binary_convert_smooth(p)

# ------------
# Binary Clear
# ------------

proc target*(clear: var NBinaryClear; buffer: pointer; stride, bytes: cint) =
  clear.buffer = buffer
  # Buffer Metrics
  clear.stride = stride
  clear.bytes = bytes

proc region*(clear: var NBinaryClear; x, y, w, h: cint) =
  clear.x = x
  clear.y = y
  # Clear Region
  clear.w = w
  clear.h = h

proc dispatch*(clear: var NBinaryClear) =
  binary_clear(addr clear)
