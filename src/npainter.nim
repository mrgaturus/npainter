import gui/[window, widget, render, event, signal, timer]
import gui/widgets/[slider, label, color, radio, check, button]
# Import OpenGL
import libs/gl
# Import Maths
from math import floor, arctan2, pow, log2
import omath
# Import Brush Engine
import wip/[brush, texture, binary, canvas]
from wip/canvas/context import composed
import wip/canvas/matrix
import spmc

const
  bw = 1280#*4
  bh = 720#*4

type
  GUICanvasPanel = ref object of GUIWidget
  GUIShapePanel = ref object of GUICanvasPanel
    shape: NBrushShape
    # Blotmap Parameters
    blot_mess: Value
    blot_scale: Value
    blot_tone: Value
    blot_invert: bool
    # Bitmap Parameters
    bitmap_flow: Value
    bitmap_space: Value
    bitmap_angle: Value
    bitmap_aspect: Value
    bitmap_scale: Value
    # Bitmap Automatic
    auto_flow: bool
    auto_angle: bool
    # Scattering Parameters
    scatter_space: Value
    scatter_scale: Value
    scatter_angle: Value
    # Texture Configuration
    tex_amount: Value
    tex_scale: Value
    tex_scratch0: Value
    tex_scratch1: Value
    tex_invert: bool
    # Texture Images
    tex0, tex1, tex2: NTexture
  GUIBlendPanel = ref object of GUICanvasPanel
    # RGB Color
    color: RGBColor
    # Basic Attributes
    size, alpha: Value
    hard, sharp: Value
    # Pressure Minimun
    min_size, min_alpha: Value
    # Blending Mode
    blend: NBrushBlend
    # ----------------
    glass: bool
    ##################
    blending: Value
    dilution: Value
    persistence: Value
    ##################
    watering: Value
    coloring: bool
    ##################
    p_blending: bool
    p_dilution: bool
    p_watering: bool
    p_minimun: Value
    # ----------------
    blur: Value
  GUIBucketPanel = ref object of GUICanvasPanel
    check: NBucketCheck
    # Threshold Sliders
    threshold: Value
    gap: Value
    # Antialiasing Check
    antialiasing: bool
  CanvasMode = enum
    moNone, moPaint
    moMove, moRotate, moZoom
  GUICanvas = ref object of GUIWidget
    # Canvas Brush Panel
    panel: GUIBlendPanel
    shape: GUIShapePanel
    bucket: GUIBucketPanel
    # Canvas Engine
    view: NCanvasProof
    backup: NCanvasAffine
    bx, by: cfloat
    # Brush Engine
    path: NBrushStroke
    fill: NBucketProof
    # Busy Indicator
    mode: CanvasMode
    spacebar: bool
    busy, eraser: bool
    handle: uint
    # Thread Pool
    pool: NThreadPool
  GUICanvasState = object
    canvas: GUICanvas

# -------------------------
# GUI CANVAS PIXEL TRANSFER
# -------------------------

# Can Be SIMD, of course
#[
proc copy(self: GUICanvas, x, y, w, h: int) =
  var
    cursor_src = 
      (y * bw + x) shl 2
    cursor_dst: int
  # Convert to RGBA8
  for yi in 0..<h:
    for xi in 0..<w:
      self.dst_copy[cursor_dst] = 
        cast[uint8](self.dst[cursor_src] shr 8)
      self.dst_copy[cursor_dst + 1] = 
        cast[uint8](self.dst[cursor_src + 1] shr 8)
      self.dst_copy[cursor_dst + 2] = 
        cast[uint8](self.dst[cursor_src + 2] shr 8)
      self.dst_copy[cursor_dst + 3] =
        cast[uint8](self.dst[cursor_src + 3] shr 8)
      # Next Pixel
      cursor_src += 4; cursor_dst += 4
    # Next Row
    cursor_src += (bw - w) shl 2
    #cursor_dst += w shl 2
  # Copy To Texture
  glBindTexture(GL_TEXTURE_2D, self.tex)
  glTexSubImage2D(GL_TEXTURE_2D, 0, 
    cast[int32](x), cast[int32](y), cast[int32](w), cast[int32](h),
    GL_RGBA, GL_UNSIGNED_BYTE, addr self.dst_copy[0])
  glBindTexture(GL_TEXTURE_2D, 0)
]#

# -----------------------
# GUI CANVAS MANIPULATION
# -----------------------

proc prepare(self: GUICanvas) =
  let
    panel = self.panel
    banel = self.shape
    color = panel.color
    # Shortcut
    path = addr self.path
    basic = addr path.basic
    circle = addr path.mask.circle
    # Unpack Color to Fix15
    r = cint(color.r * 255.0)
    g = cint(color.g * 255.0)
    b = cint(color.b * 255.0)
  # Calculate Size
  basic.size = distance(panel.size)
  basic.p_size = distance(panel.min_size)
  # Calculate Alpha
  basic.alpha = distance(panel.alpha)
  basic.p_alpha = distance(panel.min_alpha)
  # Calculate Dynamics Amplification
  basic.amp_size = 1.0
  basic.amp_alpha = 1.0
  # Configure Shape Mode
  case banel.shape
  of bsCircle, bsBlotmap:
    # Calculate Circle Style
    circle.hard = distance(panel.hard)
    circle.sharp = distance(panel.sharp)
    # Configure Blotmap Style
    if banel.shape == bsBlotmap:
      let blot = addr path.mask.blot
      blot.fract = distance(banel.blot_mess)
      blot.scale = distance(banel.blot_scale)
      blot.tone = distance(banel.blot_tone)
      # Set Texture Inversion
      blot.invert = banel.blot_invert
      # Set Texture Buffer Pointer
      blot.texture = addr banel.tex0
  of bsBitmap:
      let bitmap = addr path.mask.bitmap
      # Configure Bitmap Affine
      bitmap.flow = distance(banel.bitmap_flow)
      bitmap.step = distance(banel.bitmap_space)
      bitmap.angle = distance(banel.bitmap_angle)
      bitmap.aspect = distance(banel.bitmap_aspect)
      bitmap.scale = distance(banel.bitmap_scale)
      # Configure Bitmap Scattering
      bitmap.s_space = distance(banel.scatter_space)
      bitmap.s_angle = distance(banel.scatter_angle)
      bitmap.s_scale = distance(banel.scatter_scale)
      # Configure Automatic Flow
      bitmap.auto_flow = banel.auto_flow
      # Configure Automatic Angle
      if banel.auto_angle:
        bitmap.auto_angle = 255
      else: bitmap.auto_angle = 0
      # Set Texture Buffer Pointer
      bitmap.texture = addr banel.tex1
  # Configure Texture
  block:
    let texture = addr path.texture
    texture.fract = distance(banel.tex_amount)
    texture.scale = distance(banel.tex_scale)
    texture.invert = banel.tex_invert
    # Texture Scratch
    texture.scratch = distance(banel.tex_scratch0)
    texture.p_scratch = distance(banel.tex_scratch1)
    # Temporal Enabled Check
    texture.texture = addr banel.tex2
    texture.enabled = texture.fract > 0.0
  # Configure Blending Mode
  case panel.blend
  of bnAverage, bnWater:
    let avg = addr path.data.avg
    avg.blending = distance(panel.blending)
    avg.dilution = distance(panel.dilution)
    avg.persistence = distance(panel.persistence)
    # Pressure Activation
    avg.p_blending = panel.p_blending
    avg.p_dilution = panel.p_dilution
    avg.p_minimun = distance(panel.p_minimun)
    # Watercolor Parameters
    if panel.blend == bnWater:
      avg.watering = distance(panel.watering)
      avg.p_watering = panel.p_watering
      avg.coloring = panel.coloring
  of bnMarker:
    let marker = addr path.data.marker
    marker.blending = distance(panel.blending)
    marker.persistence = distance(panel.persistence)
    # Pressure Activation
    marker.p_blending = panel.p_blending
  of bnBlur:
    let b = addr path.data.blur
    b.radius = distance(panel.blur)
  else: discard
  # Set Current Blendig Mode
  self.path.shape = banel.shape
  self.path.blend = panel.blend
  # Set Current Brush Color
  self.path.color(r, g, b, panel.glass)
  # Set Current Thread Pool
  self.path.pipe.pool = self.pool
  # Prepare Path Rendering
  self.path.prepare()

# -------------------
# GUI Paint Callbacks
# -------------------

proc cb_panel_bucket(global: ptr GUICanvasState, dummy: pointer) =
  global.canvas.shape.set(wHidden)
  global.canvas.bucket.clear(wHidden)
  pushSignal(global.canvas.target, msgDirty)

proc cb_panel_brush(global: ptr GUICanvasState, dummy: pointer) =
  global.canvas.shape.clear(wHidden)
  global.canvas.bucket.set(wHidden)
  pushSignal(global.canvas.target, msgDirty)

proc cb_bucket(global: ptr GUICanvasState, p: ptr tuple[x, y: cint]) =
  let 
    canvas = global.canvas
    fill = addr global.canvas.fill
  # Configure Bucket
  fill.tolerance = cint(canvas.bucket.threshold.distance() * 255)
  fill.gap = cint(canvas.bucket.gap.distance() * 100)
  fill.check = canvas.bucket.check
  fill.antialiasing = canvas.bucket.antialiasing
  fill.rgba = canvas.panel.color.rgb8
  # Dispatch Position
  if fill.check != bkSimilar:
    fill[].flood(p.x, p.y)
  else: fill[].similar(p.x, p.y)
  fill[].blend()
  # Update Render Region
  canvas.view.mark(0, 0, bw, bh)
  canvas.view.clean()
  canvas.busy = false

proc cb_dispatch(g: pointer, w: ptr GUITarget) =
  let self = cast[GUICanvas](w[])
  # Draw Point Line
  self.pool.start()
  dispatch(self.path)
  self.pool.stop()
  let aabb = addr self.path.aabb
  # Clamp to Canvas
  aabb.x1 = max(0, aabb.x1)
  aabb.y1 = max(0, aabb.y1)
  aabb.x2 = min(bw, aabb.x2)
  aabb.y2 = min(bh, aabb.y2)
  # Copy To Buffer
  self.view.mark(
    aabb.x1, aabb.y1, 
    aabb.x2 - aabb.x1,
    aabb.y2 - aabb.y1)
  self.view.clean()
  #self.copy(0, 0, 
  #  1280, 720)
  # Reset Dirty Region
  aabb.x1 = high(int32); aabb.x2 = 0
  aabb.y1 = high(int32); aabb.y2 = 0
  # Recover Status
  self.busy = false

proc cb_clear(g: pointer, w: ptr GUITarget) =
  let self = cast[GUICanvas](w[])
  # Clear View
  self.view.clear()
  # Recover Status
  self.busy = false

# ----------------------
# GUICanvas Widget Paint
# ----------------------

proc eventBrush(self: GUICanvas, state: ptr GUIState) =
  if state.kind == evCursorClick:
    self.prepare()
    # Prototype Clearing
    if state.key == RightButton:
      if not self.busy:
        var target = self.target
        pushCallback(cb_clear, target)
        # Avoid Repeat
        self.busy = true
    elif state.key == MiddleButton:
      self.eraser = not self.eraser
    # Store Who Clicked
    self.handle = state.key
  # Perform Brush Path, if is moving
  elif self.test(wGrab) and 
  state.kind == evCursorMove and 
  self.handle == LeftButton:
    point(self.path, state.px, state.py, state.pressure, 0.0)
    # Call Dispatch
    if not self.busy:
      # Push Dispatch Callback
      var target = self.target
      pushCallback(cb_dispatch, target)
      # Stop Repeating Callback
      self.busy = true

proc eventBucket(self: GUICanvas, state: ptr GUIState) =
  if state.kind == evCursorClick:
    if state.key == LeftButton:
      var p: tuple[x, y: cint] = (cint state.px, cint state.py)
      pushCallback(cb_bucket, p)
    elif state.key == RightButton:
      if not self.busy:
        var target = self.target
        pushCallback(cb_clear, target)
        # Avoid Repeat
        self.busy = true

proc eventPaint(self: GUICanvas, state: ptr GUIState) =
  # Dirty But Works for a Proof of Concept
  if self.shape.test(wVisible):
    eventBrush(self, state)
  elif self.bucket.test(wVisible):
    eventBucket(self, state)

# --------------------------
# GUICanvas Canvas Callbacks
# --------------------------
type NCanvasPacket = tuple[x, y: cfloat]

proc cb_canvasMove(global: ptr GUICanvasState, pos: ptr NCanvasPacket) =
  let 
    self = global.canvas
    affine = self.view.affine
    backup = addr self.backup
  # Calculate Movement
  let
    # Apply Inverse Matrix
    p0 = affine[].forward(floor self.bx, floor self.by)
    p1 = affine[].forward(floor pos.x, floor pos.y)
    dx = p1.x - p0.x
    dy = p1.y - p0.y
  # Apply Movement
  affine.x = backup.x - dx
  affine.y = backup.y - dy
  self.view.update()
  self.busy = false

proc cb_canvasRotate(global: ptr GUICanvasState, pos: ptr NCanvasPacket) =
  let 
    self = global.canvas
    affine = self.view.affine
    backup = addr self.backup
  # Calculate Rotation
  let
    cx = cfloat(self.rect.w shr 1)
    cy = cfloat(self.rect.h shr 1)
    dx0 = self.bx - cx
    dy0 = self.by - cy
    dx1 = pos.x - cx
    dy1 = pos.y - cy
    # Calculate Rotation
    rot1 = arctan2(dy1, dx1)
    rot0 = arctan2(dy0, dx0)
    d = rot1 - rot0
  # Apply Rotation
  affine.angle = backup.angle - d
  self.view.update()
  self.busy = false

proc cb_canvasZoom(global: ptr GUICanvasState, pos: ptr NCanvasPacket) =
  let
    self = global.canvas
    affine = self.view.affine
    backup = addr self.backup
  # We need Power Of Two
  let
    size = cfloat(self.rect.h)
    dist = self.by - pos.y
    scale = (dist / size) * 6
  # Log2 Scale
    l0 = log2(backup.zoom)
    zoom = pow(2, l0 + scale)
  affine.zoom = zoom
  self.view.update()
  self.busy = false

proc eventCanvas(self: GUICanvas, state: ptr GUIState) =
  if state.kind == evCursorClick and state.key == LeftButton:
    self.backup = self.view.affine[]
    self.bx = state.px
    self.by = state.py
    # Backup Affine and Points
  elif self.test(wGrab) and not self.busy:
    var target = (state.px, state.py)
    # Decide Which Mode
    case self.mode
    of moMove: pushCallback(cb_canvasMove, target)
    of moRotate: pushCallback(cb_canvasRotate, target)
    of moZoom: pushCallback(cb_canvasZoom, target)
    else: discard
    self.busy = true

# ------------------------
# GUICanvas Widget Methods
# ------------------------

method event(self: GUICanvas, state: ptr GUIState) =
  case state.kind
  # Test if Canvas Needs to be Moved
  of evKeyDown: self.spacebar = 
    self.spacebar or state.key == 32
  of evKeyUp: self.spacebar = 
    self.spacebar and state.key != 32
  # Perform Current Event
  of evCursorClick:
    if state.key == LeftButton:
      self.mode = if not self.spacebar: moPaint
      elif (state.mods and ShiftMod) == ShiftMod: moZoom
      elif (state.mods and CtrlMod) == CtrlMod: moRotate
      else: moMove
  of evCursorRelease: 
    if state.key == LeftButton:
      self.mode = moNone
  else: discard
  # Dispatch Canvas Mode
  case self.mode
  of moPaint: eventPaint(self, state)
  of moMove, moRotate, moZoom: 
    eventCanvas(self, state)
  of moNone: discard

method layout(self: GUICanvas) =
  let affine = self.view.affine
  affine.vw = self.rect.w
  affine.vh = self.rect.h
  self.view.update()

# ------------------
# GUI PANEL CREATION
# ------------------

method draw(self: GUICanvasPanel, ctx: ptr CTXRender) =
  ctx.color(uint32 0xfb3b3b3b)
  ctx.fill(rect self.rect)

proc newBrushPanel(): GUIBlendPanel =
  new result
  # Set Mouse Attribute
  result.flags = wMouse
  # Set Geometry To Floating
  result.geometry(0, 0, 250, 720)
  # Create Label: |Slider|
  var 
    label: GUILabel
    slider: GUISlider
    color: GUIColorBar
    check: GUIWidget
  # -- Color Square --
  color = newColorBar(addr result.color)
  color.geometry(5, 5, 240, 240)
  result.add(color)
  # -- Size Slider --
  interval(result.size, 0, 1000)
  label = newLabel("Size", hoLeft, veMiddle)
  label.geometry(5, 265, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.size)
  slider.geometry(90, 265, 150, slider.hint.h)
  result.add(slider)
  # Min Size Slider
  interval(result.min_size, 0, 100)
  label = newLabel("Min Size", hoLeft, veMiddle)
  label.geometry(5, 285, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.min_size)
  slider.geometry(90, 285, 100, slider.hint.h)
  result.add(slider)
  # -- Opacity Slider --
  interval(result.alpha, 0, 100)
  label = newLabel("Opacity", hoLeft, veMiddle)
  label.geometry(5, 310, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.alpha)
  slider.geometry(90, 310, 150, slider.hint.h)
  result.add(slider)
  # Min Opacity Slider
  interval(result.min_alpha, 0, 100)
  label = newLabel("Min Opacity", hoLeft, veMiddle)
  label.geometry(5, 330, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.min_alpha)
  slider.geometry(90, 330, 100, slider.hint.h)
  result.add(slider)
  # -- Hardness|Sharpness Slider --
  interval(result.hard, 0, 100)
  label = newLabel("Hardness", hoLeft, veMiddle)
  label.geometry(5, 360, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.hard)
  slider.geometry(90, 360, 150, slider.hint.h)
  result.add(slider)
  # Min Opacity Slider
  interval(result.sharp, 0, 100)
  label = newLabel("Sharpness", hoLeft, veMiddle)
  label.geometry(5, 380, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.sharp)
  slider.geometry(90, 380, 150, slider.hint.h)
  result.add(slider)
  # -- Default Values --
  val(result.size, 10)
  val(result.min_size, 20)
  val(result.alpha, 100)
  val(result.min_alpha, 100)
  val(result.hard, 100)
  val(result.sharp, 50)
  # Blending Modes
  check = newRadio("Pencil",
    bnPencil.byte, cast[ptr byte](addr result.blend))
  check.geometry(5, 420, 80, check.hint.h)
  result.add(check)
  check = newRadio("Pen",
    bnFlat.byte, cast[ptr byte](addr result.blend))
  check.geometry(85, 420, 80, check.hint.h)
  result.add(check)
  check = newRadio("Eraser",
    bnEraser.byte, cast[ptr byte](addr result.blend))
  check.geometry(175, 420, 80, check.hint.h)
  result.add(check)
  # -- Water Color Blendings
  check = newRadio("Brush",
    bnAverage.byte, cast[ptr byte](addr result.blend))
  check.geometry(5, 440, 80, check.hint.h)
  result.add(check)
  check = newRadio("Water",
    bnWater.byte, cast[ptr byte](addr result.blend))
  check.geometry(85, 440, 80, check.hint.h)
  result.add(check)
  check = newRadio("Marker",
    bnMarker.byte, cast[ptr byte](addr result.blend))
  check.geometry(175, 440, 80, check.hint.h)
  result.add(check)
  # Transparency Switch
  check = newCheckbox("Transparent", addr result.glass)
  check.geometry(90 + check.hint.h + 4, 480, 150, check.hint.h)
  result.add(check)
  # Blending Slider
  interval(result.blending, 0, 100)
  label = newLabel("Blending", hoLeft, veMiddle)
  label.geometry(5, 500, 80, label.hint.h)
  result.add(label)
  check = newCheckbox("", addr result.p_blending)
  check.geometry(90, 500, check.hint.h, check.hint.h)
  result.add(check)
  slider = newSlider(addr result.blending)
  slider.geometry(90 + check.hint.h + 4, 500, 150 - check.hint.h - 4, slider.hint.h)
  result.add(slider)
  # Dilution Slider
  interval(result.dilution, 0, 100)
  label = newLabel("Dilution", hoLeft, veMiddle)
  label.geometry(5, 520, 80, label.hint.h)
  result.add(label)
  check = newCheckbox("", addr result.p_dilution)
  check.geometry(90, 520, check.hint.h, check.hint.h)
  result.add(check)
  slider = newSlider(addr result.dilution)
  slider.geometry(90 + check.hint.h + 4, 520, 150 - check.hint.h - 4, slider.hint.h)
  result.add(slider)
  # Persistence Slider
  interval(result.persistence, 0, 100)
  label = newLabel("Persistence", hoLeft, veMiddle)
  label.geometry(5, 540, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.persistence)
  slider.geometry(90 + check.hint.h + 4, 540, 150 - check.hint.h - 4, slider.hint.h)
  result.add(slider)
  # -- Watering Slider
  interval(result.watering, 0, 100)
  label = newLabel("Watering", hoLeft, veMiddle)
  label.geometry(5, 560, 80, label.hint.h)
  result.add(label)
  check = newCheckbox("", addr result.p_watering)
  check.geometry(90, 560, check.hint.h, check.hint.h)
  result.add(check)
  slider = newSlider(addr result.watering)
  slider.geometry(90 + check.hint.h + 4, 560, 150 - check.hint.h - 4, slider.hint.h)
  result.add(slider)
  # Transparency Switch
  check = newCheckbox("Colouring", addr result.coloring)
  check.geometry(90 + check.hint.h + 4, 580, 150, check.hint.h)
  result.add(check)
  # -- Min Pressure Slider
  interval(result.p_minimun, 0, 100)
  label = newLabel("Min Pressure", hoLeft, veMiddle)
  label.geometry(5, 620, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.p_minimun)
  slider.geometry(90 + check.hint.h + 4, 620, 150 - check.hint.h - 4, slider.hint.h)
  result.add(slider)
  # -- Blur Smudge
  check = newRadio("Blur",
    bnBlur.byte, cast[ptr byte](addr result.blend))
  check.geometry(5, 660, 80, check.hint.h)
  result.add(check)
  check = newRadio("Smudge",
    bnSmudge.byte, cast[ptr byte](addr result.blend))
  check.geometry(90, 660, 80, check.hint.h)
  result.add(check)
  # Blur Size
  interval(result.blur, 0, 100)
  label = newLabel("Blur Size %", hoLeft, veMiddle)
  label.geometry(5, 680, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.blur)
  slider.geometry(90, 680, 150, slider.hint.h)
  result.add(slider)
  # -- Default Values --
  val(result.blending, 50)
  val(result.persistence, 40)
  val(result.watering, 30)
  val(result.blur, 20)
  result.p_blending = true
  result.p_watering = true

proc newShapePanel(): GUIShapePanel =
  new result
  # Set Mouse Attribute
  result.flags = wMouse
  # Set Geometry To Floating
  result.geometry(1280 - 250 - 5, 5, 250, 550)
  # Create Label: |Slider|
  var 
    label: GUILabel
    slider: GUISlider
    check: GUIWidget
  check = newRadio("Circle",
    bsCircle.byte, cast[ptr byte](addr result.shape))
  check.geometry(5, 5, 80, check.hint.h)
  result.add(check)
  check = newRadio("Blotmap",
    bsBlotmap.byte, cast[ptr byte](addr result.shape))
  check.geometry(85, 5, 80, check.hint.h)
  result.add(check)
  check = newRadio("Bitmap",
    bsBitmap.byte, cast[ptr byte](addr result.shape))
  check.geometry(175, 5, 80, check.hint.h)
  result.add(check)
  # Blotmap Sliders
  interval(result.blot_mess, 0, 100)
  label = newLabel("Mess", hoLeft, veMiddle)
  label.geometry(5, 45, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.blot_mess)
  slider.geometry(90, 45, 150, slider.hint.h)
  result.add(slider)
  # Blotmap Scale
  interval(result.blot_scale, 10, 500)
  label = newLabel("Scale", hoLeft, veMiddle)
  label.geometry(5, 65, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.blot_scale)
  slider.geometry(90, 65, 150, slider.hint.h)
  result.add(slider)
  # Blotmap Tone
  interval(result.blot_tone, 0, 100)
  label = newLabel("Tone", hoLeft, veMiddle)
  label.geometry(5, 85, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.blot_tone)
  slider.geometry(90, 85, 150, slider.hint.h)
  result.add(slider)
  check = newCheckbox("Invert Texture", addr result.blot_invert)
  check.geometry(90, 105, 150, check.hint.h)
  result.add(check)
  # Automatic Flow
  check = newCheckbox("Automatic Flow", addr result.auto_flow)
  check.geometry(90, 145, 150, check.hint.h)
  result.add(check)
  # Spacing Slider
  interval(result.bitmap_flow, 0, 100)
  label = newLabel("Flow", hoLeft, veMiddle)
  label.geometry(5, 165, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.bitmap_flow)
  slider.geometry(90, 165, 150, slider.hint.h)
  result.add(slider)
  # Spacing Slider
  interval(result.bitmap_space, 2.5, 50)
  label = newLabel("Spacing", hoLeft, veMiddle)
  label.geometry(5, 185, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.bitmap_space, 1)
  slider.geometry(90, 185, 150, slider.hint.h)
  result.add(slider)
  # -- Min Size Slider
  interval(result.scatter_space, 0, 100)
  label = newLabel("Mess Spacing", hoLeft, veMiddle)
  label.geometry(5, 205, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.scatter_space)
  slider.geometry(90, 205, 100, slider.hint.h)
  result.add(slider)
  # Automatic Flow
  check = newCheckbox("Automatic Angle", addr result.auto_angle)
  check.geometry(90, 245, 150, check.hint.h)
  result.add(check)
  # Angle Slider
  interval(result.bitmap_angle, 0, 360)
  label = newLabel("Angle", hoLeft, veMiddle)
  label.geometry(5, 265, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.bitmap_angle)
  slider.geometry(90, 265, 150, slider.hint.h)
  result.add(slider)
  # -- Min Size Slider
  interval(result.scatter_angle, 0, 100)
  label = newLabel("Mess Angle", hoLeft, veMiddle)
  label.geometry(5, 285, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.scatter_angle)
  slider.geometry(90, 285, 100, slider.hint.h)
  result.add(slider)
  # Aspect Ratio Slider
  interval(result.bitmap_aspect, -100, 100)
  label = newLabel("Aspect", hoLeft, veMiddle)
  label.geometry(5, 325, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.bitmap_aspect)
  slider.geometry(90, 325, 150, slider.hint.h)
  result.add(slider)
  # Scale Slider
  interval(result.bitmap_scale, 0, 100)
  label = newLabel("Scale", hoLeft, veMiddle)
  label.geometry(5, 345, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.bitmap_scale)
  slider.geometry(90, 345, 150, slider.hint.h)
  result.add(slider)
  # -- Min Size Slider
  interval(result.scatter_scale, 0, 100)
  label = newLabel("Mess Scale", hoLeft, veMiddle)
  label.geometry(5, 365, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.scatter_scale)
  slider.geometry(90, 365, 100, slider.hint.h)
  result.add(slider)
  # Texture Intensity
  interval(result.tex_amount, 0, 100)
  label = newLabel("Intensity", hoLeft, veMiddle)
  label.geometry(5, 425, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.tex_amount)
  slider.geometry(90, 425, 150, slider.hint.h)
  result.add(slider)
  # Texture Scale
  interval(result.tex_scale, 10, 500)
  label = newLabel("Scale", hoLeft, veMiddle)
  label.geometry(5, 445, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.tex_scale)
  slider.geometry(90, 445, 150, slider.hint.h)
  result.add(slider)
  check = newCheckbox("Invert Texture", addr result.tex_invert)
  check.geometry(90, 465, 150, check.hint.h)
  result.add(check)
  # Texture Scratch
  interval(result.tex_scratch0, 0, 100)
  label = newLabel("Scratch", hoLeft, veMiddle)
  label.geometry(5, 505, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.tex_scratch0)
  slider.geometry(90, 505, 150, slider.hint.h)
  result.add(slider)
  # -- Min Scratch
  interval(result.tex_scratch1, 0, 100)
  label = newLabel("Min Scratch", hoLeft, veMiddle)
  label.geometry(5, 525, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.tex_scratch1)
  slider.geometry(90, 525, 100, slider.hint.h)
  result.add(slider)
  # -- Default Values --
  val(result.blot_mess, 80)
  val(result.blot_tone, 50)
  val(result.blot_scale, 100)
  val(result.bitmap_flow, 100)
  val(result.bitmap_scale, 100)
  val(result.tex_scale, 50)
  result.auto_flow = true
  result.auto_angle = true
  # Load Demo Textures
  result.tex0 = newPNGTexture("tex0.png")
  result.tex1 = newPNGTexture("tex1.png")
  result.tex2 = newPNGTexture("tex2.png")

proc newBucketPanel(): GUIBucketPanel =
  new result
  # Set Mouse Attribute
  result.flags = wMouse
  result.check = bkMinimun
  result.antialiasing = true
  # Set Geometry To Floating
  result.geometry(1280 - 250 - 5, 5, 250, 180)
  # Create Label: |Slider|
  var 
    label: GUILabel
    slider: GUISlider
    check: GUIWidget
  block: # Bucket Threshold Check
    check = newRadio("Transparent Minimun",
      bkMinimun.byte, cast[ptr byte](addr result.check))
    check.geometry(5, 5, 180, check.hint.h)
    result.add(check)
    check = newRadio("Transparent Difference",
      bkAlpha.byte, cast[ptr byte](addr result.check))
    check.geometry(5, 25, 180, check.hint.h)
    result.add(check)
    check = newRadio("Color Difference",
      bkColor.byte, cast[ptr byte](addr result.check))
    check.geometry(5, 45, 180, check.hint.h)
    result.add(check)
    check = newRadio("Color Similar",
      bkSimilar.byte, cast[ptr byte](addr result.check))
    check.geometry(5, 65, 180, check.hint.h)
    result.add(check)
  block: # Bucket Thresholds
    interval(result.threshold, 0, 255)
    label = newLabel("Threshold", hoLeft, veMiddle)
    label.geometry(5, 105, 80, label.hint.h)
    result.add(label)
    slider = newSlider(addr result.threshold)
    slider.geometry(90, 105, 150, slider.hint.h)
    result.add(slider)
    interval(result.gap, 0, 100)
    label = newLabel("Gap Closing", hoLeft, veMiddle)
    label.geometry(5, 125, 80, label.hint.h)
    result.add(label)
    slider = newSlider(addr result.gap)
    slider.geometry(90, 125, 150, slider.hint.h)
    result.add(slider)
  block: # Bucket Antialiasing
    check = newCheckbox("Anti-Aliasing", addr result.antialiasing)
    check.geometry(90, 145, 180, check.hint.h)
    result.add(check)

# -------------------
# GUI Canvas Creation
# -------------------
from math import degToRad
proc newCanvas(): GUICanvas =
  new result
  # Create Canvas Brush Panel
  let panel = newBrushPanel()
  result.panel = panel
  result.add(panel)
  let shape = newShapePanel()
  result.shape = shape
  result.add(shape)
  let bucket = newBucketPanel()
  result.bucket = bucket
  bucket.set(wHidden)
  result.add(bucket)
  # Create Two Buttons
  block:
    let
      btn0 = newButton("Brush Demo", cast[GUICallback](cb_panel_brush))
      btn1 = newButton("Bucket Demo", cast[GUICallback](cb_panel_bucket))
    btn0.geometry(280, 5, 150, btn0.hint.h + 8)
    btn1.geometry(450, 5, 150, btn0.hint.h + 8)
    result.add btn0
    result.add btn1
  # Set Mouse Enabled
  result.flags = wMouse or wKeyboard
  # Create OpenGL Texture
  #[
  glGenTextures(1, addr result.tex)
  glBindTexture(GL_TEXTURE_2D, result.tex)
  glTexImage2D(GL_TEXTURE_2D, 0, cast[GLint](GL_RGBA8), 
    bw, bh, 0, GL_RGBA, GL_UNSIGNED_BYTE, addr result.dst_copy[0])
  # Set Mig/Mag Filter
  glTexParameteri(GL_TEXTURE_2D, 
    GL_TEXTURE_MIN_FILTER, cast[GLint](GL_NEAREST))
  glTexParameteri(GL_TEXTURE_2D, 
    GL_TEXTURE_MAG_FILTER, cast[GLint](GL_NEAREST))
  glBindTexture(GL_TEXTURE_2D, 0)
  ]#
  result.view = createCanvasProof(bw, bh)
  # Initialize View Transform
  let a = result.view.affine()
  a.cw = bw
  a.ch = bh
  a.x = 200.0
  a.y = 500.0
  a.zoom = 1.0
  a.angle = degToRad(35.0)
  a.vw = bw
  a.vh = bh
  result.view.update()
  # Bind Brush Engine to Canvas
  let
    ctx = addr result.view.ctx
    canvas = addr result.path.pipe.canvas
    composed = cast[ptr cshort](ctx[].composed 0)
    buffer0 = cast[ptr cshort](addr ctx.buffer0[0])
    buffer1 = cast[ptr cshort](addr ctx.buffer1[0])
  canvas.w = ctx.w
  canvas.h = ctx.h
  # Set Canvas Stride
  canvas.stride = canvas.w
  # Working Buffers
  canvas.dst = cast[ptr cshort](ctx[].composed 0)
  canvas.buffer0 = cast[ptr cshort](addr ctx.buffer0[0])
  canvas.buffer1 = cast[ptr cshort](addr ctx.buffer1[0])
  # Bind Bucket to Canvas
  result.path.clear()
  result.fill = configure(
    composed, 
    buffer0, 
    buffer1, 
    bw, bh
  )

# --------------------
# GUI CANVAS MAIN LOOP
# --------------------

when isMainModule:
  var # Create Basic Widgets
    c: GUICanvasState
    win = newGUIWindow(1280, 720, addr c)
    root = newCanvas()
    pool = newThreadPool(6)
  root.pool = pool
  c.canvas = root
  # Open Window
  if win.open(root):
    loop(16):
      win.handleEvents() # Input
      if win.handleSignals(): break
      win.handleTimers() # Timers
      # Render Main Program
      glClearColor(0.5, 0.5, 0.5, 1.0)
      glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
      # Render GUI
      c.canvas.view.render()
      win.render()
  # Close Window
  win.close()
  pool.destroy()
  echo "reached?"