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
  CaSubPixel {.used.} = array[4, uint]

proc load(file: string): CaImage =
  let image = loadPNG32(file)
  result.w = image.width
  result.h = image.height
  result.buffer = image.data

proc `[]`(img: CaImage, x, y: int): CaPixel =
  if x < img.w and x >= 0 and y < img.h and y >= 0:
    result = cast[CaRGBA8](
      unsafeAddr img.buffer[(y * img.w + x) shl 2])[]
  #else:
  #  result[2] = 0xFF
  #  result[3] = 0xFF

proc nearest(img: CaImage, u, v: float): CaPixel =
  let 
    pos_u = u * float(img.w - 1)
    pos_v = v * float(img.h - 1)
    # Pixel Sampling
  var
    x1 = floor(pos_u).int
    y1 = floor(pos_v).int
  # Skip Outside
  let
    m00 = img[x1, y1]
  # Perform Interpolation
  result[0] = m00[0]
  result[1] = m00[1]
  result[2] = m00[2]
  result[3] = m00[3]
  #result[3] = ((c0 + c1 + c2 + c3) div 4).uint8

proc bilinear(img: CaImage, u, v: float): CaPixel =
  let
    pos_u = u * float(img.w - 1)
    pos_v = v * float(img.h - 1)
    x1 = floor(pos_u)
    y1 = floor(pos_v)
    # Interpolator
    su = int32((pos_u - x1) * 255)
    sv = int32((pos_v - y1) * 255)
  var
    # Castings
    xx1 = x1.int
    yy1 = y1.int
    xx2 = xx1 + 1
    yy2 = yy1 + 1
  let
    # Pixel Elements
    m00 = img[xx1, yy1]
    m10 = img[xx2, yy1]
    m01 = img[xx1, yy2]
    m11 = img[xx2, yy2]
  # Interpolate Elements
  var 
    a, b: int32
    c00, c10, c01, c11: int32
  # Interpolate Red
  c00 = m00[0].int32; c10 = m10[0].int32; c01 = m01[0].int32; c11 = m11[0].int32
  a = c00 + su * (c10 - c00) div 255
  b = c01 + su * (c11 - c01) div 255
  result[0] = uint8(a + sv * (b - a) div 255)
  # Interpolate Green
  c00 = m00[1].int32; c10 = m10[1].int32; c01 = m01[1].int32; c11 = m11[1].int32
  a = c00 + su * (c10 - c00) div 255
  b = c01 + su * (c11 - c01) div 255
  result[1] = uint8(a + sv * (b - a) div 255)
  # Interpolate Blue
  c00 = m00[2].int32; c10 = m10[2].int32; c01 = m01[2].int32; c11 = m11[2].int32
  a = c00 + su * (c10 - c00) div 255
  b = c01 + su * (c11 - c01) div 255
  result[2] = uint8(a + sv * (b - a) div 255)
  # Interpolate Alpha
  c00 = m00[3].int32; c10 = m10[3].int32; c01 = m01[3].int32; c11 = m11[3].int32
  a = c00 + su * (c10 - c00) div 255
  b = c01 + su * (c11 - c01) div 255
  result[3] = uint8(a + sv * (b - a) div 255)

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
    quad: CaQuad
    buffer: array[1280*720*4, uint8]
    grab: ptr CaVector
    color: uint32
    amout: float
    busy: bool
    image: CaImage

{.compile: "painter/distort.c".}
proc both_distort(q: var CaQuad, p: CaVector, uv: var CaVector, t: float): int32 {.importc.}
proc both_positive(q: var CaQuad, p: CaVector, uv: var CaVector, t: float): int32 {.importc.}
proc both_negative(q: var CaQuad, p: CaVector, uv: var CaVector, t: float): int32 {.importc.}
proc checkboard(uv: var CaVector): uint8 {.importc, used.}
proc perspective_check(q: var CaQuad): int32 {.importc.}

proc xy(v: var CaVector, x, y: float) {.inline.} =
  v.x = x; v.y = y

method draw(self: GUICanvas, ctx: ptr CTXRender) =
  ctx.color(uint32 0xFFFFFFFF)
  #ctx.color(uint32 0xFFFF2f2f)
  var r = rect(0, 0, 1280, 720)
  ctx.fill(r)
  ctx.color(uint32 0xFFFFFFFF)
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

proc check(self: GUICanvas, x, y: int32): ptr CaVector =
  let 
    dx = float32(x)
    dy = float32(y)
  for v in mitems(self.quad.v):
    if dx > v.x - 10 and dx < v.x + 10 and dy > v.y - 10 and dy < v.y + 10:
      echo "reached"
      result = addr v

proc cb_distort(g: pointer, w: ptr GUITarget) =
  let self = cast[GUICanvas](w[])
  var p, uv: CaVector
  var pixel: CaPixel
  let orient = perspective_check(self.quad)
  if orient > 0:
    let distort =
      if orient == 1: both_negative
      else: both_positive
    for y in 0..<720:
      for x in 0..<1280:
        when defined(subpixel):
          var sp: CaVector
          var subpixel: CaSubPixel
          for sx in 0..<8:
            let dsx = (sx.float + 0.5) * 0.125 - 0.5
            for sy in 0..<8:
              let dsy = (sy.float + 0.5) * 0.125 - 0.5
              sp.xy(x.float + dsx, y.float + dsy)
              if distort(self.quad, sp, uv, self.amout) == 1:
                pixel = bilinear(self.image, uv.x, uv.y)
                subpixel[0] += pixel[0]
                subpixel[1] += pixel[1]
                subpixel[2] += pixel[2]
                subpixel[3] += pixel[3]
          # Compute Pixel Average
          subpixel[0] = subpixel[0] shr 6
          subpixel[1] = subpixel[1] shr 6
          subpixel[2] = subpixel[2] shr 6
          subpixel[3] = subpixel[3] shr 6
            # Replace Pixel
          self.buffer[(y * 1280 + x) * 4] = subpixel[0].uint8
          self.buffer[(y * 1280 + x) * 4 + 1] = subpixel[1].uint8
          self.buffer[(y * 1280 + x) * 4 + 2] = subpixel[2].uint8
          self.buffer[(y * 1280 + x) * 4 + 3] = subpixel[3].uint8
        else:
          p.xy(x.float, y.float)
          if distort(self.quad, p, uv, self.amout) == 1:
            pixel = bilinear(self.image, uv.x, uv.y)
            self.buffer[(y * 1280 + x) * 4] = pixel[0]
            self.buffer[(y * 1280 + x) * 4 + 1] = pixel[1]
            self.buffer[(y * 1280 + x) * 4 + 2] = pixel[2]
            self.buffer[(y * 1280 + x) * 4 + 3] = pixel[3]
    self.color = uint32 0xFF2B2B2B
  else: self.color = uint32 0xFF0000FF
  glBindTexture(GL_TEXTURE_2D, self.tex)
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 1280, 720, 
    GL_RGBA, GL_UNSIGNED_BYTE, addr self.buffer[0])
  #glGenerateMipmap(GL_TEXTURE_2D)
  glBindTexture(GL_TEXTURE_2D, 0)
  self.busy = false

method event(self: GUICanvas, state: ptr GUIState) =
  if state.kind == evMouseClick:
    self.grab = check(self, state.mx, state.my)
  elif self.test(wGrab):
    zeroMem(addr self.buffer[0], 1280*720*4*sizeof(uint8))
    if not isNil(self.grab):
      self.grab.x = state.mx.float32
      self.grab.y = state.my.float32
    else:
      self.amout = (state.mx.float / 512).clamp(0.05, 0.75)
    if not self.busy:
      var target = self.target
      pushCallback(cb_distort, target)
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
    quad.v[0].xy(1.0, 1.0)
    quad.v[1].xy(float(img.w), 1.0)
    quad.v[2].xy(float(img.w), float(img.h))
    quad.v[3].xy(1.0, float(img.h))
    root.quad = quad
    root.color = uint32 0xFF2B2B2B
  # -- Draw Texture
  #var uv: CaVector
  echo img.w, img.h
  for x in 1..img.w:
    for y in 1..img.h:
      #uv.xy((x.float - 1) / (img.w.float - 1), (y.float - 1) / (img.h.float - 1))
      #if x == 2 and y == 2:
      #  echo uv.repr
      let pixel = root.image[x - 1, y - 1]
      root.buffer[(y * 1280 + x) * 4] = pixel[0]
      root.buffer[(y * 1280 + x) * 4 + 1] = pixel[1]
      root.buffer[(y * 1280 + x) * 4 + 2] = pixel[2]
      root.buffer[(y * 1280 + x) * 4 + 3] = pixel[3]
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
  #glGenerateMipmap(GL_TEXTURE_2D)
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