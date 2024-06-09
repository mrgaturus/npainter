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
    # Stabilizer
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
    proxy: ptr NImageProxy
    finalized: bool

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
    # Prepare Brush Proxy
    self.proxy = self.engine.proxyBrush0proof()
    brush.proxy = self.proxy
    self.finalized = false
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

  callback cbDispatchStroke:
    let
      engine {.cursor.} = self.engine
      brush = addr engine.brush
      canvas = addr engine.canvas
    # Dispath Stroke Path
    engine.pool.start()
    brush[].dispatch()
    canvas[].update()
    engine.pool.stop()
    # Release Anti Flooding
    if self.finalized:
      self.proxy[].commit()
      self.engine.clearProxy()

  callback cbDispatch:
    let
      engine {.cursor.} = self.engine
      state0 = addr engine.state0
      state = engine.state
      # Check Clicked Grab
      locked = state0.locked
      button = state0.button == Button_Left
      # Brush Engine Pointer
      stable = addr self.stabilizer
      brush = addr engine.brush
    # Prepare Brush Dispatch
    # TODO: move stabilizer logic to engine
    if state.kind == evCursorClick:
      self.prepareDispatch()
      state.pressure = 0.0
    # Start Dragging Brush
    if locked and button:
      let
        engine {.cursor.} = self.engine
        affine = engine.canvas.affine
        # Transfrom Point to Canvas Coordinates
        p = affine[].forward(state.px, state.py)
        press = state.pressure
      # Push Point to Path
      if stable.capacity > 0:
        let ps = stable[].smooth(p.x, p.y, press, 0.0)
        brush[].point(ps.x, ps.y, ps.press, 0.0)
      else: brush[].point(p.x, p.y, press, 0.0)
      # Send Dispatch Stroke
      relax(self.cbDispatchStroke)
    # XXX: hacky way to endpoint stabilizer
    elif not locked and button:
      let
        engine {.cursor.} = self.engine
        affine = engine.canvas.affine
        cap = stable.capacity
        # Transfrom Point to Canvas Coordinates
        p = affine[].forward(state.px, state.py)
        press = state.pressure
      # Push Point to Path
      for _ in 0 ..< cap:
        let ps = stable[].smooth(p.x, p.y, press, 0.0)
        brush[].point(ps.x, ps.y, ps.press, 0.0)
      # Send Dispatch Stroke
      self.finalized = true
      relax(self.cbDispatchStroke)

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
