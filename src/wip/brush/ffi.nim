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
# ----------------------------------
{.push header: "wip/brush/brush.h".}

type
  NBrushTexture {.importc: "brush_texture_t" } = object
    alpha, fract: cshort
    # Texture Buffer
    w, h: cint
    buffer: cstring
  # -------------------------------------------------
  NBrushCircle {.importc: "brush_circle_t" } = object
    x, y, size: cfloat
    # Hard & Sharp
    smooth: cfloat
  NBrushBlotmap {.importc: "brush_blotmap_t" } = object
    # Blotmap Circle
    circle: NBrushCircle
    # Blotmap Texture Pointer
    texture: ptr NBrushTexture
  NBrushBitmap {.importc: "brush_bitmap_t" } = object
    x, y: cfloat
    # Inverse Affine
    a, b, c: cfloat
    d, e, f: cfloat
    # Subpixel LOD
    level: cint
    # Bitmap Texture Pointer
    texture: ptr NBrushTexture

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
  NBrushSmudge {.importc: "brush_smudge_t" } = object
    # Copy Position
    x, y: cfloat
  # ----------------------------------TEMPORALY PUBLIC
  NBrushCanvas {.importc: "brush_canvas_t"} = object
    w*, h*, stride*: cint
    # Clipping Buffers
    clip*, alpha*: ptr cshort
    # Auxiliar/Working Buffers
    buffer0*: ptr cshort
    buffer1*: ptr cshort
    # Destination
    dst*: ptr cshort
  NBrushRender {.importc: "brush_render_t" } = object
    x, y, w, h: cint
    # Shape Color
    color: ptr array[4, cshort]
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
    sharp = 1.0 - (0.5 * sharp)
    # Size And Reciprocal
    size = circle.size
    rcp = 1.0 / size
  # Calculate Smoth Constant
  var calc: cfloat
  # Smothstep Sharpness & Hardness
  calc = (6.0 - log2(size) * 0.5) * (rcp * sharp)
  calc = 1.0 / (hard - calc - 0.5)
  # Set Smooth Constant
  circle.smooth = calc

# ----------------------------
# BRUSH BITMAP MASK DEFINITION
# ----------------------------

proc derivative(bitmap: var NBrushBitmap) =
  let
    dudx = bitmap.a
    dudy = bitmap.b
    # --------------
    dvdx = bitmap.d
    dvdy = bitmap.e
    # -----------------------------
    ddu = dudx * dudx + dudy * dudy
    ddv = dvdx * dvdx + dvdy * dvdy
  # Subpixel Level
  var calc: cfloat
  # Calculate Longest
  calc = max(ddu, ddv)
  if calc > 1.0:
    calc = log2(calc)
    # Limit to 16x16
    calc = min(calc, 4.0)
  else: calc = 0.0
  # Return Subpixel Level
  bitmap.level = cint(calc)

proc basic*(bitmap: var NBrushBitmap; x, y: cfloat) =
  # Change Position
  bitmap.x = x
  bitmap.y = y

proc affine*(bitmap: var NBrushBitmap; angle, scale, aspect: cfloat) =
  # -- Calculate Affine Transformation
  let
    x = bitmap.x
    y = bitmap.y
    # Orientation
    sa = sin(angle)
    ca = cos(angle)
    # Center Of Texture Rectangle
    cx = cfloat(bitmap.texture.w) * 0.5
    cy = cfloat(bitmap.texture.h) * 0.5
    # Aspect Ratio
    wh = (0.0 < aspect).cint - (aspect < 0.0).cint
    fract = 1.0 - (aspect - aspect.floor)
  # Calculate Scaling
  var sx, sy = scale
  # Apply Aspect Ratio
  if wh < 0: sx *= fract
  elif wh > 0: sy *= fract
  # Convert To Reciprocal
  sx = 1.0 / sx; sy = 1.0 / sy
  # X Affine Transformation
  bitmap.a = ca * sx; bitmap.b = sa * sx
  bitmap.c = -(ca * x + sa * y + cx * sx) * sx
  # Y Affine Transformation
  bitmap.d = -sa * sy; bitmap.e = ca * sy
  bitmap.f = (sa * x - ca * y - cy * sy) * sy
  # Calculate Subpixel Level
  bitmap.derivative()
