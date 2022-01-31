import texture
import brush/pipe
# Import Math
from math import 
  floor, ceil,
  sqrt, pow, log2,
  # Angle Calculation
  sin, cos, arctan2
# Import 2PI Constant
const pi2 = 6.283185307179586
# Import Scattering
from random import 
  Rand, gauss, initRand
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
    flow*, step*: cfloat
    # Angle & Aspect Ratio
    scale*, angle*, aspect*: cfloat
    # Automatic Calculation
    auto_flow*: bool
    auto_angle*: byte
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
    x, y, press, angle: float32
  # ----------------
  NStrokeAngle = enum
    faAuto, faStylus, faNone
  NStrokeFlow = enum
    fwAuto, fwFlat, fwCustom
  NStrokeGeneric = object
    # Staged Position
    x, y: cfloat
    # Staged Shape
    size, angle: cfloat
    turn: NStrokeAngle
    # Staged Opacity
    alpha, flow: cfloat
    kind: NStrokeFlow
    # Constant Flow Kind
    magic: cfloat
    # Bitmap Randomizer
    affine: bool
    rng: Rand
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
    # Bind Pipeline Texture to Blotmap
    path.pipe.mask.blotmap.tex = tex0
  of bsBitmap:
    let
      tex0 = addr path.pipe.tex0
      step = path.mask.bitmap.step
    path.step = 0.025 + 0.975 * step
    # Bind Pipeline Texture to Blotmap
    path.pipe.mask.bitmap.tex = tex0
  # Define Flow Calculation
  if blend in {bnFlat, bnMarker, bnSmudge}:
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
  # Define Bitmap Calculation
  if shape == bsBitmap:
    let b = addr path.mask.bitmap
    # Configure Affine Mode
    dyn.affine = true
    # Configure Flow Mode
    if not b.auto_flow:
      dyn.kind = fwCustom
      dyn.magic = b.flow
    # Configure Angle Mode
    case b.auto_angle
    of 0: dyn.turn = faNone
    of 255: dyn.turn = faAuto
    else: dyn.turn = faStylus
  else:
    dyn.affine = false
    dyn.turn = faNone
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

proc region(x, y, size, angle: cfloat): NStrokeRegion =
  let
    ca = cos(angle).abs()
    sa = sin(angle).abs()
    # Calculate Orient
    ow = ca + sa
    oh = sa + ca
  var
    w = size * ow
    h = size * oh
  # Block Size Shifting
  result.shift = max(w, h).log2().cint
  # Interval Half Size
  w *= 0.5; h *= 0.5
  # Interval Region
  result.x1 = floor(x - w).cint
  result.y1 = floor(y - h).cint
  result.x2 = ceil(x + w).cint
  result.y2 = ceil(y + h).cint

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

proc prepare_stage0(path: var NBrushStroke, dyn: ptr NStrokeGeneric) =
  let
    x = dyn.x
    y = dyn.y
    # Basic Dynamics
    size = dyn.size
    angle = dyn.angle
    alpha = dyn.alpha
    flow = dyn.flow
    # Path Shortcut
    mask = addr path.pipe.mask
  # Pipeline Stage Alpha
  if path.blend in {bnFlat, bnMarker, bnSmudge}:
    path.pipe.alpha = cint(alpha * 65535.0)
  # Pipeline Stage Flow
  path.pipe.flow =
    cint(flow * 65535.0)
  # Pipeline Stage Region
  var r: NStrokeRegion
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
    # Brush Circle Region
    r = region(x, y, size)
  of bsBitmap:
    # Generate New Random
    if path.pipe.skip:
      let seed = cast[int64](x + y)
      path.generic.rng = initRand(seed)
    let
      # Scatter Shortcut
      b = addr path.mask.bitmap
      tex0 = mask.bitmap.tex
      # Random Generator Gaussian
      r0 = gauss(dyn.rng, 0.0, 1.0)
      r1 = gauss(dyn.rng, 0.0, 1.0)
      # Random Generator Normalized
      r2 = r0 - floor(r0)
      # Random Interpolator
      s_space = size * b.s_space
      s_angle = r1 * b.s_angle
      s_scale = 1.0 + (r2 - 1.0) * b.s_scale
      # Scatter Position
      x1 = x + r0 * s_space
      y1 = y + r1 * s_space
      # Scatter Angle / Scale
      a1 = pi2 * (b.angle + s_angle + angle)
      s1 = max(size * b.scale * s_scale, 1.0)
      # Bitmap Aspect Ratio
      wh = 2.0 * b.aspect - 1.0
    # Configure Bitmap Buffer
    var
      offset: cfloat
      mip = raw(b.texture)
    image(tex0, mip.w, mip.h, mip.buffer)
    # Configure Bitmap Scaling
    offset = scaling(mask.bitmap, s1, wh)
    if offset < 1.0:
      mip = raw(b.texture, offset)
      image(tex0, mip.w, mip.h, mip.buffer)
      # Configure Mipmaped Scaling
      offset = scaling(mask.bitmap, s1, wh)
    offset *= 2.0
    # Configure Bitmap Affine
    affine(mask.bitmap, x1, y1, a1)
    # Calculare Brush Bitmap Region
    r = region(x1, y1, s1 + offset, a1)
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

proc stage(path: var NBrushStroke; dyn: ptr NStrokeGeneric; press: cfloat) =
  # Pipeline Stage 0
  prepare_stage0(path, dyn)
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
  # Ajust Size and Distance
  if not dyn.affine:
    if size < 2.5:
      alpha *= size * 0.4
      # Clamp Size
      size = 2.5
    # Ajust Step With Size
    result = step + (1.0 / size)
  else:
    if size < 1.0:
      alpha *= size
      # Clamp Size
      size = 1.0
    # Ajust Step With Size
    result = max(step, 1.0 / size)
  # Calculate Flow Opacity
  case dyn.kind
  of fwAuto:
    # Ajust Opacity With Size
    alpha = min(alpha, 0.99995)
    # Calculate Flow
    flow = 1.0 - alpha
    flow = pow(flow, result)
    flow = 1.0 - flow
  of fwFlat:
    flow = dyn.magic
  of fwCustom:
    flow = dyn.magic * alpha
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
    da, press, s: cfloat
  # Calculate Angle Distance
  da = (b.angle - a.angle + 0.5)
  da = da - floor(da) - 0.5
  if da < -0.5: da += 1.0
  # Draw Each Stroke Point
  while t < 1.0:
    # Pressure Interpolation
    press = p_start + p_dist * t
    # Basic Brush Parameters
    s = dyn.evaluate(basic, press, step)
    # Current Position
    dyn.x = a.x + dx * t
    dyn.y = a.y + dy * t
    # Current Angle
    dyn.angle = a.angle + da * t
    if dyn.angle < 0.0:
      dyn.angle += 1.0
    # Render Current Shape
    path.stage(dyn, press)
    # Step to Next Point
    t += dyn.size * (s / length)
  # Return Remainder
  result = length * (t - 1.0)

# ------------------------
# BRUSH POINT MANIPULATION
# ------------------------

proc point*(path: var NBrushStroke; x, y, press, angle: cfloat) =
  var p: NStrokePoint
  # Point Position
  p.x = x; p.y = y
  # Point Angle
  case path.generic.turn
  of faNone: p.angle = 0.0
  of faStylus: p.angle = angle
  of faAuto:
    var omega: cfloat
    # Calculate Angle for Two Points
    if len(path.points) > 0:
      let
        basic = addr path.basic
        prev = addr path.points[^1]
        # Calculate Delta Position
        dx = p.x - prev.x
        dy = p.y - prev.y
        # Calculate Distance
        dist = sqrt(dx * dx + dy * dy)
        # Calculate Minimun Size
        p_size = basic.p_size
        # Calculate Minimun Distance
        t = p_size + press - press * p_size
        limit = path.step * basic.size * t
      # Skip Not Enough Distance
      if dist < limit * 0.5: return
      # Calculate Angle
      omega = arctan2(dy, dx)
      if omega < 0.0: omega += pi2
      omega = omega / pi2
      # Replace First Angle
      if prev.angle > 1.0:
        prev.angle = omega
        prev.press = press
      # Set Current Angle
      p.angle = omega
    else: p.angle = 2.0
  # Avoid 0.0 Infinite Loop
  p.press = max(press, 0.0001)
  # Add New Point
  path.points.add(p)

proc dispatch*(path: var NBrushStroke) =
  let count = len(path.points)
  # Draw Point Line
  if count > 1:
    var a, b: NStrokePoint
    # Draw Each Line
    for i in 1 ..< count:
      a = path.points[i - 1]
      b = path.points[i]
      # Draw Brush Line
      path.prev_t = path.line(
        a, b, path.prev_t)
    # Set Last Point to First
    path.points[0] = path.points[^1]
    setLen(path.points, 1)
