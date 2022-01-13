import texture
import brush/pipe
# Import Useful Math
from math import 
  floor, ceil,
  sqrt, pow, log2
# Export Brush Pipeline Kinds
export NBrushShape, NBrushBlend

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
    fract*: cfloat
    scale*: cfloat
    tone*: cfloat
    # Texture Invert
    invert*: bool
    # Texture Buffer
    texture*: ptr NTexture
  NStrokeBitmap = object
    alpha*, step*: cfloat
    # Angle & Aspect Ratio
    angle*, aspect*: cfloat
    # Scatter Intensity
    s_space*: cfloat
    s_angle*: cfloat
    s_scale*: cfloat
    # Texture Buffer
    texture*: ptr NTexture
  # ---------------------
  NStrokeTexture = object
    # Texture Configuration
    fract*, tone*, scale*: cfloat
    # Texture Invert
    invert*: bool
    # Texture Buffer
    texture*: ptr NTexture
type
  NStrokeAverage = object
    blending*: cfloat
    dilution*: cfloat
    persistence*: cfloat
    # Watercolor Wet
    watering*: cfloat
    coloring*: bool
    # Transparent
    glass: bool
    # Pressure Flags
    p_blending*: bool
    p_dilution*: bool
    p_watering*: bool
    # Pressure Minimun
    p_minimun*: cfloat
  NStrokeMarker = object
    blending*: cfloat
    persistence*: cfloat
    # Blending Pressure
    p_blending*: bool
  # -------------------
  NStrokeBlur = object
    radius*, x, y: cfloat

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

proc color*(path: var NBrushStroke, r, g, b: cint, glass: bool) =
  if not glass:
    color(path.pipe, r, g, b)
    # Ensure Average Not Transparent
    if path.blend in {bnAverage, bnWater}:
      path.data.avg.glass = glass
  else: # Prepare Transparent
    transparent(path.pipe)
    # Override Blending Modes
    case path.blend
    of bnPencil, bnFunc:
      path.blend = bnEraser
    of bnFlat: color(path.pipe, 0, 0, 0)
    of bnAverage, bnWater, bnMarker:
      path.data.avg.glass = glass
      # Override Marker With Average
      if path.blend == bnMarker:
        path.blend = bnAverage
    else: discard

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
  # Ajust Size, Smallest is Resolved With Opacity
  basic.size = 2.5 + (1000.0 - 2.5) * basic.size
  # Decide Which Step Use
  case shape
  of bsCircle:
    # Calculate Current Step
    let hard = path.mask.circle.hard
    path.step = 0.075 - 0.05 * hard
    # Spacing for Special
    if blend == bnBlur:
      path.step *= 2.0
    elif blend == bnSmudge:
      path.step = 0.025
  of bsBlotmap:
    let 
      circle = addr path.mask.circle
      hard = circle.hard * 0.75
    # Calculate Current Step
    path.step = 0.075 - 0.05 * hard
    # Spacing for Special
    if blend == bnBlur:
      path.step *= 2.0
    # Ajust Circle Parameters
    circle.sharp = 0.0
    circle.hard = hard
    let
      tex0 = addr path.pipe.tex0
      blot = addr path.mask.blot
      # Calculate Scale Interpolation
      scale = 0.1 + (5.0 - 0.1) * blot.scale
      mip = raw(blot.texture, scale)
    # Configure Texture Buffer
    tex0.image(mip.w, mip.h, mip.buffer)
    # Configure Texture Scale & Interpolation
    tex0.amount(blot.fract, blot.invert)
    tex0.scale(scale, mip.level)
    # Bind Texture to Blotmap
    path.pipe.mask.blotmap.tex = tex0
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
      of bnFlat: 1.0
      else: basic.alpha
    # Ajust Circle Sharpness to Half
    if shape == bsCircle:
      path.mask.circle.sharp *= 0.5
  else: # Use Automatic
    dyn.kind = fwAuto
    dyn.magic = path.step
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
  if path.blend in {bnFlat, bnMarker, bnSmudge}:
    path.pipe.alpha = cint(alpha * 65535.0)
  # Pipeline Stage Flow
  path.pipe.flow =
    cint(flow * 65535.0)
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
      let
        t0 = path.mask.blot.tone
        tex0 = addr path.pipe.tex0
      tex0.tone(t0, flow, size)
  of bsBitmap: discard
  # Pipeline Stage Texture
  # ----------------------
  # Pipeline Stage Blocks
  reserve(path.pipe,
    r.x1, r.y1,
    r.x2, r.y2,
    r.shift)
  # Pipeline Stage Special
  case path.blend
  of bnBlur:
    let b = addr path.data.blur
    # Calculate Gaussian Kernel
    blur(path.pipe, b.radius)
  of bnSmudge: 
    let b = addr path.data.blur
    # Check Skip First
    if path.pipe.skip:
      path.pipe.alpha = 65536
    # Calculate Smudge Offset
    smudge(path.pipe, x - b.x, y - b.y)
    # Set Previous Position
    b.x = x; b.y = y
  else: discard
  # Expand Dirty AABB
  path.dirty(r)

proc prepare_stage1(path: var NBrushStroke, press: cfloat): bool =
  result = true
  # Pipeline Stage Blend
  case path.blend
  of bnAverage, bnWater:
    let 
      avg = addr path.data.avg
      # Ajust Interpolators Using Step
      ajust = 1.0 - pow(0.00005, path.step)
    var
      s = press
      b0, d0, p0: cfloat
    # Smootstep Pressure
    s = s - avg.p_minimun * s
    s = s * s * (3.0 - 2.0 * s)
    # Calculate Parameters
    b0 = avg.blending
    d0 = avg.dilution
    p0 = avg.persistence
    # Interpolate With Pressure
    if avg.p_blending:
      b0 = 1.0 + s * b0 - s
    if avg.p_dilution:
      d0 = 1.0 + s * d0 - s
    # Apply Ajust
    b0 = pow(b0, ajust)
    d0 = pow(d0, ajust)
    # Convert to Integer
    let
      b = cint(b0 * 65535.0)
      d = cint(d0 * 65535.0)
      p = cint(p0 * 65535.0)
    # Calcutate Averaged
    if not avg.glass:
      average(path.pipe, b, d, p)
    else: glass(path.pipe, b, p)
    # Calculate Watercolor
    if path.blend == bnWater:
      b0 = avg.watering
      # Ajust Amount
      if avg.p_watering:
        b0 = 1.0 + s * b0 - s
      b0 = pow(b0, ajust)
      # Convert to Fix15
      var w = cint(b0 * 65535.0)
      if not avg.coloring or avg.glass: w = -w
      # Apply Water Interpolation
      water(path.pipe, w)
  of bnMarker:
    let
      marker = addr path.data.marker
      # Ajust Interpolators Using Step
      ajust = 1.0 - pow(0.00005, path.step)
    var b0, p0, c0: cfloat
    # Calculate Parameters
    b0 = marker.blending
    p0 = marker.persistence
    # Interpolate With Pressure
    if marker.p_blending:
      c0 = press * press * (3.0 - 2.0 * press)
      # Apply Pressure to Blending
      b0 = 1.0 + c0 * b0 - c0
    # Apply Ajust
    if not path.pipe.skip:
      b0 = pow(b0, ajust)
    else:
      c0 = pow(b0, ajust)
      b0 = b0 + (c0 - b0) * b0
    # Convert to Integer
    let
      b = cint(b0 * 65535.0)
      p = cint(p0 * 65535.0)
    # Calculate Averaged
    average(path.pipe, b, 0, p)
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

proc evaluate(dyn: ptr NStrokeGeneric, basic: ptr NStrokeBasic, p, step: cfloat): cfloat =
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
  # Parameter Dynamics Shortcurts
  var size, alpha, flow: cfloat
  # Pressure Amplify
  size = pow(p, s_amp)
  alpha = pow(p, a_amp)
  # Apply Smoothstep to Pressure
  if dyn.kind == fwAuto:
    alpha = alpha * alpha * (3.0 - 2.0 * alpha)
  # Pressure Interpolation
  size = (s_st + s_dist * size) * basic.size
  alpha = (a_st + a_dist * alpha) * basic.alpha
  # Simulate Smallest
  if size < 2.5:
    alpha *= size * 0.4
    # Clamp Size
    size = 2.5
  # Ajust Distance Step With Size
  result = step + (1.0 / size)
  # Calculate Flow Opacity
  case dyn.kind
  of fwAuto:
    # Ajust Opacity With Size
    alpha = min(alpha, 0.99995)
    # Calculate Flow
    flow = 1.0 - alpha
    flow = pow(flow, result)
    flow = 1.0 - flow
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
    step = path.step
    # Pressure Interval
    p_start = a.press
    p_dist = # Distance
      b.press - a.press
  var
    t = start / length
    press, x, y, s: cfloat
  # Draw Each Stroke Point
  while t < 1.0:
    # Pressure Interpolation
    press = p_start + p_dist * t
    # Basic Brush Parameters
    s = dyn.evaluate(basic, press, step)
    # Current Position
    x = a.x + dx * t
    y = a.y + dy * t
    # Render Current Shape
    path.stage(dyn, x, y, press)
    # Step to Next Point
    t += dyn.size * (s / length)
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
