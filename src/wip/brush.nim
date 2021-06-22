import brush/pipe
from math import 
  floor, ceil,
  sqrt, pow, log2
# Export Brush Kinds
export NBrushShape, NBrushBlend, color

# ---------------------------------
# BRUSH ENGINE STROKE TYPES & PROCS
# ---------------------------------

type
  NStrokeBasic = object
    size*, p_size*, amp_size*: cfloat
    alpha*, p_alpha*, amp_alpha*: cfloat
  # ---------------------------
  NStrokeCircle = object
    hard*, sharp*, step*: cfloat
  NStrokeBlotmap = object
    hard*, sharp*, step*: cfloat
    # Interpolation
    fract*: cshort
    # Texture Buffer
    buffer*: pointer
  NStrokeBitmap = object
    alpha*, step*: cfloat
    # Angle & Aspect Ratio
    angle*, aspect*: cfloat
    # Scatter Intensity
    s_space*: cfloat
    s_angle*: cfloat
    s_scale*: cfloat
    # Texture Buffer
    buffer*: pointer
  # ---------------------
  NStrokeTexture = object
    scratch*, fract*: cshort
    # Texture Buffer
    buffer*: pointer
type
  NStrokeAverage = object
    blending*: cshort
    dilution*: cshort
    persistence*: cshort
    # Pressure Flags
    p_blending*: bool
    p_dilution*: bool
    # Pressure Min 
    p_minimun*: cfloat
    # UnPremultiply?
    keep_alpha*: bool
  NStrokeMarker = object
    blending*: cshort
    persistence*: cshort
    # Blending Pressure
    p_blending*: bool
  # -------------------
  NStrokeBlur = object
    radius*: cshort

type
  NStrokePoint = object
    x, y, press: float32
  NStrokeRegion = object
    shift: cint
    # Rendering Region
    x1, y1, x2, y2: cint
  # -----------------------------
  NStrokeShape {.union.} = object
    circle*: NStrokeCircle
    blot*: NStrokeBlotmap
    bitmap*: NStrokeBitmap
  NStrokeBlend {.union.} = object
    avg: NStrokeAverage
    marker: NStrokeMarker
    # ---------------
    blur: NStrokeBlur
  # ---------------------
  NBrushStroke* = object
    # Shape & Blend Kind
    shape*: NBrushShape
    blend*: NBrushBlend
    # Fundamental Config
    basic*: NStrokeBasic
    # Shape & Texture Config
    mask*: NStrokeShape
    texture*: NStrokeTexture
    # Blending Mode Config
    data*: NStrokeBlend
    # Continuous Stroke
    step*, flow, prev_t: float32
    points: seq[NStrokePoint]
    # --TEMPORALY PUBLIC--
    # Brush Engine Pipeline
    pipe*: NBrushPipeline

# ----------------------
# BRUSH STROKE PREPARING
# ----------------------

proc prepare*(path: var NBrushStroke) =
  # Reset Path
  path.prev_t = 0.0
  setLen(path.points, 0)
  # Decide Which Step Use
  let
    check0 = # Check if Opacity is Flat
      path.blend in {bnFlat, bnMarker, bnSmudge}
    check1 = # Check if Opacity is Custom
      path.shape == bsBitmap
    # Shortcut Pipeline
    pipe = addr path.pipe
  # Decide Which Step Use
  path.step = if not check1:
    path.mask.circle.step
  else: path.mask.bitmap.step
  # Check if needs opacity ajust
  path.flow = if check0 or check1:
    0.0 else: path.step * 2.0
  # Prepare Pipeline Kind
  pipe.shape = path.shape
  pipe.blend = path.blend

# ------------------------
# BRUSH STROKE REGION SIZE
# ------------------------

proc region(x, y, size: cfloat): NStrokeRegion =
  let
    shift = log2(size).cint
    radius = size * 0.5
    # Interval Region
    x1 = floor(x - radius).cint
    y1 = floor(y - radius).cint
    x2 = ceil(x + radius).cint
    y2 = ceil(y + radius).cint
  # Block Size Shifting
  result.shift = min(shift, 5)
  # Position
  result.x1 = x1
  result.y1 = y1
  # Dimensions
  result.x2 = x2
  result.y2 = y2

proc region(x, y, size: cfloat; bitmap: NStrokeBitmap): NStrokeRegion {.used.} =
  discard

# --------------------------------------
# BRUSH STROKE PER SHAPE RENDERING PROCS
# --------------------------------------

proc prepare_stage0(path: var NBrushStroke, x, y, size, alpha: cfloat) =
  let 
    r = region(x, y, size)
    mask = addr path.pipe.mask
  # Pipeline Stage Size & Alpha
  path.pipe.size =
    if path.blend == bnBlur:
      cint(path.data.blur.radius)
    else: cint(1 shl r.shift)
  path.pipe.alpha =
    cint(alpha * 32767.0)
  # Pipeline Stage Shape
  case path.shape
  of bsCircle, bsBlotmap:
    let 
      hard = path.mask.circle.hard
      sharp = path.mask.circle.sharp
    # Configure Circle
    basic(mask.circle, x, y, size)
    style(mask.circle, hard, sharp)
    # Configure Blotmap
    if path.shape == bsBlotmap:
      discard
  of bsBitmap: discard
  # Pipeline Stage Texture
  # ----------------------
  # Pipeline Stage Blocks
  reserve(path.pipe,
    r.x1, r.y1,
    r.x2, r.y2,
    r.shift)

proc prepare_stage1(path: var NBrushStroke, press: cfloat): bool =
  result = true
  # Pipeline Stage Blend
  case path.blend
  of bnAverage, bnWater:
    let 
      avg = # Shortcut
        addr path.data.avg
      # Minimun Pressure
      m_st = avg.p_minimun
      m_dist = 1.0 - m_st
      # Current Calculated Pressure Inverted
      m_press = 1.0 - (m_st + m_dist * press)
    var b, d, p: cint
    # Calculate Parameters
    b = avg.blending
    d = avg.dilution
    p = avg.persistence
    # Interpolate With Pressure
    if avg.p_blending:
      b = cint(m_press * b.cfloat)
    if avg.p_dilution:
      d = cint(m_press * d.cfloat)
    # Calcultate Averaged
    average(path.pipe, 
      b, d, p, avg.keep_alpha)
    # Watercolor Buffer
    if path.blend == bnWater:
      water(path.pipe, avg.keep_alpha)
  of bnMarker:
    let marker = 
      addr path.data.marker
    var b, p: cint
    b = marker.blending
    p = marker.persistence
    # Interpolate With Pressure
    if marker.p_blending:
      b = cint(press * b.cfloat)
    # Calculate Averaged
    average(path.pipe,
      b, 0, p, true)
  of bnBlur, bnSmudge: discard
  else: result = false

proc stage(path: var NBrushStroke, x, y, size, alpha, press: cfloat) =
  # Pipeline Stage 0
  prepare_stage0(path, x, y, size, alpha)
  dispatch_stage0(path.pipe)
  # Pipeline Stage 1
  if prepare_stage1(path, press):
    dispatch_stage1(path.pipe)

# --------------------------
# BRUSH STROKE PATH DISPATCH
# --------------------------

proc evaluate(basic: ptr NStrokeBasic, p, flow: cfloat): tuple[s, a: cfloat] =
  let
    # Size Interval
    s_st = basic.p_size
    s_dist = 1.0 - s_st
    # Size Pressure Amplify
    s_amp = basic.amp_size
  let
    # Alpha Interval
    a_st = basic.p_alpha
    a_dist = 1.0 - a_st
    # Alpha Pressure Amplify
    a_amp = basic.amp_alpha
  # Shortcurts
  var size, alpha: cfloat
  # Pressure Amplify
  size = pow(p, s_amp)
  alpha = pow(p, a_amp)
  # Pressure Interpolation
  size = (s_st + s_dist * size) * basic.size
  alpha = (a_st + a_dist * alpha) * basic.alpha
  # Simulate Smallest
  if size < 2.5:
    alpha *= size * 0.4
    # Clamp Size
    size = 2.5
  # Calculate Proper Opacity
  if flow > 0.0:
    alpha = 1.0 - pow(alpha, alpha + 1.25)
    alpha = 1.0 - pow(alpha, flow)
  # Return Values
  result.s = size
  result.a = alpha

proc line(path: var NBrushStroke, a, b: NStrokePoint, start: cfloat): cfloat =
  let
    dx = b.x - a.x
    dy = b.y - a.y
    # Stroke Line Length
    length = sqrt(dx * dx + dy * dy)
    # Basic Shortcut
    basic = addr path.basic
  # Avoid Zero Length
  if length < 0.0001:
    return start
  let 
    # Stroke Shape Step
    step = path.step / length
    # Stroke Opacity Step
    flow = path.flow
    # Pressure Interval
    p_start = a.press
    p_dist = # Distance
      b.press - a.press
  var
    t = start / length
    press, x, y: float32
  # Draw Each Stroke Point
  while t < 1.0:
    # Pressure Interpolation
    press = p_start + p_dist * t
    # Basic Parameters
    let basic =
      basic.evaluate(press, flow)
    # Current Position
    x = a.x + dx * t
    y = a.y + dy * t
    # Render Shape
    path.stage(x, y,
      basic.s, basic.a, press)
    # Step to next point
    t += basic.s * step
  # Return Remainder
  result = length * (t - 1.0)

# ------------------------
# BRUSH POINT MANIPULATION
# ------------------------

proc point*(path: var NBrushStroke; x, y, press: cfloat) =
  var p: NStrokePoint
  # Point Position
  p.x = x; p.y = y
  # Avoid 0.0 Infinite Loop
  p.press = max(press, 0.0001)
  # Add New Point
  path.points.add(p)

proc dispatch*(path: var NBrushStroke) =
  let count = len(path.points)
  # Draw Point Line
  if count > 1:
    var a, b: NStrokePoint
    for i in 1..<count:
      a = path.points[i - 1]
      b = path.points[i]
      # Draw Brush Line
      path.prev_t = path.line(
        a, b, path.prev_t)
    # Set Last Point to First
    path.points[0] = path.points[^1]
    setLen(path.points, 1)
