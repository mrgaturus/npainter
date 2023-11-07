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
    sizeAmp*: @ Lerp2
    # Opacity Values
    opacity*: @ Lerp
    opacityMin*: @ Lerp
    opacityAmp*: @ Lerp2
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
    scale*: @ Lerp2
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
    # -- Initialize Lerps
    let
      lerpBasic = lerp(0, 100)
      lerpScale = lerp2(0.1, 1.0, 5)
      lerpAspect = lerp2(0.0, 1.0)
      lerpSpacing = lerp(2.5, 50)
      lerpAngle = lerp(0, 360)
      lerpAmp = lerp2(0.25, 1.0, 4)
    # -- Initialize Basics
    basic.size = lerpBasic.value
    basic.sizeMin = lerpBasic.value
    basic.sizeAmp = lerpAmp.value
    basic.opacity = lerpBasic.value
    basic.opacityMin = lerpBasic.value
    basic.opacityAmp = lerpAmp.value
    # -- Initialize Circle
    circle.hardness = lerpBasic.value
    circle.sharpness = lerpBasic.value
    # -- Initialize Blotmap
    blotmap.hardness = lerpBasic.value
    blotmap.sharpness = lerpBasic.value
    blotmap.mess = lerpBasic.value
    blotmap.scale = lerpScale.value
    blotmap.tone = lerpBasic.value
    # -- Initialize Bitmap
    bitmap.flow = lerpBasic.value
    bitmap.spacing = lerpSpacing.value
    bitmap.spacingMess = lerpBasic.value
    bitmap.angle = lerpAngle.value
    bitmap.angleMess = lerpBasic.value
    bitmap.aspect = lerpAspect.value
    bitmap.scale = lerpScale.value
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
