import nogui/builder
import nogui/ux/prelude
import nogui/ux/values/[linear, dual, chroma]
# Import NPainter Engine
import engine, color
from ../../wip/image/proxy import
  NImageProxy, commit
import ../../wip/canvas/matrix
import ../../wip/brush/stabilizer

# ----------------------
# Brush Shape Controller
# ----------------------

type
  CXBrushBasic = object
    size*: @ Linear
    sizeMin*: @ Linear
    sizeAmp*: @ LinearDual
    # Opacity Values
    opacity*: @ Linear
    opacityMin*: @ Linear
    opacityAmp*: @ LinearDual
    # Stabilizer Level
    stabilizer*: @ Linear
  CXBrushCircle = object
    hardness*: @ Linear
    sharpness*: @ Linear
  CXBrushBlotmap = object
    hardness*: @ Linear
    sharpness*: @ Linear
    # Blotmap Texture
    mess*: @ Linear
    scale*: @ LinearDual
    tone*: @ Linear
    # Invert Blotmap
    invert*: @ bool
  CXBrushBitmap = object
    flow*: @ Linear
    flowAuto*: @ bool
    # Spacing Control
    spacing*: @ Linear
    spacingMess*: @ Linear
    # Angle Control
    angle*: @ Linear
    angleMess*: @ Linear
    angleAuto*: @ bool
    # Scale Control
    aspect*: @ LinearDual
    scale*: @ Linear
    scaleMess*: @ Linear
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
    intensity*: @ Linear
    scale*: @ LinearDual
    invert*, enabled*: @ bool
    # Scratch
    scratch*: @ Linear
    minScratch*: @ Linear

# -------------------------
# Brush Blending Controller
# -------------------------

type 
  CXBrushWater = object
    blending*: @ Linear
    dilution*: @ Linear
    persistence*: @ Linear
    # Watercolor
    watering*: @ Linear
    colouring*: @ bool
    # Pressure Control
    pBlending*: @ bool
    pDilution*: @ bool
    pWatering*: @ bool
    # Pressure Slider
    minimum*: @ Linear
  CXBrushBlur = object
    size*: @ Linear
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
    {.cursor.}:
      engine: NPainterEngine
      color: CXColor
    # Brush Properties
    {.public.}:
      shape: CXBrushShape
      texture: CXBrushTexture
      blending: CXBrushBlending
      # User Defined Callback
      onchange: GUICallback

  callback cbChange:
    force(self.onchange)

  # -- Initializers --
  proc initShape =
    let 
      shape = addr self.shape
      basic = addr shape.basic
      circle = addr shape.circle
      blotmap = addr shape.blotmap
      bitmap = addr shape.bitmap
    # Initialize Linears
    let
      liSize = linear(0, 1000)
      liBasic = linear(0, 100)
      duScale = dual(0.1, 1.0, 5)
      duAspect = dual(0.0, 1.0)
      liSpacing = linear(2.5, 50)
      liAngle = linear(0, 360)
      duAmp = dual(0.25, 1.0, 4)
      liStabilizer = linear(0, 64)
    # Initialize Basics
    basic.size = liSize
    basic.sizeMin = liBasic
    basic.sizeAmp = duAmp
    basic.opacity = liBasic
    basic.opacityMin = liBasic
    basic.opacityAmp = duAmp
    basic.stabilizer = liStabilizer
    # Initialize Circle
    circle.hardness = liBasic
    circle.sharpness = liBasic
    # Initialize Blotmap
    blotmap.hardness = liBasic
    blotmap.sharpness = liBasic
    blotmap.mess = liBasic
    blotmap.scale = duScale
    blotmap.tone = liBasic
    # Initialize Bitmap
    bitmap.flow = liBasic.value
    bitmap.spacing = liSpacing
    bitmap.spacingMess = liBasic
    bitmap.angle = liAngle
    bitmap.angleMess = liBasic
    bitmap.aspect = duAspect
    bitmap.scale = liBasic
    bitmap.scaleMess = liBasic

  proc initTexture =
    let 
      tex = addr self.texture
      liBasic = linear(0, 100)
      duScale = dual(0.1, 1.0, 5)
    # Basic Texture
    tex.intensity = liBasic
    tex.scale = duScale
    # Scratch Texture
    tex.scratch = liBasic
    tex.minScratch = liBasic

  proc initBlending =
    let 
      blend = addr self.blending
      water = addr blend.water
      blur = addr blend.blur
      liBasic = linear(0, 100)
    # -- Initialize Watercolor
    water.blending = liBasic
    water.dilution = liBasic
    water.persistence = liBasic
    water.watering = liBasic
    water.minimum = liBasic
    # -- Initialize Blur
    blur.size = liBasic

  # -- Constructor --
  new cxbrush(engine: NPainterEngine, color: CXColor):
    result.engine = engine
    result.color = color
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

# ---------------------
# Brush Engine Dispatch
# TODO: move stabilizer logic to engine
# ---------------------

widget UXBrushDispatch:
  attributes:
    {.cursor.}:
      brush: CXBrush
    proxy: ptr NImageProxy
    stabilizer: NBrushStabilizer

  new uxbrushdispatch(brush: CXBrush):
    result.brush = brush

  # -- Basic State -> Engine --
  proc prepareBasics() =
    let
      brush0 {.cursor.} = self.brush
      brush = addr brush0.engine.brush
      b0 = addr brush0.shape.basic
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
      brush0 {.cursor.} = self.brush
      brush = addr brush0.engine.brush
      c {.cursor.} = brush0.color
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
      brush0 {.cursor.} = self.brush
      brush = addr brush0.engine.brush
      circle0 = addr brush0.shape.circle
      circle1 = addr brush.mask.circle
    # Configure Hardness And Sharpness
    circle1.hard = toRaw circle0.hardness.peek[]
    circle1.sharp = toRaw circle0.sharpness.peek[]
    # Configure Shape Mode
    brush.shape = bsCircle

  proc prepareBlotmap() =
    let
      brush0 {.cursor.} = self.brush
      brush = addr brush0.engine.brush
      blot0 = addr brush0.shape.blotmap
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
    blot1.texture = addr brush0.engine.tex0

  proc prepareBitmap() =
    let
      brush0 {.cursor.} = self.brush
      brush = addr brush0.engine.brush
      bm0 = addr brush0.shape.bitmap
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
    # XXX: Bitmap Auto-angle, needs to be enum
    bm1.auto_flow = bm0.flowAuto.peek[]
    bm1.auto_angle = if bm0.angleAuto.peek[]: 255 else: 0
    # Configure Bitmap Mode
    brush.shape = bsBitmap
    bm1.texture = addr brush0.engine.tex1

  # -- Texture State -> Engine --
  proc prepareTexture() =
    let
      brush0 {.cursor.} = self.brush
      brush = addr brush0.engine.brush
      tex0 = addr brush0.texture
      tex1 = addr brush.texture
    # Configure Texture
    tex1.fract = toRaw tex0.intensity.peek[]
    tex1.scale = toFloat tex0.scale.peek[]
    tex1.invert = tex0.invert.peek[]
    tex1.enabled = tex0.enabled.peek[] and tex1.fract > 0.0
    # Configure Texture Scratch
    tex1.scratch = toRaw tex0.scratch.peek[]
    tex1.p_scratch = toRaw tex0.minScratch.peek[]
    tex1.texture = addr brush0.engine.tex2

  # -- Blending State -> Engine --
  proc prepareWater(mode: NBrushBlend) =
    let
      brush0 {.cursor.} = self.brush
      brush = addr brush0.engine.brush
      avg0 = addr brush0.blending.water
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
      brush0 {.cursor.} = self.brush
      brush = addr brush0.engine.brush
      avg0 = addr brush0.blending.water
      avg1 = addr brush.data.marker
    # Configure Marker
    avg1.blending = toRaw avg0.blending.peek[]
    avg1.persistence = toRaw avg0.dilution.peek[]
    avg1.p_blending = avg0.pBlending.peek[]
    # Configure Marker Mode
    brush.blend = bnMarker
  
  proc prepareBlur() =
    let
      brush0 {.cursor.} = self.brush
      brush = addr brush0.engine.brush
      blur0 = addr brush0.blending.blur
      blur1 = addr brush.data.blur
    # Configure Blur
    blur1.radius = toRaw blur0.size.peek[]
    # Configure Blur Mode
    brush.blend = bnBlur

  # -- Dispatch Preparing --
  proc prepareDispatch() =
    let
      brush0 {.cursor.} = self.brush
      engine {.cursor.} = brush0.engine
      brush = addr engine.brush
    # Prepare Brush Proxy
    self.proxy = engine.proxyBrush0proof()
    brush.proxy = self.proxy
    # Configure Basics
    self.prepareBasics()
    # Configure Shape
    case brush0.shape.kind
    of ckShapeCircle: self.prepareCircle()
    of ckShapeBlotmap: self.prepareBlotmap()
    of ckShapeBitmap: self.prepareBitmap()
    # Configure Texture
    self.prepareTexture()
    # Configure Blending
    case brush0.blending.kind
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

  # -- Dispatch Callbacks --
  callback cbDispatchStroke:
    let engine {.cursor.} = self.brush.engine
    # Dispath Stroke Path
    engine.pool.start()
    engine.brush.dispatch()
    engine.canvas.update()
    engine.pool.stop()

  callback cbCommitStroke:
    self.proxy[].commit()
    self.brush.engine.clearProxy()

  # -- Dispatch Event --
  method event(state: ptr GUIState) =
    let
      engine {.cursor.} = self.brush.engine
      stable = addr self.stabilizer
      brush = addr engine.brush
      affine = engine.canvas.affine
    # Prepare Brush Dispatch
    if state.kind == evCursorClick:
      self.prepareDispatch()
      state.pressure = 0.0
    # Start Dragging Brush Stroke
    if self.test(wGrab):
      let
        # Transfrom Point to Canvas Coordinates
        p = affine[].forward(state.px, state.py)
        press = state.pressure
      # TODO: move stabilizer logic to engine
      if stable.capacity > 0:
        let ps = stable[].smooth(p.x, p.y, press, 0.0)
        brush[].point(ps.x, ps.y, ps.press, 0.0)
      else: brush[].point(p.x, p.y, press, 0.0)
      # Send Dispatch Stroke
      relax(self.cbDispatchStroke)
    # Terminate Brush Stroke
    elif state.kind == evCursorRelease:
      let
        # Transfrom Point to Canvas Coordinates
        p = affine[].forward(state.px, state.py)
        press = state.pressure
        cap = stable.capacity
      # TODO: move stabilizer logic to engine
      for _ in 0 ..< cap:
        let ps = stable[].smooth(p.x, p.y, press, 0.0)
        brush[].point(ps.x, ps.y, ps.press, 0.0)
      # Send Dispatch Stroke
      relax(self.cbDispatchStroke)
      relax(self.cbCommitStroke)

  method handle(reason: GUIHandle) =
    echo "brush reason: ", reason
