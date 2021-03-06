import brush/pipe
from math import 
  floor, ceil, round,
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
    hard*, sharp*: cfloat
  NStrokeBlotmap = object
    hard*, sharp*: cfloat
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
  # ----------------
  NStrokeFlow = enum
    fwAuto, fwFlat, fwCustom
  NStrokeGeneric = object
    size, angle: cfloat
    # Staged Opacity
    alpha, flow: cfloat
    # Constant Flow Kind
    kind: NStrokeFlow
    magic: cfloat
  # --------------------
  NStrokeRegion = object
    shift: cint
    # Rendering Region
    x1*, y1*, x2*, y2*: cint
  # -----------------------------
  NStrokeShape {.union.} = object
    circle*: NStrokeCircle
    blot*: NStrokeBlotmap
    bitmap*: NStrokeBitmap
  NStrokeBlend {.union.} = object
    avg*: NStrokeAverage
    marker*: NStrokeMarker
    blur*: NStrokeBlur
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
    step, prev_t: float32
    generic: NStrokeGeneric
    points: seq[NStrokePoint]
    # --TEMPORALY PUBLIC--
    # Brush Engine Pipeline
    pipe*: NBrushPipeline
    aabb*: NStrokeRegion

# ----------------------
# BRUSH STROKE PREPARING
# ----------------------

proc clear*(path: var NBrushStroke) =
  # Reset Path
  path.prev_t = 0.0
  setLen(path.points, 0)
  # Region Shortcut
  let aabb = addr path.aabb
  # Reset Dirty Region -TEMPORAL-
  aabb.x1 = high(int32); aabb.x2 = 0
  aabb.y1 = high(int32); aabb.y2 = 0

proc prepare*(path: var NBrushStroke) =
  # Reset Path
  path.clear()
  # Shortcuts
  let
    shape = path.shape
    blend = path.blend
    # Generic Dynamics
    dyn = addr path.generic
    basic = addr path.basic
  # Ajust Size And Alpha Parameters
  basic.size = 2.5 + (1000.0 - 2.5) * basic.size
  basic.alpha = min(basic.alpha, 0.9999)
  # Decide Which Step Use
  case shape
  of bsCircle, bsBlotmap:
    let hard = path.mask.circle.hard
    path.step = # Automatic Step
      0.075 + (0.025 - 0.075) * hard
  of bsBitmap:
    path.step = # Custom Step
      path.mask.bitmap.step
  # Define Which Flow Use
  if shape == bsBitmap:
    dyn.kind = fwCustom
    dyn.magic = # Custom Alpha
      path.mask.bitmap.alpha
  elif blend in {bnFlat, bnMarker, bnSmudge}:
    dyn.kind = fwFlat
    # Decide Which Flow Use
    dyn.magic = case blend
      of bnFlat, bnSmudge: 1.0
      else: basic.alpha
    # Ajust Circle Sharpness
    path.mask.circle.sharp -= 1.0
  else: # Use Automatic
    dyn.kind = fwAuto
    dyn.magic = path.step * 2.0
  # Prepare Pipeline Kind
  path.pipe.shape = shape
  path.pipe.blend = blend
  # Prepare Pipeline Skip
  path.pipe.skip = true

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
  result.shift = shift
  # Position
  result.x1 = x1
  result.y1 = y1
  # Dimensions
  result.x2 = x2
  result.y2 = y2

proc region(x, y, size: cfloat; bitmap: NStrokeBitmap): NStrokeRegion {.used.} =
  discard

proc dirty(path: var NBrushStroke, region: NStrokeRegion) =
  let aabb = addr path.aabb
  # Sum Dirty AABB Region
  aabb.x1 = min(region.x1, aabb.x1)
  aabb.x2 = max(region.x2, aabb.x2)
  aabb.y1 = min(region.y1, aabb.y1)
  aabb.y2 = max(region.y2, aabb.y2)

# --------------------------------------
# BRUSH STROKE PER SHAPE RENDERING PROCS
# --------------------------------------

proc prepare_stage0(path: var NBrushStroke, x, y, size, alpha, flow: cfloat) =
  let 
    r = region(x, y, size)
    mask = addr path.pipe.mask
  # Pipeline Stage Alpha
  case path.blend
  of bnFlat, bnMarker:
    path.pipe.alpha =
      cint(alpha * 32767.0)
  of bnWater:
    path.pipe.alpha = # Keep Opacity
      cshort(path.data.avg.keep_alpha)
  of bnBlur:
    path.pipe.alpha = # Radius
      path.data.blur.radius
  of bnSmudge:
    path.pipe.alpha = # Skip
      cshort(path.pipe.skip)
  else: discard
  # Pipeline Stage Flow
  path.pipe.flow =
    cint(flow * 32767.0)
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
  # Pipeline State Water Blocks
  if path.blend == bnWater:
    water(path.pipe)
  # Sum Dirty AABB
  path.dirty(r)

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
      m_fract = cint(m_press * 32767.0)
    var b, d, p: cint
    # Calculate Parameters
    b = avg.blending
    d = avg.dilution
    p = avg.persistence
    # Interpolate With Pressure
    if avg.p_blending:
      b = div_32767(b * m_fract)
    if avg.p_dilution:
      d = div_32767(d * m_fract)
    # Ajust Blending
    b = sqrt_32767(b)
    d = sqrt_32767(d)
    # Ajust Persistence
    p = sqrt_32767(p)
    p = sqrt_32767(p)
    # Calcultate Averaged
    average(path.pipe, 
      b, d, p, avg.keep_alpha)
  of bnMarker:
    let marker = 
      addr path.data.marker
    var b, p: cint
    b = marker.blending
    p = marker.persistence
    # Interpolate With Pressure
    if marker.p_blending:
      let fract = # Pressure
        cint(press * 32767.0)
      b = div_32767(b * fract)
    # Ajust Blending
    b = sqrt_32767(b)
    # Ajust Persistence
    p = sqrt_32767(p)
    p = sqrt_32767(p)
    # Calculate Averaged
    average(path.pipe,
      b, 0, p, false)
  of bnBlur, bnSmudge: discard
  else: result = false

proc stage(path: var NBrushStroke; dyn: ptr NStrokeGeneric; x, y, press: cfloat) =
  # Pipeline Stage 0
  prepare_stage0(path, x, y, 
    dyn.size, dyn.alpha, dyn.flow)
  dispatch_stage0(path.pipe)
  # Pipeline Stage 1
  if prepare_stage1(path, press):
    dispatch_stage1(path.pipe)
  # Pipeline Stage Skip
  path.pipe.skip = false

# --------------------------
# BRUSH STROKE PATH DISPATCH
# --------------------------

proc evaluate(dyn: ptr NStrokeGeneric, basic: ptr NStrokeBasic, p: cfloat) =
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
  var size, alpha, flow: cfloat
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
  # Calculate Flow Opacity
  case dyn.kind
  of fwAuto:
    flow = 1.0 - pow(alpha, alpha + 1.25)
    flow = 1.0 - pow(flow, dyn.magic)
  of fwFlat, fwCustom:
    flow = dyn.magic
  # Return Values
  dyn.size = size
  dyn.alpha = alpha
  dyn.flow = flow

proc line(path: var NBrushStroke, a, b: NStrokePoint, start: cfloat): cfloat =
  let
    dx = b.x - a.x
    dy = b.y - a.y
    # Stroke Line Length
    length = sqrt(dx * dx + dy * dy)
    # Dynamics Shortcut
    basic = addr path.basic
    dyn = addr path.generic
  # Avoid Zero Length
  if length < 0.0001:
    return start
  let
    # Stroke Shape Step
    step = path.step / length
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
    dyn.evaluate(basic, press)
    # Current Position
    x = a.x + dx * t
    y = a.y + dy * t
    # Render Current Shape
    path.stage(dyn, x, y, press)
    # Step to next point
    t += dyn.size * step
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
