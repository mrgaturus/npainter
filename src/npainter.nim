import gui/[window, widget, render, event, signal]
import gui/widgets/[slider, label, color]
import libs/gl
import math, omath

type
  BrushPoint = object # Vec2
    x, y, press: float32
  GUICanvas = ref object of GUIWidget
    buffer: array[1280*720*4, int16] # Fix15
    buffer_copy: array[1280*720*4, uint8]
    # -- GUI Panel
    panel: GUIBrushPanel
    # -- Brush Color
    r, g, b: int16
    # -- Basic Attributes
    size, alpha: float
    hard, sharp: float
    # Pressure Minimun
    min_size, min_alpha: float
    # -- Continuous Stroke
    step, prev_t: float 
    points: seq[BrushPoint]
    # -- OpenGL Test Texture
    tex: GLuint
    # -- Busy Indicator
    busy: bool
    handle: uint
  # Brush Configurator
  GUIBrushPanel = ref object of GUIWidget
    # RGB Color
    color: RGBColor
    # Basic Attributes
    size, alpha: Value
    hard, sharp: Value
    # Pressure Minimun
    min_size, min_alpha: Value

# ------------------------
# Simple Buffer Copy Procs
# ------------------------

# Can Be SIMD, of course
proc copy(self: GUICanvas, x, y, w, h: int) =
  var
    cursor_src = 
      (y * 1280 + x) shl 2
    cursor_dst: int
  # Convert to RGBA8
  for yi in 0..<h:
    for xi in 0..<w:
      self.buffer_copy[cursor_dst] = 
        cast[uint8](self.buffer[cursor_src] shr 7)
      self.buffer_copy[cursor_dst + 1] = 
        cast[uint8](self.buffer[cursor_src + 1] shr 7)
      self.buffer_copy[cursor_dst + 2] = 
        cast[uint8](self.buffer[cursor_src + 2] shr 7)
      self.buffer_copy[cursor_dst + 3] =
        cast[uint8](self.buffer[cursor_src + 3] shr 7)
      # Next Pixel
      cursor_src += 4; cursor_dst += 4
    # Next Row
    cursor_src += (1280 - w) shl 2
    #cursor_dst += w shl 2
  # Copy To Texture
  glBindTexture(GL_TEXTURE_2D, self.tex)
  glTexSubImage2D(GL_TEXTURE_2D, 0, 
    cast[int32](x), cast[int32](y), cast[int32](w), cast[int32](h),
    GL_RGBA, GL_UNSIGNED_BYTE, addr self.buffer_copy[0])
  glBindTexture(GL_TEXTURE_2D, 0)

# ----------------------------
# Brush Engine Prototype Procs
# ----------------------------

# -- Blending Proc / Can be SIMDfied
template div32767(a: int32): int32 =
  ( a + ( (a + 32769) shr 15 ) ) shr 15

proc blend_s(src, dst, alpha, ralpha: int32): int16 {.inline.} =
  let pre = div32767(cast[int32](src) * alpha)
  result = cast[int16](pre + div32767(dst * ralpha))

proc blend(src, dst, alpha: int32): int16 {.inline.} =
  result = cast[int16](src + div32767(dst * alpha))

# -- Alpha via numerical method
proc alpha(n, beta: float): float =
  (unsafeAddr beta)[] = 1.0 - beta
  # Numerical Method Loop
  var 
    i: int
    prev, error: float
    # Auxiliar Vars
    ac, acn: float
  # Error at 100%
  error = 1.0
  # Solve using Numerical Method
  while error > 0.10 and i < 5:
    prev = result
    # Auxiliar Vars
    ac = 1.0 - result
    acn = pow(ac, n)
    # Calculate Next Step
    result -= ac * (beta - acn) / (acn * n)
    # Calculate Current Error
    error = (result - prev) / result
    inc(i) # Next Iteration

# -----------------------
# Brush Shape Masks Procs
# -----------------------

proc circle(self: GUICanvas, x, y, d, a: float32) =
  let
    inverse = 1.0 / d
    # X Positions Interval | Dirty Clipping
    xi = floor(x - d * 0.5).int32.clamp(0, 1280)
    xd = ceil(x + d * 0.5).int32.clamp(0, 1280)
    # Y Positions Interval | Dirty Clipping
    yi = floor(y - d * 0.5).int32.clamp(0, 720)
    yd = ceil(y + d * 0.5).int32.clamp(0, 720)
    # Antialiasing Gamma Coeffient, inverse * |0.5 <-> 1.0|
    gamma = (6.0 - log2(d) * 0.5) * (inverse * self.sharp)
    # Smoothstep Coeffients
    edge_a = 0.5
    edge_div = # |0.25 <-> 0.5|
      1.0 / (self.hard - gamma - edge_a)
  var
    xn = xi # Position X
    yn = yi # Position Y
    dist, dx, dy: float32
    # Current Pixel
    i: int
  # -- It will be tiled
  while yn < yd:
    xn = xi
    while xn < xd:
      dx = x - float32(xn)
      dy = y - float32(yn)
      # 1 -- Calculate Circle Smooth SDF
      dist = fastSqrt(dx * dx + dy * dy) * inverse
      dist = (dist - edge_a) * edge_div
      dist = clamp(dist, 0.0, 1.0)
      dist = dist * dist * (3.0 - 2.0 * dist)
      # 2 -- Blend Source With Alpha
      let 
        alpha = (dist * a).int16
        r_alpha = 32767 - alpha
      # Get Current Pixel
      i = (yn * 1280 + xn) shl 2
      # Blend Red, Blue, Green - Can be SIMDfied
      self.buffer[i] = blend_s(self.r, self.buffer[i], alpha, r_alpha); inc(i)
      self.buffer[i] = blend_s(self.g, self.buffer[i], alpha, r_alpha); inc(i)
      self.buffer[i] = blend_s(self.b, self.buffer[i], alpha, r_alpha); inc(i)
      # Blend Alpha - Can be Premultiplied
      self.buffer[i] = blend(alpha, self.buffer[i], r_alpha)
      inc(xn) # Next Pixel
    inc(yn) # Next Row
  # -- Copy To Texture
  self.copy(xi, yi, xd - xi, yd - yi)

# ------------------------------------
# Brush Engine Fundamental Stroke Line
# ------------------------------------

# TODO: Rework GUI Values
proc prepare(self: GUICanvas) =
  # Reset Path
  self.prev_t = 0.0
  setLen(self.points, 0)
  # Shortcut Pointer
  let
    panel = self.panel
    color = panel.color
  # Unpack Color to Fix15
  self.r = int16(color.r * 32767.0)
  self.g = int16(color.g * 32767.0)
  self.b = int16(color.b * 32767.0)
  # Set Size and Min Size
  self.size = 2.5 + (1000.0 - 2.5) * distance(panel.size)
  self.min_size = distance(panel.min_size)
  # Set Alpha and Min Alpha
  self.alpha = distance(panel.alpha)
  self.min_alpha = distance(panel.min_alpha)
  # Set Hardness and Interval
  let hardness = distance(panel.hard)
  self.hard = 0.5 * hardness
  self.step = 0.1 + (0.025 - 0.1) * hardness
  # Set Circle Sharpess
  self.sharp = 1.0 + (0.5 - 1.0) * distance(panel.sharp)

proc stroke(self: GUICanvas, a, b: BrushPoint, t_start: float32): float32 =
  let
    dx = b.x - a.x
    dy = b.y - a.y
    # Line Length
    length = sqrt(dx * dx + dy * dy)
  # Avoid Zero Length
  if length < 0.0001:
    return t_start
  let # Calculate Steps
    t_step = self.step / length
    f_step = 0.5 / self.step
    # Pressure Start
    press_st = a.press
    press_dist = b.press - press_st
    # Min Size Interval
    size_st = self.min_size
    size_dist = 1.0 - size_st
    # Min Opacity Interval
    alpha_st = self.min_alpha
    alpha_dist = 1.0 - alpha_st
  var # Loop Variables
    t = t_start / length
    press, size, alpha: float32
  # Draw Each Stroke Point
  while t < 1.0:
    # Calculate Pressure at this point
    press = press_st + press_dist * t
    size = (size_st + size_dist * press) * self.size
    alpha = (alpha_st + alpha_dist * press) * self.alpha
    # Simulate Smallest
    if size < 2.5:
      alpha *= 
        size * 0.4
      size = 2.5
    alpha = pow(alpha, 1.75)
    alpha = # Calculate Current Alpha
      alpha(f_step, alpha) * 32767.0
    # Draw Circle
    self.circle(
      a.x + dx * t, 
      a.y + dy * t, 
      size, alpha)
    # Step to next point
    t += size * t_step
  # Return Remainder
  result = length * (t - 1.0)

# ----------------------------------
# GUI Brush Engine Interactive Procs
# ----------------------------------

proc cb_brush_dispatch(g: pointer, w: ptr GUITarget) =
  let 
    self = cast[GUICanvas](w[])
    count = len(self.points)
  # Draw Point Line
  if count > 1:
    var a, b: BrushPoint
    for i in 1..<len(self.points):
      a = self.points[i - 1]
      b = self.points[i]
      # Draw Brush Line
      self.prev_t = stroke(
        self, a, b, self.prev_t)
    # Set Last Point to First
    self.points[0] = self.points[^1]
    setLen(self.points, 1)
  # Stop Begin Busy
  self.busy = false

proc cb_clear(g: pointer, w: ptr GUITarget) =
  let self = cast[GUICanvas](w[])
  # Clear Both Canvas Buffers
  zeroMem(addr self.buffer[0], 
    sizeof(self.buffer))
  zeroMem(addr self.buffer_copy[0], 
    sizeof(self.buffer_copy))
  # Copy Cleared Buffer
  glBindTexture(GL_TEXTURE_2D, self.tex)
  glTexSubImage2D(GL_TEXTURE_2D, 0, 
    0, 0, 1280, 720, GL_RGBA, GL_UNSIGNED_BYTE, 
    addr self.buffer_copy[0])
  glBindTexture(GL_TEXTURE_2D, 0)
  # Recover Status
  self.busy = false

method event(self: GUICanvas, state: ptr GUIState) =
  # If clicked, reset points
  if state.kind == evCursorClick:
    # Prepare Attributes
    self.prepare()
    # Prototype Clearing
    if state.key == RightButton:
      if not self.busy:
        var target = self.target
        pushCallback(cb_clear, target)
        # Avoid Repeat
        self.busy = true
    # Store Who Clicked
    self.handle = state.key
  # Perform Brush Path, if is moving
  elif self.test(wGrab) and 
  state.kind == evCursorMove and 
  self.handle == LeftButton:
    var point: BrushPoint
    # Define New Point
    point.x = state.px
    point.y = state.py
    point.press = # Avoid 0.0 Steps
      max(state.pressure, 0.0001)
    # Add New Point
    self.points.add(point)
    # Call Dispatch
    if not self.busy:
      # Push Dispatch Callback
      var target = self.target
      pushCallback(cb_brush_dispatch, target)
      # Stop Repeating Callback
      self.busy = true

method draw(self: GUICanvas, ctx: ptr CTXRender) =
  ctx.color(uint32 0xFFFFFFFF)
  #ctx.color(uint32 0xFFFF2f2f)
  var r = rect(0, 0, 1280, 720)
  ctx.fill(r)
  ctx.color(uint32 0xFFFFFFFF)
  ctx.texture(r, self.tex)

# -----------------------------
# GUI Brush Engine Configurator
# -----------------------------

method draw(self: GUIBrushPanel, ctx: ptr CTXRender) =
  ctx.color(uint32 0xff3b3b3b)
  ctx.fill(rect self.rect)

proc newBrushPanel(): GUIBrushPanel =
  new result
  # Set Mouse Attribute
  result.flags = wMouse
  # Set Geometry To Floating
  result.geometry(20, 20, 250, 450)
  # Create Label: |Slider|
  var 
    label: GUILabel
    slider: GUISlider
    color: GUIColorBar
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

proc newCanvas(): GUICanvas =
  new result
  # Add New Brush Panel
  var panel = newBrushPanel()
  result.panel = panel
  result.add(panel)

# -------------
# Main GUI Loop
# -------------

when isMainModule:
  var # Create Basic Widgets
    win = newGUIWindow(1280, 720, nil)
    root = newCanvas()
  # -- Generate Canvas Texture
  glGenTextures(1, addr root.tex)
  glBindTexture(GL_TEXTURE_2D, root.tex)
  glTexImage2D(GL_TEXTURE_2D, 0, cast[GLint](GL_RGBA8), 
    1280, 720, 0, GL_RGBA, GL_UNSIGNED_BYTE, addr root.buffer_copy[0])
  # Set Mig/Mag Filter
  glTexParameteri(GL_TEXTURE_2D, 
    GL_TEXTURE_MIN_FILTER, cast[GLint](GL_NEAREST))
  glTexParameteri(GL_TEXTURE_2D, 
    GL_TEXTURE_MAG_FILTER, cast[GLint](GL_NEAREST))
  glBindTexture(GL_TEXTURE_2D, 0)
  # -- Put The Circle and Copy
  root.flags = wMouse
  # -- Open Window
  if win.open(root):
    while true:
      win.handleEvents() # Input
      if win.handleSignals(): break
      win.handleTimers() # Timers
      # Render Main Program
      glClearColor(0.5, 0.5, 0.5, 1.0)
      glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
      # Render GUI
      win.render()
  # -- Close Window
  win.close()
