import gui/[window, widget, render, event]
import libs/gl

type
  CaVector = object
    x, y: float32
  CaQuad = object
    v: array[4, CaVector]
  GUICanvas = ref object of GUIWidget
    tex: GLuint
    quad: CaQuad
    buffer: array[1280*720*4, uint16]
    grab: ptr CaVector
    color: uint32
    amout: float
    busy: bool

{.compile: "painter/distort.c".}
proc both_distort(q: var CaQuad, p: CaVector, uv: var CaVector, t: float): int32 {.importc.}
proc bilinear_distort(q: var CaQuad, p: CaVector, uv: var CaVector): int32 {.importc.}
proc perspective_check(q: var CaQuad): int32 {.importc.}
proc perspective_distort(q: var CaQuad, p: CaVector, uv: var CaVector): int32 {.importc.}
proc checkboard(uv: CaVector): uint16 {.importc.}
#proc debug_quad(q: var CaQuad) {.importc.}

proc xy(v: var CaVector, x, y: float32) {.inline.} =
  v.x = x; v.y = y

method draw(self: GUICanvas, ctx: ptr CTXRender) =
  ctx.color(uint32 0xFFBBBBBB)
  var r = rect(0, 0, 1280, 720)
  ctx.fill(r)
  ctx.texture(r, self.tex)
  ctx.color(self.color)
  for v in self.quad.v:
    r = rect(int32 v.x - 5, int32 v.y - 5, 10, 10)
    ctx.fill(r)
  ## Draw Lines
  ctx.line(
    point(self.quad.v[0].x, self.quad.v[0].y),
    point(self.quad.v[1].x, self.quad.v[1].y)
  )
  ctx.line(
    point(self.quad.v[1].x, self.quad.v[1].y),
    point(self.quad.v[2].x, self.quad.v[2].y)
  )
  ctx.line(
    point(self.quad.v[2].x, self.quad.v[2].y),
    point(self.quad.v[3].x, self.quad.v[3].y)
  )
  ctx.line(
    point(self.quad.v[3].x, self.quad.v[3].y),
    point(self.quad.v[0].x, self.quad.v[0].y)
  )
  self.busy = false

proc check(self: GUICanvas, x, y: int32): ptr CaVector =
  let 
    dx = float32(x)
    dy = float32(y)
  for v in mitems(self.quad.v):
    if dx > v.x - 10 and dx < v.x + 10 and dy > v.y - 10 and dy < v.y + 10:
      echo "reached"
      result = addr v

method event(self: GUICanvas, state: ptr GUIState) =
  if state.kind == evMouseClick:
    self.grab = check(self, state.mx, state.my)
  elif self.test(wGrab) and not self.busy:
    zeroMem(addr self.buffer[0], 1280*720*4*sizeof(uint16))
    if not isNil(self.grab):
      self.grab.x = state.mx.float32
      self.grab.y = state.my.float32
    else: 
      echo "reached amout"
      self.amout = (state.mx.float / 512).clamp(0.0, 1.0)
    var p, uv: CaVector
    if perspective_check(self.quad) == 1:
      for y in 0..<720:
        for x in 0..<1280:
          p.xy(x.float32, y.float32)
          if both_distort(self.quad, p, uv, self.amout) == 1:
            self.buffer[(y * 1280 + x) * 4] = uint16(65535 * uv.x)
            self.buffer[(y * 1280 + x) * 4 + 1] = uint16(65535 * uv.y)
            self.buffer[(y * 1280 + x) * 4 + 3] = checkboard(uv)
            self.buffer[(y * 1280 + x) * 4 + 3] = checkboard(uv)
          #elif bilinear_distort(self.quad, p, uv) == 1:
            #self.buffer[(y * 1280 + x) * 4 + 3] = checkboard(uv)
      self.color = uint32 0xFF2B2B2B
    else: self.color = uint32 0xFF0000FF
    glBindTexture(GL_TEXTURE_2D, self.tex)
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 1280, 720, 
      GL_RGBA, GL_UNSIGNED_SHORT, addr self.buffer[0])
    glBindTexture(GL_TEXTURE_2D, 0)
    self.busy = true

when isMainModule:
  var win = # -- Create GUIWindow
    newGUIWindow(1280, 720, nil)
  # -- Create GUICanvas
  let root = new GUICanvas
  root.flags = wMouse
  # -- Draw On Canvas
  block:
    var 
      quad: CaQuad
    quad.v[0].xy(500, 200)
    quad.v[1].xy(800, 200)
    quad.v[2].xy(800, 500)
    quad.v[3].xy(500, 500)
    root.quad = quad
    root.color = uint32 0xFF2B2B2B
  # -- Draw Quad
  var p, uv: CaVector
  for y in 0..<720:
    for x in 0..<1280:
      p.xy(x.float32, y.float32)
      if bilinear_distort(root.quad, p, uv) == 1:
        root.buffer[(y * 1280 + x) * 4] = uint16(65535 * uv.x)
        root.buffer[(y * 1280 + x) * 4 + 1] = uint16(65535 * uv.y)
        root.buffer[(y * 1280 + x) * 4 + 3] = checkboard(uv)
  glBindTexture(GL_TEXTURE_2D, root.tex)
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 1280, 720, 
    GL_RGBA, GL_UNSIGNED_SHORT, addr root.buffer[0])
  glBindTexture(GL_TEXTURE_2D, 0)
  # -- Generate Canvas Texture
  glGenTextures(1, addr root.tex)
  glBindTexture(GL_TEXTURE_2D, root.tex)
  glTexImage2D(GL_TEXTURE_2D, 0, cast[GLint](GL_RGBA16), 
    1280, 720, 0, GL_RGBA, GL_UNSIGNED_SHORT, addr root.buffer[0])
  # Set Mig/Mag Filter
  glTexParameteri(GL_TEXTURE_2D, 
    GL_TEXTURE_MIN_FILTER, cast[GLint](GL_NEAREST))
  glTexParameteri(GL_TEXTURE_2D, 
    GL_TEXTURE_MAG_FILTER, cast[GLint](GL_NEAREST))
  glBindTexture(GL_TEXTURE_2D, 0)
  # Open Window
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
  # Close Window
  win.close()