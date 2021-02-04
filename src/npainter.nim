import gui/[window, widget, render, event, signal]
import libs/gl
import math
from omath import fastSqrt

type
  BrushPoint = object # Vec2
    x, y, press: float32
  GUICanvas = ref object of GUIWidget
    buffer: array[1280*720*4, int16] # Fix15
    buffer_copy: array[1280*720*4, uint8]
    # -- Brush Basic Attributes
    size, hard, rough: float
    # -- Continuous Stroke
    prev_t: float 
    # -- Stroke Points
    points: seq[BrushPoint]
    # -- OpenGL Test Texture
    tex: GLuint
    # -- Busy Indicator
    busy: bool
    handle: uint

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
proc blend(src, dst, alpha: int32): int16 {.inline.} =
  result = cast[int16](src + dst * alpha div 32765)

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

# -- Standard Circle
proc circle(self: GUICanvas, x, y, d: float32) =
  let
    inverse = 1.0 / d
    # X Positions Interval | Dirty Clipping
    xi = floor(x - d * 0.5).int32.clamp(0, 1280)
    xd = ceil(x + d * 0.5).int32.clamp(0, 1280)
    # Y Positions Interval | Dirty Clipping
    yi = floor(y - d * 0.5).int32.clamp(0, 720)
    yd = ceil(y + d * 0.5).int32.clamp(0, 720)
    # Antialiasing Gamma Coeffient, inverse * |0.5 <-> 1.0|
    gamma = (6.0 - log2(d) * 0.5) * (inverse * 0.5)
    # Smoothstep Coeffients
    edge_a = 0.5
    edge_div = 
      1.0 / (0.5 - gamma - edge_a)
    alpha = alpha(0.5 / 0.025, 1.0) * 32765.0
  var
    xn = xi # Position X
    yn = yi # Position Y
    dist, dx, dy: float32
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
        s_alpha = (dist * alpha).int16
        d_alpha = 32765 - self.buffer[(yn * 1280 + xn) * 4 + 3]
      # Blend Color - Can be SIMDfied
      self.buffer[(yn * 1280 + xn) * 4] = 
        blend(self.buffer[(yn * 1280 + xn) * 4], 0, s_alpha)
      self.buffer[(yn * 1280 + xn) * 4 + 1] = 
        blend(self.buffer[(yn * 1280 + xn) * 4 + 1], 0, s_alpha)
      self.buffer[(yn * 1280 + xn) * 4 + 2] = 
        blend(self.buffer[(yn * 1280 + xn) * 4 + 2], 0, s_alpha)
      self.buffer[(yn * 1280 + xn) * 4 + 3] = 
        blend(self.buffer[(yn * 1280 + xn) * 4 + 3], s_alpha, d_alpha)
      inc(xn) # Next Pixel
    inc(yn) # Next Row
  # -- Copy To Texture
  self.copy(xi, yi, xd - xi, yd - yi)

# -----------------------------
# GUICanvas Interactive Methods
# -----------------------------

proc brush_line(self: GUICanvas, a, b: BrushPoint, t_start: float32): float32 =
  let
    dx = b.x - a.x
    dy = b.y - a.y
    # Line Length
    length = sqrt(dx * dx + dy * dy)
  # Avoid Zero Length
  if length < 0.0001:
    return t_start
  let # Calculate Steps
    t_step = 0.025 / length
    # Pressure Start
    press_st = a.press
    # Pressure Distance
    press_dist = b.press - press_st
  var # Loop Variables
    t = t_start / length
    press, size: float32
  # Draw Each Stroke Point
  while t < 1.0:
    # Calculate Pressure at this point
    press = press_st + press_dist * t
    size = self.size * press
    # Draw Circle
    self.circle(
      a.x + dx * t, 
      a.y + dy * t, 
      size)
    # Step to next point
    t += size * t_step
  # Return Remainder
  result = length * (t - 1.0)

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
      self.prev_t = brush_line(
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
  state.pressure = 1.0
  # If clicked, reset points
  if state.kind == evCursorClick:
    # Reset Path
    self.prev_t = 0.0
    setLen(self.points, 0)
    # Prototype Clearing
    if state.key == RightButton:
      if not self.busy:
        var target = self.target
        pushCallback(cb_clear, target)
        # Avoid Repeat
        self.busy = true
    # Store Who Clicked
    self.handle = state.key
  # -- Perform Brush Path, if is moving
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

# -------------
# Main GUI Loop
# -------------

when isMainModule:
  var # Create Basic Widgets
    win = newGUIWindow(1280, 720, nil)
    root = new GUICanvas
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
  root.size = 100
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