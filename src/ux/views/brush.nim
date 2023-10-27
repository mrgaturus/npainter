import nogui/ux/prelude
import nogui/builder
# Import Values
import nogui/values

# ----------------------
# Brush Shape Controller
# ----------------------

type
  CXBrushBasic = object
    size*: @ Lerp
    sizeMin*: @ Lerp
    sizeAmp*: @ Lerp
    # Opacity Values
    opacity*: @ Lerp
    opacityMin*: @ Lerp
    opacityAmp*: @ Lerp
  CXBrushCircle = object
    hardness*: @ Lerp
    sharpness*: @ Lerp
  CXBrushBlotmap = object
    hardness*: @ Lerp
    sharpness*: @ Lerp
    # Blotmap Texture
    mess*: @ Lerp
    scale*: @ Lerp
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
    aspect*: @ Lerp
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
    scale*: @ Lerp
    invert*: @ bool
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
    ckBlendPencil
    ckBlendPen
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
  attributes: {.public.}:
    # Change Callback
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
    # -- Initialize Basics
    basic.size = lerp(0, 100).value
    basic.sizeMin = lerp(0, 100).value
    basic.sizeAmp = lerp(-100, 100).value
    basic.opacity = lerp(0, 100).value
    basic.opacityMin = lerp(0, 100).value
    basic.opacityAmp = lerp(-100, 100).value
    # -- Initialize Circle
    circle.hardness = lerp(0, 100).value
    circle.sharpness = lerp(0, 100).value
    # -- Initialize Blotmap
    blotmap.hardness = lerp(0, 100).value
    blotmap.sharpness = lerp(0, 100).value
    blotmap.mess = lerp(0, 100).value
    blotmap.scale = lerp(10, 500).value
    blotmap.tone = lerp(0, 100).value
    # -- Initialize Bitmap
    bitmap.flow = lerp(0, 100).value
    bitmap.spacing = lerp(2.5, 50).value
    bitmap.spacingMess = lerp(2.5, 50).value
    bitmap.angle = lerp(0, 360).value
    bitmap.angleMess = lerp(0, 100).value
    bitmap.aspect = lerp(-100, 100).value
    bitmap.scale = lerp(0, 100).value
    bitmap.scaleMess = lerp(0, 100).value

  proc initTexture =
    let tex = addr self.texture
    tex.intensity = lerp(0, 100).value
    tex.scale = lerp(10, 500).value
    # Scratch Texture
    tex.scratch = lerp(0, 100).value
    tex.minScratch = lerp(0, 100).value

  proc initBlending =
    let 
      blend = addr self.blending
      water = addr blend.water
      blur = addr blend.blur
    # -- Initialize Watercolor
    water.blending = lerp(0, 100).value
    water.dilution = lerp(0, 100).value
    water.persistence = lerp(0, 100).value
    water.watering = lerp(0, 100).value
    water.minimum = lerp(0, 100).value
    # -- Initialize Blur
    blur.size = lerp(0, 100).value

  # -- Constructor --
  new cxbrush():
    # Init Value Ranges
    result.initShape()
    result.initTexture()
    result.initBlending()
