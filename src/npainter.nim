import gui/[window, widget, render, event, signal, timer]
import gui/widgets/[slider, label, color, check, radio]
# Import OpenGL
import libs/gl
# Import Maths
import omath
# Import Brush Engine
import wip/brush
import spmc

const
  bw = 1280
  bh = 720

type
  GUICanvasPanel = ref object of GUIWidget
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
    blending: Value
    dilution: Value
    persistence: Value
    keep: bool
  GUICanvas = ref object of GUIWidget
    # Canvas Brush Panel
    panel: GUICanvasPanel
    # Mask & Color Buffer
    buffer0: array[bw*bh, int16]
    buffer1: array[bw*bh*4, int16]
    # Destination Color Buffer
    dst: array[bw*bh*4, int16]
    dst_copy: array[bw*bh*4, uint8]
    # OpenGL Texture
    tex: GLuint
    # Brush Engine
    path: NBrushStroke
    # Busy Indicator
    busy, eraser: bool
    handle: uint

# -------------------------
# GUI CANVAS PIXEL TRANSFER
# -------------------------

# Can Be SIMD, of course
proc copy(self: GUICanvas, x, y, w, h: int) =
  var
    cursor_src = 
      (y * bw + x) shl 2
    cursor_dst: int
  # Convert to RGBA8
  for yi in 0..<h:
    for xi in 0..<w:
      self.dst_copy[cursor_dst] = 
        cast[uint8](self.dst[cursor_src] shr 7)
      self.dst_copy[cursor_dst + 1] = 
        cast[uint8](self.dst[cursor_src + 1] shr 7)
      self.dst_copy[cursor_dst + 2] = 
        cast[uint8](self.dst[cursor_src + 2] shr 7)
      self.dst_copy[cursor_dst + 3] =
        cast[uint8](self.dst[cursor_src + 3] shr 7)
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

# -----------------------
# GUI CANVAS MANIPULATION
# -----------------------

proc prepare(self: GUICanvas) =
  let
    panel = self.panel
    color = panel.color
    # Shortcut
    path = addr self.path
    basic = addr path.basic
    circle = addr path.mask.circle
    # Unpack Color to Fix15
    r = int16(color.r * 255.0)
    g = int16(color.g * 255.0)
    b = int16(color.b * 255.0)
  # Set Pipeline Color
  color(path.pipe, r, g, b)
  # Calculate Size
  basic.size = distance(panel.size)
  basic.p_size = distance(panel.min_size)
  # Calculate Alpha
  basic.alpha = distance(panel.alpha)
  basic.p_alpha = distance(panel.min_alpha)
  # Calculate Dynamics Amplification
  basic.amp_size = 2.5
  basic.amp_alpha = 1.0
  # Calculate Circle Style
  circle.hard = distance(panel.hard)
  circle.sharp = distance(panel.sharp)
  # Set Shape As Circle
  self.path.shape = bsCircle
  # Configure Blending Mode
  case panel.blend
  of bnAverage, bnWater:
    let avg = addr path.data.avg
    avg.blending = 
      cshort(distance(panel.blending) * 32767.0)
    avg.dilution = 
      cshort(distance(panel.dilution) * 32767.0)
    avg.persistence = 
      cshort(distance(panel.persistence) * 32767.0)
    avg.keep_alpha = panel.keep
  of bnMarker:
    let marker = addr self.path.data.marker
    marker.blending = 
      cshort(distance(panel.blending) * 32767.0)
    marker.persistence = 
      cshort(distance(panel.persistence) * 32767.0)
  else: discard
  # Set Current Blendig Mode
  self.path.blend = panel.blend
  # Prepare Path Rendering
  self.path.prepare()

proc cb_dispatch(g: pointer, w: ptr GUITarget) =
  let self = cast[GUICanvas](w[])
  # Draw Point Line
  dispatch(self.path)
  let aabb = addr self.path.aabb
  # Clamp to Canvas
  aabb.x1 = max(0, aabb.x1)
  aabb.y1 = max(0, aabb.y1)
  aabb.x2 = min(bw, aabb.x2)
  aabb.y2 = min(bh, aabb.y2)
  # Copy To Buffer
  self.copy(aabb.x1, aabb.y1, 
    aabb.x2 - aabb.x1,
    aabb.y2 - aabb.y1)
  #self.copy(0, 0, 
  #  1280, 720)
  # Reset Dirty Region
  aabb.x1 = high(int32); aabb.x2 = 0
  aabb.y1 = high(int32); aabb.y2 = 0
  # Recover Status
  self.busy = false

proc cb_clear(g: pointer, w: ptr GUITarget) =
  let self = cast[GUICanvas](w[])
  # Clear Both Canvas Buffers
  zeroMem(addr self.dst[0], 
    sizeof(self.dst))
  zeroMem(addr self.buffer1[0], 
    sizeof(self.dst))
  zeroMem(addr self.dst_copy[0], 
    sizeof(self.dst_copy))
  # Copy Cleared Buffer
  glBindTexture(GL_TEXTURE_2D, self.tex)
  glTexSubImage2D(GL_TEXTURE_2D, 0, 
    0, 0, bw, bh, GL_RGBA, GL_UNSIGNED_BYTE, 
    addr self.dst_copy[0])
  glBindTexture(GL_TEXTURE_2D, 0)
  # Recover Status
  self.busy = false

method event(self: GUICanvas, state: ptr GUIState) =
  #state.px *= 4.0
  #state.py *= 4.0
  # If clicked, reset points
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
    point(self.path, state.px, state.py, state.pressure)
    # Call Dispatch
    if not self.busy:
      # Push Dispatch Callback
      var target = self.target
      pushCallback(cb_dispatch, target)
      # Stop Repeating Callback
      self.busy = true

method draw(self: GUICanvas, ctx: ptr CTXRender) =
  ctx.color(uint32 0xFFFFFFFF)
  #ctx.color(uint32 0xFFFF2f2f)
  var r: CTXRect
  r = rect(0, 0, 1280, 720)
  ctx.fill(r)
  ctx.color(uint32 0xFF000000)
  r = rect(640, 0, 640, 720)
  ctx.fill(r)
  r = rect(0, 0, 1280, 720)
  ctx.color(uint32 0xFFFFFFFF)
  ctx.texture(r, self.tex)

# ------------------
# GUI PANEL CREATION
# ------------------

method draw(self: GUICanvasPanel, ctx: ptr CTXRender) =
  ctx.color(uint32 0xfb3b3b3b)
  ctx.fill(rect self.rect)

proc newBrushPanel(): GUICanvasPanel =
  new result
  # Set Mouse Attribute
  result.flags = wMouse
  # Set Geometry To Floating
  result.geometry(20, 20, 250, 580)
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
  # Water Color Blendings
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
  # Blending Slider
  interval(result.blending, 0, 100)
  label = newLabel("Blending", hoLeft, veMiddle)
  label.geometry(5, 480, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.blending)
  slider.geometry(90, 480, 150, slider.hint.h)
  result.add(slider)
  # Dilution Slider
  interval(result.dilution, 0, 100)
  label = newLabel("Dilution", hoLeft, veMiddle)
  label.geometry(5, 500, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.dilution)
  slider.geometry(90, 500, 150, slider.hint.h)
  result.add(slider)
  # Persistence Slider
  interval(result.persistence, 0, 100)
  label = newLabel("Persistence", hoLeft, veMiddle)
  label.geometry(5, 520, 80, label.hint.h)
  result.add(label)
  slider = newSlider(addr result.persistence)
  slider.geometry(90, 520, 150, slider.hint.h)
  result.add(slider)
  # Keep Opacity Switch
  check = newCheckbox("Keep Opacity", addr result.keep)
  check.geometry(90, 540, 150, check.hint.h)
  result.add(check)

proc newCanvas(): GUICanvas =
  new result
  # Create Canvas Brush Panel
  let panel = newBrushPanel()
  result.panel = panel
  result.add(panel)
  # Set Mouse Enabled
  result.flags = wMouse
  # Create OpenGL Texture
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
  # Bind Brush Engine to Canvas
  let canvas = 
    addr result.path.pipe.canvas
  canvas.w = bw
  canvas.h = bh
  # Set Canvas Stride
  canvas.stride = canvas.w
  # Working Buffers
  canvas.dst = addr result.dst[0]
  canvas.buffer0 = addr result.buffer0[0]
  canvas.buffer1 = addr result.buffer1[0]

# --------------------
# GUI CANVAS MAIN LOOP
# --------------------

when isMainModule:
  var # Create Basic Widgets
    win = newGUIWindow(1280, 720, nil)
    root = newCanvas()
    pool = newThreadPool(6)
  root.path.pipe.pool = pool
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
      win.render()
  # Close Window
  win.close()
  pool.destroy()
  echo "reached?"