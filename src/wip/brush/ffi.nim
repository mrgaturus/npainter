# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2021 Cristian Camilo Ruiz <mrgaturus>
from math import 
  floor, ceil,
  log2, sin, cos

# ----------------
# BRUSH ENGINE FFI
# ----------------

{.compile: "shape.c".}
{.compile: "clip.c".}
# --------------------
{.compile: "basic.c".}
{.compile: "water.c".}
{.compile: "blur.c".}
{.compile: "smudge.c".}
# ----------------------------------
{.push header: "wip/brush/brush.h".}

type
  NBrushTexture {.importc: "brush_texture_t" } = object
    fract, tone0, tone1: cint
    # Texture Buffer
    w, h, fixed: cint
    buffer: pointer
  # -------------------------------------------------
  NBrushCircle {.importc: "brush_circle_t" } = object
    x, y, size: cfloat
    # Hard & Sharp
    smooth: cfloat
  NBrushBlotmap {.importc: "brush_blotmap_t" } = object
    # Blotmap Circle
    circle: NBrushCircle
    # Blotmap Texture Pointer
    tex*: ptr NBrushTexture
  NBrushBitmap {.importc: "brush_bitmap_t" } = object
    sx, sy: cfloat
    # Inverse Affine
    a, b, c: cint
    d, e, f: cint
    # Bitmap Texture Pointer
    tex*: ptr NBrushTexture

type
  NBrushAverage {.importc: "brush_average_t" } = object
    count: cint
    # Color Acumulation
    total: array[4, cint]
  NBrushWater {.importc: "brush_water_t" } = object
    count: cint
    # Color Acumulation
    total: array[4, cint]
    # Water Tiled
    x, y, fx, fy: cint
    # Water Stride
    stride: cint
  NBrushBlur {.importc: "brush_blur_t" } = object
    # Buffer Size
    x, y, w, h: cshort
    # Buffer Scale
    sw, sh: cshort
    # Buffer Bilinear Steps
    down_fx, down_fy: cint
    up_fx, up_fy: cint
    # Buffer Bilinear Offset
    offset: cint
  NBrushSmudge {.importc: "brush_smudge_t" } = object
    # Copy Position
    dx, dy: cint
  # ----------------------------------TEMPORALY PUBLIC
  NBrushCanvas {.importc: "brush_canvas_t"} = object
    w*, h*, stride*: cint
    # Clipping Buffers
    clip*, alpha*: ptr cshort
    # Auxiliar Buffers
    buffer0*: ptr cshort
    buffer1*: ptr cshort
    # Destination
    dst*: ptr cshort
  NBrushRender {.importc: "brush_render_t" } = object
    x, y, w, h: cint
    # Shape Color
    color: ptr array[4, cint]
    # Shape Alpha
    alpha, flow: cint
    # Canvas Target
    canvas: ptr NBrushCanvas
    # Aditional Data
    opaque: pointer

{.push importc.}

# ----------------------------
# BRUSH ENGINE SHAPE RENDERING
# ----------------------------

proc brush_circle_mask(render: ptr NBrushRender, circle: ptr NBrushCircle)
proc brush_blotmap_mask(render: ptr NBrushRender, blot: ptr NBrushBlotmap)
proc brush_bitmap_mask(render: ptr NBrushRender, bitmap: ptr NBrushBitmap)
# -----------------------------------------------------------------------
proc brush_texture_mask(render: ptr NBrushRender, tex: ptr NBrushTexture)

# ---------------------------
# BRUSH ENGINE BLENDING MODES
# ---------------------------

proc brush_clip_blend(render: ptr NBrushRender)
# -----------------------------------------------
proc brush_normal_blend(render: ptr NBrushRender)
proc brush_func_blend(render: ptr NBrushRender)
proc brush_flat_blend(render: ptr NBrushRender)
proc brush_erase_blend(render: ptr NBrushRender)
# ----------------------------------------------
proc brush_water_first(render: ptr NBrushRender)
proc brush_water_blend(render: ptr NBrushRender)
# ---------------------------------------------
proc brush_blur_first(render: ptr NBrushRender)
proc brush_blur_blend(render: ptr NBrushRender)
# -----------------------------------------------
proc brush_smudge_first(render: ptr NBrushRender)
proc brush_smudge_blend(render: ptr NBrushRender)

{.pop.} # End Importc
{.pop.} # End Header

# ----------------------------
# BRUSH CIRCLE MASK DEFINITION
# ----------------------------

proc basic*(circle: var NBrushCircle, x, y, size: cfloat) =
  circle.x = x
  circle.y = y
  # Change Circle Size
  circle.size = size

proc style*(circle: var NBrushCircle, hard, sharp: cfloat) =
  let
    hard = 0.5 * hard
    sharp = 1.5 - sharp
    # Size And Reciprocal
    size = circle.size
    rcp = 1.0 / size
  # Calculate Smoth Constant
  var calc: cfloat
  # Smothstep Sharpness & Hardness
  calc = 2.0 * (rcp * sharp)
  calc = 1.0 / (hard - calc - 0.5)
  # Set Smooth Constant
  circle.smooth = calc

# -----------------------------
# BRUSH TEXTURE MASK DEFINITION
# -----------------------------

proc image*(tex: ptr NBrushTexture, w, h: cint, buffer: pointer) =
  tex.w = w
  tex.h = h
  # Set Current Buffer
  tex.buffer = buffer

proc scale*(tex: ptr NBrushTexture, scale: cfloat, level: cint) =
  tex.fixed = cint(65536.0 / scale) shr level

proc amount*(tex: ptr NBrushTexture, fract: cfloat, invert: bool) =
  # Set Texture Pattern Opacity
  var c = cint(fract * 65535.0)
  if invert: c = c or 65536
  # Replace Current Fract
  tex.fract = c

proc tone*(tex: ptr NBrushTexture, tone, flow, size: cfloat) =
  var t0, t1: uint32
  let 
    a = uint32(flow * 65535.0)
    s = uint32(65535.0 / size)
  # Set Minimun Tone
  t0 = uint32(tone * 65535.0)
  t0 = max(65535 - t0, s)
  t0 = (t0 * a + 65535) shr 16
  # Calculate Tone Scale
  if t0 > 0: 
    t1 = a * 65535 div t0
  # Set Current Tone
  tex.tone0 = cast[cint](t0)
  tex.tone1 = cast[cint](t1)

proc tone*(tex: ptr NBrushTexture, tone, size: cfloat) =
  var t0, t1: uint32
  # Calculate Reciprocal Size
  let s = uint32(65535.0 / size)
  # Clamp to Reciprocal Size
  t0 = uint32(tone * 65535.0)
  t0 = max(65535 - t0, s)
  # Calculate Tone Scale
  if t0 > 0:
    t1 = uint32(4294836225) div t0
  # Set Current Tone
  tex.tone0 = cast[cint](t0)
  tex.tone1 = cast[cint](t1)

# ----------------------------
# BRUSH BITMAP MASK DEFINITION
# ----------------------------

proc scaling*(bitmap: var NBrushBitmap; size, aspect: cfloat): cfloat =
  let
    w = cfloat(bitmap.tex.w)
    h = cfloat(bitmap.tex.h)
    # Fit Scale to Square
    scale = min(size / w, size / h)
  # Ajust Aspect Ratio
  var sx, sy = scale
  if aspect > 0.0:
    sx *= aspect
  elif aspect < 0.0:
    sy *= -aspect
  # Replace Scaling
  bitmap.sx = sx
  bitmap.sy = sy
  # Return Minimun Scaling
  result = min(sx, sy)

proc affine*(bitmap: var NBrushBitmap; x, y, angle: cfloat) =
  let
    # Texture Orientation
    sa = sin(angle)
    ca = cos(angle)
    # Texture Rectangle Center
    cx = cfloat(bitmap.tex.w) * 0.5
    cy = cfloat(bitmap.tex.h) * 0.5
    # Calculate Scaling
    sx = bitmap.sx
    sy = bitmap.sy
    # Convert To Reciprocal
    rx = 1.0 / sx
    ry = 1.0 / sy
  # Affine Constants
  var a, b, c, d, e, f: cfloat
  # X Affine Transformation
  a = ca * rx
  b = sa * rx
  c = -(ca * x + sa * y - cx * sx) * rx
  # Y Affine Transformation
  d = -sa * ry
  e = ca * ry
  f = (sa * x - ca * y + cy * sy) * ry
  # Convert X Affine to Fix15
  bitmap.a = cint(a * 32768.0)
  bitmap.b = cint(b * 32768.0)
  bitmap.c = cint(c * 32768.0)
  # Convert Y Affine to Fix15
  bitmap.d = cint(d * 32768.0)
  bitmap.e = cint(e * 32768.0)
  bitmap.f = cint(f * 32768.0)
