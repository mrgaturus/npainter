import nogui/ux/prelude
import nogui/builder
import nogui/values
# Import NPainter Engine
import engine, color
import ../../../wip/canvas/matrix
import ../../../wip/brush/stabilizer

# ----------------------
# Brush Shape Controller
# ----------------------

type
  CXBrushBasic = object
    size*: @ Lerp
    sizeMin*: @ Lerp
    sizeAmp*: @ Lerp2
    # Opacity Values
    opacity*: @ Lerp
    opacityMin*: @ Lerp
    opacityAmp*: @ Lerp2
    # Stabilizer
    stabilizer*: @ Lerp
  CXBrushCircle = object
    hardness*: @ Lerp
    sharpness*: @ Lerp
  CXBrushBlotmap = object
    hardness*: @ Lerp
    sharpness*: @ Lerp
    # Blotmap Texture
    mess*: @ Lerp
    scale*: @ Lerp2
    tone*: @ Lerp
    # Invert Blotmap
    invert*: @ bool
  CXBrushBitmap = object
    flow*: @ Lerp
    flowAuto*: @ bool
    # Spacing Control
    spacing*: @ Lerp
    spacingMess*: @ Lerp
    # Angle Control
    angle*: @ Lerp
    angleMess*: @ Lerp
    angleAuto*: @ bool
    # Scale Control
    aspect*: @ Lerp2
    scale*: @ Lerp
    scaleMess*: @ Lerp
  # Shape Controller
  CKBrushShape* = enum
    ckShapeCircle
    ckShapeBlotmap
    ckShapeBitmap
  CXBrushShape = object
    basic*: CXBrushBasic
    kind*: CKBrushShape
    # Brush Shape Data
    circle*: CXBrushCircle
    blotmap*: CXBrushBlotmap
    bitmap*: CXBrushBitmap

# ------------------------
# Brush Texture Controller
# ------------------------

type
  CXBrushTexture = object
    intensity*: @ Lerp
    scale*: @ Lerp2
    invert*, enabled*: @ bool
    # Scratch
    scratch*: @ Lerp
    minScratch*: @ Lerp

# -------------------------
# Brush Blending Controller
# -------------------------

type 
  CXBrushWater = object
    blending*: @ Lerp
    dilution*: @ Lerp
    persistence*: @ Lerp
    # Watercolor
    watering*: @ Lerp
    colouring*: @ bool
    # Pressure Control
    pBlending*: @ bool
    pDilution*: @ bool
    pWatering*: @ bool
    # Pressure Slider
    minimum*: @ Lerp
  CXBrushBlur = object
    size*: @ Lerp
    pressure*: @ bool
    minimum*: @ bool
  # Blending Controller
  CKBrushBlending* = enum
    ckBlendPen
    ckBlendPencil
    ckBlendEraser
    # Watercolors
    ckBlendBrush
    ckBlendWater
    ckBlendMarker
    # Smearings
    ckBlendBlur
    ckBlendSmudge
  CXBrushBlending = object
    kind*: CKBrushBlending
    # Brush Blending Data
    water*: CXBrushWater
    blur*: CXBrushBlur

# -----------------------
# Brush Engine Controller
# -----------------------

controller CXBrush:
  attributes: 
    {.public.}:
      # Change Callback
      shape: CXBrushShape
      texture: CXBrushTexture
      blending: CXBrushBlending
      # User Defined Callback
      onchange: GUICallback
    # TODO: Move this to a dispatch widget
    {.public, cursor.}:
      engine: NPainterEngine
      color: CXColor
    # XXX: proof of concept stabilizer
    stabilizer: NBrushStabilizer

  # -- Basic State -> Engine --
  proc prepareBasics() =
    let
      brush = addr self.engine.brush
      b0 = addr self.shape.basic
      b1 = addr brush.basic
    # Configure Basics Size
    b1.size = toRaw b0.size.peek[]
    b1.p_size = toRaw b0.sizeMin.peek[]
    # Configure Basics Opacity
    b1.alpha = toRaw b0.opacity.peek[]
    b1.p_alpha = toRaw b0.opacityMin.peek[]
    # Configure Basics Dynamics
    b1.amp_size = toFloat b0.sizeAmp.peek[]
    b1.amp_alpha = toFloat b0.opacityAmp.peek[]
    # Configure Stabilizer
    reset(self.stabilizer, toInt b0.stabilizer.peek[])

  proc prepareColor() =
    let
      brush = addr self.engine.brush
      c {.cursor.} = self.color
      # Lookup Current Color
      rgb = c.color.peek[].toRGB
      glass = c.eraser.peek[]
      # Unpack to Fix8
      r = cint(rgb.r * 255.0)
      g = cint(rgb.g * 255.0)
      b = cint(rgb.b * 255.0)
    # Configure Current Color
    brush[].color(r, g, b, glass)

  # -- Shape State -> Engine --
  proc prepareCircle() =
    let 
      brush = addr self.engine.brush
      circle0 = addr self.shape.circle
      circle1 = addr brush.mask.circle
    # Configure Hardness And Sharpness
    circle1.hard = toRaw circle0.hardness.peek[]
    circle1.sharp = toRaw circle0.sharpness.peek[]
    # Configure Shape Mode
    brush.shape = bsCircle

  proc prepareBlotmap() =
    let 
      brush = addr self.engine.brush
      blot0 = addr self.shape.blotmap
      blot1 = addr brush.mask.blot
    # Configure Blotmap Circle
    blot1.hard = toRaw blot0.hardness.peek[]
    blot1.sharp = toRaw blot0.sharpness.peek[]
    # Configure Blotmap Texture
    blot1.fract = toRaw blot0.mess.peek[]
    blot1.scale = toFloat blot0.scale.peek[]
    blot1.tone = toRaw blot0.tone.peek[]
    blot1.invert = blot0.invert.peek[]
    # Configure Shape Mode
    brush.shape = bsBlotmap
    blot1.texture = addr self.engine.tex0

  proc prepareBitmap() =
    let 
      brush = addr self.engine.brush
      bm0 = addr self.shape.bitmap
      bm1 = addr brush.mask.bitmap
    # Configure Bitmap
    bm1.flow = toRaw bm0.flow.peek[]
    bm1.step = toRaw bm0.spacing.peek[]
    bm1.angle = toRaw bm0.angle.peek[]
    bm1.aspect = toRaw bm0.aspect.peek[]
    bm1.scale = toRaw bm0.scale.peek[]
    # Configure Bitmap Scattering
    bm1.s_space = toRaw bm0.spacingMess.peek[]
    bm1.s_angle = toRaw bm0.angleMess.peek[]
    bm1.s_scale = toRaw bm0.scaleMess.peek[]
    # Configure Bitmap Automatic
    bm1.auto_flow = bm0.flowAuto.peek[]
    bm1.auto_angle = # XXX: Bitmap Auto-angle, this needs to be enum
      if bm0.angleAuto.peek[]: 255 else: 0
    # Configure Bitmap Mode
    brush.shape = bsBitmap
    bm1.texture = addr self.engine.tex1

  # -- Texture State -> Engine --
  proc prepareTexture() =
    let 
      brush = addr self.engine.brush
      tex0 = addr self.texture
      tex1 = addr brush.texture
    # Configure Texture
    tex1.fract = toRaw tex0.intensity.peek[]
    tex1.scale = toFloat tex0.scale.peek[]
    tex1.invert = tex0.invert.peek[]
    tex1.enabled = tex0.enabled.peek[] and tex1.fract > 0.0
    # Configure Texture Scratch
    tex1.scratch = toRaw tex0.scratch.peek[]
    tex1.p_scratch = toRaw tex0.minScratch.peek[]
    tex1.texture = addr self.engine.tex2

  # -- Blending State -> Engine --
  proc prepareWater(mode: NBrushBlend) =
    let 
      brush = addr self.engine.brush
      avg0 = addr self.blending.water
      avg1 = addr brush.data.avg
    # Configure Average
    avg1.blending = toRaw avg0.blending.peek[]
    avg1.dilution = toRaw avg0.dilution.peek[]
    avg1.persistence = toRaw avg0.persistence.peek[]
    avg1.watering = toRaw avg0.watering.peek[]
    avg1.coloring = avg0.colouring.peek[]
    # Configure Average Pressure
    avg1.p_blending = avg0.pBlending.peek[]
    avg1.p_dilution = avg0.pDilution.peek[]
    avg1.p_watering = avg0.pWatering.peek[]
    avg1.p_minimun = toRaw avg0.minimum.peek[]
    # Configure Average Mode
    brush.blend = mode

  proc prepareMarker() =
    let
      brush = addr self.engine.brush
      avg0 = addr self.blending.water
      avg1 = addr brush.data.marker
    # Configure Marker
    avg1.blending = toRaw avg0.blending.peek[]
    avg1.persistence = toRaw avg0.dilution.peek[]
    avg1.p_blending = avg0.pBlending.peek[]
    # Configure Marker Mode
    brush.blend = bnMarker
  
  proc prepareBlur() =
    let
      brush = addr self.engine.brush
      blur0 = addr self.blending.blur
      blur1 = addr brush.data.blur
    # Configure Blur
    blur1.radius = toRaw blur0.size.peek[]
    # Configure Blur Mode
    brush.blend = bnBlur

  # -- Dispatch Preparing --
  proc prepareDispatch() =
    let brush = addr self.engine.brush
    # Configure Basics
    self.prepareBasics()
    # Configure Shape
    case self.shape.kind
    of ckShapeCircle: self.prepareCircle()
    of ckShapeBlotmap: self.prepareBlotmap()
    of ckShapeBitmap: self.prepareBitmap()
    # Configure Texture
    self.prepareTexture()
    # Configure Blending
    case self.blending.kind
    of ckBlendPen: brush.blend = bnFlat
    of ckBlendPencil: brush.blend = bnPencil
    of ckBlendEraser: brush.blend = bnEraser
    of ckBlendBrush: self.prepareWater(bnAverage)
    of ckBlendWater: self.prepareWater(bnWater)
    of ckBlendMarker: self.prepareMarker()
    of ckBlendBlur: self.prepareBlur()
    of ckBlendSmudge: brush.blend = bnSmudge
    # Prepare Brush Dispatch
    self.prepareColor()
    brush[].prepare()

  # -- Callbacks --
  callback cbChange:
    force(self.onchange)

  callback cbDispathStroke(e: AuxState):
    let
      engine {.cursor.} = self.engine
      brush = addr engine.brush
    # Dispath Stroke Path
    engine.pool.start()
    brush[].dispatch()
    engine.pool.stop()
    # TODO: move this to canvas side
    let
      canvas = addr engine.canvas
      ctx = addr engine.canvas.ctx
      aabb = addr brush.aabb
    # Clamp to Canvas
    aabb.x1 = max(0, aabb.x1)
    aabb.y1 = max(0, aabb.y1)
    aabb.x2 = min(ctx.w, aabb.x2)
    aabb.y2 = min(ctx.h, aabb.y2)
    # Copy To Buffer
    canvas[].mark(
      aabb.x1, aabb.y1, 
      aabb.x2 - aabb.x1,
      aabb.y2 - aabb.y1)
    canvas[].clean()
    # Reset Dirty Region
    aabb.x1 = high(int32); aabb.x2 = 0
    aabb.y1 = high(int32); aabb.y2 = 0
    # Release Anti Flooding
    e.release()

  callback cbDispatch(e: AuxState):
    if e.first:
      self.prepareDispatch()
      e.pressure = 0.0
    # Start Dragging Brush
    if (e.flags and wGrab) == wGrab and e.click0 == LeftButton:
      let
        engine {.cursor.} = self.engine
        affine = engine.canvas.affine
        p = affine[].forward(e.x, e.y)
        press = e.pressure
      # Push Point to Path
      if self.stabilizer.capacity > 0:
        let ps = self.stabilizer.smooth(p.x, p.y, press, 0.0)
        point(engine.brush, ps.x, ps.y, ps.press, 0.0)
      else: point(engine.brush, p.x, p.y, press, 0.0)
      # XXX: this hacky guard avoids event flooding
      if e.guard():
        push(self.cbDispathStroke, e[])
    # XXX: hacky way to endpoint stabilizer
    elif e.kind == evCursorRelease and e.click0 == LeftButton:
      let
        engine {.cursor.} = self.engine
        affine = engine.canvas.affine
        p = affine[].forward(e.x, e.y)
        cap = self.stabilizer.capacity
      # Push Point to Path
      for _ in 0 ..< cap:
        let ps = self.stabilizer.smooth(p.x, p.y, e.pressure, 0.0)
        point(engine.brush, ps.x, ps.y, ps.press, 0.0)
      # XXX: this hacky guard avoids event flooding
      if e.guard():
        push(self.cbDispathStroke, e[])

  # -- Initializers --
  proc initShape =
    let 
      shape = addr self.shape
      basic = addr shape.basic
      circle = addr shape.circle
      blotmap = addr shape.blotmap
      bitmap = addr shape.bitmap
    # Initialize Lerps
    let
      lerpSize = lerp(0, 1000)
      lerpBasic = lerp(0, 100)
      lerpScale = lerp2(0.1, 1.0, 5)
      lerpAspect = lerp2(0.0, 1.0)
      lerpSpacing = lerp(2.5, 50)
      lerpAngle = lerp(0, 360)
      lerpAmp = lerp2(0.25, 1.0, 4)
      lerpStabilizer = lerp(0, 64)
    # Initialize Basics
    basic.size = lerpSize.value
    basic.sizeMin = lerpBasic.value
    basic.sizeAmp = lerpAmp.value
    basic.opacity = lerpBasic.value
    basic.opacityMin = lerpBasic.value
    basic.opacityAmp = lerpAmp.value
    basic.stabilizer = lerpStabilizer.value
    # Initialize Circle
    circle.hardness = lerpBasic.value
    circle.sharpness = lerpBasic.value
    # Initialize Blotmap
    blotmap.hardness = lerpBasic.value
    blotmap.sharpness = lerpBasic.value
    blotmap.mess = lerpBasic.value
    blotmap.scale = lerpScale.value
    blotmap.tone = lerpBasic.value
    # Initialize Bitmap
    bitmap.flow = lerpBasic.value
    bitmap.spacing = lerpSpacing.value
    bitmap.spacingMess = lerpBasic.value
    bitmap.angle = lerpAngle.value
    bitmap.angleMess = lerpBasic.value
    bitmap.aspect = lerpAspect.value
    bitmap.scale = lerpBasic.value
    bitmap.scaleMess = lerpBasic.value

  proc initTexture =
    let 
      tex = addr self.texture
      lerpBasic = lerp(0, 100)
      lerpScale = lerp2(0.1, 1.0, 5)
    # Basic Texture
    tex.intensity = lerpBasic.value
    tex.scale = lerpScale.value
    # Scratch Texture
    tex.scratch = lerpBasic.value
    tex.minScratch = lerpBasic.value

  proc initBlending =
    let 
      blend = addr self.blending
      water = addr blend.water
      blur = addr blend.blur
      lerpBasic = lerp(0, 100)
    # -- Initialize Watercolor
    water.blending = lerpBasic.value
    water.dilution = lerpBasic.value
    water.persistence = lerpBasic.value
    water.watering = lerpBasic.value
    water.minimum = lerpBasic.value
    # -- Initialize Blur
    blur.size = lerpBasic.value

  # -- Constructor --
  new cxbrush():
    # Init Value Ranges
    result.initShape()
    result.initTexture()
    result.initBlending()

# -------------------------------
# Proof of Concept Default Values
# TODO: create brush presets
# -------------------------------

proc proof0basic(basic: ptr CXBrushBasic) =
  # Default Size
  lorp basic.size.peek[], 10
  lerp basic.sizeMin.peek[], 0.2
  lerp basic.sizeAmp.peek[], 0.5
  # Default Opacity
  lerp basic.opacity.peek[], 1.0
  lerp basic.opacityMin.peek[], 1.0
  lerp basic.opacityAmp.peek[], 0.5
  # Default Stabilizer
  lorp basic.stabilizer.peek[], 4

proc proof0shapes(shape: ptr CXBrushShape) =
  let
    circle = addr shape.circle
    blot = addr shape.blotmap
    bitmap = addr shape.bitmap
  # Default Circle Values
  lerp circle.hardness.peek[], 1.0
  lerp circle.sharpness.peek[], 0.5
  # Default Blotmap Values
  lerp blot.hardness.peek[], 1.0
  lerp blot.sharpness.peek[], 0.5
  lerp blot.mess.peek[], 0.75
  lerp blot.scale.peek[], 0.5
  lerp blot.tone.peek[], 0.5
  # Default Bitmap Values
  bitmap.flowAuto.peek[] = true
  bitmap.angleAuto.peek[] = true
  lerp bitmap.flow.peek[], 1.0
  lorp bitmap.spacing.peek[], 4.0
  lerp bitmap.aspect.peek[], 0.5
  lerp bitmap.scale.peek[], 1.0

proc proof0texture(tex: ptr CXBrushTexture) =
  lerp tex.intensity.peek[], 0.75
  lerp tex.scale.peek[], 0.5
  lerp tex.scratch.peek[], 0.25

proc proof0water(water: ptr CXBrushWater) =
  lerp water.blending.peek[], 0.75
  lerp water.persistence.peek[], 0.25
  lerp water.watering.peek[], 0.25
  # Activate Switching
  water.pBlending.peek[] = true
  water.pWatering.peek[] = true
  water.colouring.peek[] = true

proc proof0default*(brush: CXBrush) =
  let 
    shape = addr brush.shape
    blend = addr brush.blending
  proof0basic(addr shape.basic)
  proof0shapes(shape)
  proof0texture(addr brush.texture)
  proof0water(addr blend.water)
  # Configure Blur Amount
  lorp blend.blur.size.peek[], 20
