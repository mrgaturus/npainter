import nogui/ux/prelude
import nogui/builder
# Import Value Formatting
import nogui/format
# Import Widgets
import nogui/pack
import nogui/ux/widgets/[check, label, slider]
import nogui/ux/layouts/[form, level, misc]
import nogui/ux/values/[linear, dual]
# Import Docks and Brushes
import nogui/ux/containers/[dock, scroll]
import ../../state/brush
# Import Brush Section
import section

# ----------------------
# Brush Field Formatting
# ----------------------

proc fmtScale(s: ShallowString, v: LinearDual) =
  let val = v.toFloat * 100.0
  if val >= 100.0:
    s.format("%.0f%%", val)
  else: s.format("%.1f%%", val)

proc fmtAspect(s: ShallowString, v: LinearDual) =
  var val = int32(v.toFloat * 200.0)
  if val == 100:
    s.format("1:1")
  elif val > 100:
    val = 100 - (val - 100)
    s.format("W:%d", val)
  else: s.format("%d:H", val)

const fmtAmplify = fmf2"%.2f"

# ------------------
# Brush Field Helper
# ------------------

proc field(name: string, check: & bool, w: GUIWidget): GUIWidget =
  let ck =
    if not isNil(check): check
    else: cast[& bool](w)
  # Create Middle Checkbox
  let c = checkbox("", ck)
  if isNil(check):
    c.flags = {wHidden}
  # Level Widget
  let l = level().child:
    label(name, hoLeft, veMiddle)
    tail(): c
  # Return Widget
  field(l): w

proc half(value: & Linear): UXAdjustLayout =
  result = adjust slider(value)
  # Adjust Metrics
  result.scaleW = 0.75

proc separator(): UXLabel =
  label("", hoLeft, veMiddle)

# ------------------------
# Brush Configuration Dock
# ------------------------

icons "dock/brush", 16:
  dockBrush := "brush.svg"
  # Shape Brush Section
  shapeCircle := "shape_circle.svg"
  shapeBlotmap := "shape_blotmap.svg"
  shapeBitmap := "shape_bitmap.svg"
  # Texture Brush Section
  texture0 := "texture0.svg"
  texture1 := "texture1.svg"
  # Blending Simple Section
  blendPen := "blend_pen.svg"
  blendPencil := "blend_pencil.svg"
  blendEraser := "blend_eraser.svg"
  # Blending Averaging
  blendBrush := "blend_brush.svg"
  blendWater := "blend_water.svg"
  blendMarker := "blend_marker.svg"
  # Blending Smearing
  blendBlur := "blend_blur.svg"
  blendSmudge := "blend_smudge.svg"

controller CXBrushDock:
  attributes:
    brush: CXBrush
    # Brush Sections
    shapeSec: CXBrushSection
    textureSec: CXBrushSection
    blendSec: CXBrushSection
    extraSec: CXBrushSection
    # Usable Dock
    {.public.}:
      dock: UXDockContent

  callback cbChangeProof:
    privateAccess(CXBrushSection)
    let brush {.cursor.} = self.brush
    brush.shape.kind = CKBrushShape(self.shapeSec.index)
    brush.blending.kind = CKBrushBlending(self.blendSec.index)
    brush.texture.enabled.peek[] = self.textureSec.index > 0

  proc createShapeSec =
    let m = # Create Combomodel
      menu("brush#shape").child:
        comboitem("Circle", iconShapeCircle, 0)
        comboitem("Blotmap", iconShapeBlotmap, 1)
        comboitem("Bitmap", iconShapeBitmap, 2)
    # Create Brush Section
    let 
      sec = cxbrushsection(m)
      shape = addr self.brush.shape
      circle = addr shape.circle
      blotmap = addr shape.blotmap
      bitmap = addr shape.bitmap
    # Register Circle Section
    sec.register:
      form().child:
        field("Hardness"): slider(circle.hardness)
        field("Sharpness"): slider(circle.sharpness)
    # Register Blotmap Section
    sec.register:
      form().child:
        field("Hardness"): slider(blotmap.hardness)
        field("Sharpness"): slider(blotmap.sharpness)
        separator() # Blotmap Texture
        field("Mess"): slider(blotmap.mess)
        field("Scale"): dual0float(blotmap.scale, fmtScale)
        field("Tone"): slider(blotmap.tone)
        field(): checkbox("Invert Texture", blotmap.invert)
    # Register Bitmap Section
    sec.register:
      form().child:
        field(): checkbox("Auto Flow", bitmap.flowAuto)
        field("Flow"): slider(bitmap.flow)
        field("Spacing"): slider(bitmap.spacing)
        field("Mess Spacing"): half(bitmap.spacingMess)
        separator() # Angle Control
        field(): checkbox("Auto Angle", bitmap.angleAuto)
        field("Angle"): slider(bitmap.angle)
        field("Mess Angle"): half(bitmap.angleMess)
        separator() # Scale Control
        field("Aspect"): dual0float(bitmap.aspect, fmtAspect)
        field("Scale"): slider(bitmap.scale)
        field("Mess Scale"): half(bitmap.scaleMess)
    # Store Shape Section
    self.shapeSec = sec
    sec.onchange = self.cbChangeProof

  proc createTextureSec =
    let m = # Create Combomodel
      menu("brush#texture").child:
        comboitem("No Texture", iconTexture0, 0)
        comboitem("Texture", iconTexture1, 1)
    # Create Texture Section
    let 
      sec = cxbrushsection(m)
      tex = addr self.brush.texture
    # Create Texture Section
    sec.registerEmpty()
    sec.register:
      form().child:
        field("Intensity"): slider(tex.intensity)
        field("Scale"): dual0float(tex.scale, fmtScale)
        field(): checkbox("Invert Texture", tex.invert)
        separator() # Scale Control
        field("Scratch"): slider(tex.scratch)
        field("Min Scratch"): half(tex.minScratch)
    # Store Texture Section
    self.textureSec = sec
    sec.onchange = self.cbChangeProof

  proc createBlendSec =
    let m = # Create Combomodel
      menu("brush#blend").child:
        comboitem("Pen", iconBlendPen, 0)
        comboitem("Pencil", iconBlendPencil, 1)
        comboitem("Eraser", iconBlendEraser, 2)
        menuseparator("Averaging")
        comboitem("Brush", iconBlendBrush, 3)
        comboitem("Water", iconBlendWater, 4)
        comboitem("Marker", iconBlendMarker, 5)
        menuseparator("Smearing")
        comboitem("Blur", iconBlendBlur, 6)
        comboitem("Smudge", iconBlendSmudge, 7)
    # Create Blend Section
    let
      sec = cxbrushsection(m)
      blend = addr self.brush.blending
      water = addr blend.water
      blur = addr blend.blur
    # Create Simple Blendings
    sec.registerEmpty()
    sec.registerEmpty()
    sec.registerEmpty()
    # Create Brush Blending
    sec.register:
      form().child:
        field("Blending", water.pBlending): slider(water.blending)
        field("Dilution", water.pDilution): slider(water.dilution)
        field("Persistence", nil): slider(water.persistence)
        separator() # Min Pressure
        field("Min Pressure"): slider(water.minimum)
    # Create Water Blending
    sec.register:
      form().child:
        field("Blending", water.pBlending): slider(water.blending)
        field("Dilution", water.pDilution): slider(water.dilution)
        field("Persistence", nil): slider(water.persistence)
        field("Watering", water.pWatering): slider(water.watering)
        field(): checkbox("Colouring", water.colouring)
        separator() # Min Pressure
        field("Min Pressure"): slider(water.minimum)
    # Create Marker Blending
    sec.register:
      form().child:
        field("Blending", water.pBlending): slider(water.blending)
        field("Persistence", nil): slider(water.persistence)
        separator() # Min Pressure
        field("Min Pressure"): slider(water.minimum)
    # Create Smearing Blendings
    sec.register:
      form().child:
        field("Size"): slider(blur.size)
    sec.registerEmpty()
    # Store Texture Section
    self.blendSec = sec
    sec.onchange = self.cbChangeProof

  proc createExtraSec =
    # Load Basics
    let
      brush {.cursor.} = self.brush
      basic = addr brush.shape.basic
    # Create Extra Section
    let section =
      form().child:
        field("Stabilizer"): slider(basic.stabilizer)
        separator() # Pressure Curves
        label("Pressure Curves", hoLeft, veMiddle)
        field("Size"): dual0float(basic.sizeAmp, fmtAmplify)
        field("Opacity"): dual0float(basic.opacityAmp, fmtAmplify)
    # Store Additional Settings Section
    self.extraSec = cxbrushsection("Additional Settings", section)

  proc createWidget: GUIWidget =
    let
      brush {.cursor.} = self.brush
      basic = addr brush.shape.basic
      # Brush Sections
      shape = self.shapeSec.section
      texture = self.textureSec.section
      blending = self.blendSec.section
      extra = self.extraSec.section
    # Create Sliders
    margin(4): form().child:
      # Basic Sliders
      margin(4): form().child:
        field("Size"): slider(basic.size)
        field("Min Size"): half(basic.sizeMin)
        field("Opacity"): slider(basic.opacity)
        field("Min Opacity"): half(basic.opacityMin)
      # Folded Customizers
      shape
      texture
      blending
      extra

  proc createDock =
    let
      w = scrollview self.createWidget()
      dock = dockcontent("Brush Tool", iconDockBrush, w)
    # Register Top Section
    self.shapeSec.top = w
    self.textureSec.top = w
    self.blendSec.top = w
    self.extraSec.top = w
    # Define Dock Attribute
    self.dock = dock

  new cxbrushdock(brush: CXBrush):
    result.brush = brush
    result.createShapeSec()
    result.createTextureSec()
    result.createBlendSec()
    result.createExtraSec()
    result.createDock()
    # Proof of Concept Pencil Select
    result.blendSec.selectProof(1)
