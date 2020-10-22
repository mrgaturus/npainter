import gui/[window, widget, render, event]
import libs/gl
import nimPNG
import math

# -------------------
# Simple Image Loader
# -------------------

type
  CaImage = object
    w, h: int
    buffer: string
  CaPixel = array[4, uint8]
  CaRGBA8 = ptr array[4, uint8]

proc load(file: string): CaImage =
  let image = loadPNG32(file)
  result.w = image.width
  result.h = image.height
  result.buffer = image.data

proc nearest(img: CaImage, u, v: float): CaPixel =
  let 
    pos_u = u * float(img.w - 1)
    pos_v = v * float(img.h - 1)
    # Pixel Sampling
    x = floor(pos_u + 0.5)
    y = floor(pos_v + 0.5)
  var
    x1 = x.int
    y1 = y.int
  # Skip Outside
  let
    m00 = cast[CaRGBA8](unsafeAddr img.buffer[(y1 * img.w + x1) * 4])
  # Perform Interpolation
  result[0] = m00[0]
  result[1] = m00[1]
  result[2] = m00[2]
  result[3] = m00[3]
  #result[3] = ((c0 + c1 + c2 + c3) div 4).uint8

# ---------------
# Distortion Test
# ---------------

type
  CaVector = object
    x, y: float
  CaQuad = object
    v: array[4, CaVector]
  GUICanvas = ref object of GUIWidget
    tex: GLuint
    quad, quad_n: CaQuad
    buffer: array[1280*720*4, uint8]
    grab: ptr CaVector
    color: uint32
    amout: float
    busy: bool
    image: CaImage

{.compile: "painter/distort.c".}
proc both_distort(q: var CaQuad, p: CaVector, uv: var CaVector, t: float): int32 {.importc.}
#proc bilinear_distort(q: var CaQuad, p: CaVector, uv: var CaVector): int32 {.importc.}
proc perspective_check(q: var CaQuad): int32 {.importc.}
proc perspective_distort(q: var CaQuad, p: CaVector, uv: var CaVector): int32 {.importc.}
proc checkboard(uv: CaVector): uint16 {.importc.}
#proc debug_quad(q: var CaQuad) {.importc.}

#[
proc normalize(v: var CaVector, w, h: float) =
  v.x /= w; v.y /= h

proc normalize(q: var CaQuad, w, h: float) =
  for q in mitems(q.v):
    q.normalize(w, h)
]#
proc xy(v: var CaVector, x, y: float) {.inline.} =
  v.x = x; v.y = y

method draw(self: GUICanvas, ctx: ptr CTXRender) =
  ctx.color(uint32 0xFFFFFFFF)
  var r = rect(0, 0, 2560, 1440)
  ctx.fill(r)
  ctx.texture(r, self.tex)
  ctx.color(self.color)
  for v in self.quad.v:
    r = rect(int32 v.x - 5, int32 v.y - 5, 10, 10)
    ctx.fill(r)
  ## Draw Lines
  #[
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
  ]#
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
    zeroMem(addr self.buffer[0], 1280*720*4*sizeof(uint8))
    if not isNil(self.grab):
      self.grab.x = state.mx.float32
      self.grab.y = state.my.float32
      self.quad_n = self.quad
    else: 
      echo "reached amout"
      self.amout = (state.mx.float / 512).clamp(0.0001, 0.9999)
    var p, uv: CaVector
    if perspective_check(self.quad) == 1:
      for y in 0..<720:
        for x in 0..<1280:
          p.xy(x.float, y.float)
          if both_distort(self.quad_n, p, uv, self.amout) == 1:
            let pixel = nearest(self.image, uv.x, uv.y)
            #let 
            #  checker = checkboard(uv)
            #if (uv.x * 65535) == 65535 or (uv.x * 65535) == 65535: continue
            self.buffer[(y * 1280 + x) * 4] = pixel[0]
            self.buffer[(y * 1280 + x) * 4 + 1] = pixel[1]
            self.buffer[(y * 1280 + x) * 4 + 2] = pixel[2]
            self.buffer[(y * 1280 + x) * 4 + 3] = pixel[3]

            #self.buffer[(y * 1280 + x) * 4 + 3] = 0xFF
            #elif u == 0 or v == 0:
            #  self.buffer[(y * 1280 + x) * 4] = 0
            #  self.buffer[(y * 1280 + x) * 4 + 2] = 0xFFFF
            #elif checker > 32768:
            #  self.buffer[(y * 1280 + x) * 4] = u
            #  self.buffer[(y * 1280 + x) * 4 + 1] = v
            #self.buffer[(y * 1280 + x) * 4 + 3] = 0xFFFF
          #elif bilinear_distort(self.quad, p, uv) == 1:
            #self.buffer[(y * 1280 + x) * 4 + 3] = checkboard(uv)
      self.color = uint32 0xFF2B2B2B
    else: self.color = uint32 0xFF0000FF
    glBindTexture(GL_TEXTURE_2D, self.tex)
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 1280, 720, 
      GL_RGBA, GL_UNSIGNED_BYTE, addr self.buffer[0])
    glBindTexture(GL_TEXTURE_2D, 0)
    self.busy = true

when isMainModule:
  var win = # -- Create GUIWindow
    newGUIWindow(1280, 720, nil)
  # -- Create GUICanvas
  let root = new GUICanvas
  root.flags = wMouse
  # -- Load Image
  var img = load("yuh.png")
  root.image = img
  # -- Draw On Canvas
  block:
    var 
      quad: CaQuad
    quad.v[0].xy(20.0, 1.0)
    quad.v[1].xy(float(img.w), 1.0)
    quad.v[2].xy(float(img.w), float(img.h))
    quad.v[3].xy(1.0, float(img.h))
    root.quad = quad
    root.quad_n = quad
    root.color = uint32 0xFF2B2B2B
  # -- Draw Quad
  var p, uv: CaVector
  for y in 0..<720:
    for x in 0..<1280:
      p.xy(x.float32, y.float32)
      if perspective_distort(root.quad, p, uv) == 1:
        let checker = checkboard(uv)
        if checker > 32768:
          root.buffer[(y * 1280 + x) * 4] = uint8(255 * uv.x)
          root.buffer[(y * 1280 + x) * 4 + 1] = uint8(255 * uv.y)
        root.buffer[(y * 1280 + x) * 4 + 3] = 0xFF
  # -- Draw Texture
  for x in 1..img.w:
    for y in 1..img.h:
      let u = x - 1
      let v = y - 1
      root.buffer[(y * 1280 + x) * 4] = img.buffer[(v * img.w + u) * 4].uint8
      root.buffer[(y * 1280 + x) * 4 + 1] = img.buffer[(v * img.w + u) * 4 + 1].uint8
      root.buffer[(y * 1280 + x) * 4 + 2] = img.buffer[(v * img.w + u) * 4 + 2].uint8
      root.buffer[(y * 1280 + x) * 4 + 3] = img.buffer[(v * img.w + u) * 4 + 3].uint8
  glBindTexture(GL_TEXTURE_2D, root.tex)
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 1280, 720, 
    GL_RGBA, GL_UNSIGNED_SHORT, addr root.buffer[0])
  glBindTexture(GL_TEXTURE_2D, 0)
  # -- Generate Canvas Texture
  glGenTextures(1, addr root.tex)
  glBindTexture(GL_TEXTURE_2D, root.tex)
  glTexImage2D(GL_TEXTURE_2D, 0, cast[GLint](GL_RGBA8), 
    1280, 720, 0, GL_RGBA, GL_UNSIGNED_BYTE, addr root.buffer[0])
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