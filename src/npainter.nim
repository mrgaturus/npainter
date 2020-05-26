import libs/gl
#import libs/ft2
import gui/[
  window, 
  widget, 
  render, 
  #container, 
  event
  #timer
  ]
import painter/[
  canvas
]
import times

# LOAD SSE4.1
{.passC: "-msse4.1".}

type # Test Image Tile
  TTileImage = ref object of GUIWidget
    mx, my: int32
    ox, oy: int32
    canvas: NCanvas
    tex: GLuint
    work: bool
  TEnum = enum 
    eNothing

method draw(self: TTileImage, ctx: ptr CTXRender) =
  ctx.color(high uint32)
  var r = GUIRect(x: self.rect.x, y: self.rect.y, 
    w: self.canvas.w + self.canvas.rw, 
    h: self.canvas.h + self.canvas.rh)
  ctx.fill rect(r)
  ctx.texture(r, self.tex)
  # Division Lines
  discard """
  ctx.color(0xFF000000'u32)
  let
    tw = self.canvas.tw - 1
    th = self.canvas.th - 1
  var s: int16
  # Horizontal
  for x in 0..tw:
    s = cast[int16](x) shl 8
    ctx.fill rect(r.x + s, r.y, 1, r.h)
    #ctx.fill rect(r)
  # Vertical
  for x in 0..th:
    s = cast[int16](x) shl 8
    ctx.fill rect(r.x, r.y + s, r.w, 1)
    #ctx.fill rect(r)
  """



proc newTTileImage(w, h: int16): TTileImage =
  new result # Alloc Widget
  result.canvas = newCanvas(w, h)
  glGenTextures(1, addr result.tex)
  glBindTexture(GL_TEXTURE_2D, result.tex)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, cast[GLint](GL_NEAREST))
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, cast[GLint](GL_NEAREST))
  glTexImage2D(GL_TEXTURE_2D, 0, cast[GLint](GL_RGBA8), 
    result.canvas.tw shl 8, result.canvas.th shl 8, 0, GL_RGBA, 
    GL_UNSIGNED_BYTE, nil)
  glBindTexture(GL_TEXTURE_2D, 0)

proc refresh(self: TTileImage) =
  glBindTexture(GL_TEXTURE_2D, self.tex)
  #echo "tw: ", self.canvas.tw, " th: ", self.canvas.th
  var x, y: int32
  for tile in self.canvas.tiles:
    #echo "x: ", x, " y: ", y
    glTexSubImage2D(GL_TEXTURE_2D, 0, x shl 8, y shl 8, 
      256, 256, GL_RGBA, GL_UNSIGNED_BYTE, addr tile[0])
    if x + 1 < self.canvas.tw: inc(x)
    else: inc(y); x = 0
  glBindTexture(GL_TEXTURE_2D, 0)

method event(self: TTileImage, state: ptr GUIState) =
  if state.eventType == evMouseClick:
    self.mx = state.mx; self.my = state.my
    self.ox = self.canvas[0].ox
    self.oy = self.canvas[0].oy
  elif self.test(wGrab):
    if not self.work:
      var b: uint32
      b = cast[uint32](self.ox + state.mx - self.mx) or 
        (cast[uint32](self.oy + state.my - self.my) shl 16)
      pushSignal(cast[GUITarget](self), eNothing, b)
      self.work = true

method notify*(self: TTileImage, sig: GUISignal) =
  let m: uint32 = convert(sig.data, uint32)[]
  var a, b, c: float32
  self.canvas[0].ox = cast[int16](m)
  self.canvas[0].oy = cast[int16](m shr 16'u32)
  a = cpuTime()
  self.canvas.clear()
  self.canvas.composite()
  b = cpuTime()
  self.refresh()
  c = cpuTime()
  echo "composite: ", b - a, "  upload: ", c - b
  self.work = false

proc clear(tile: NTile, col: NPixel) =
  var i: int32
  while i < 65536:
    tile[i] = col; inc(i)

proc fill(canvas: var NCanvas, idx: int32, color: uint32) =
  let layer = canvas[idx]
  var i: int32
  for y in 0..<canvas.th:
    for x in 0..<canvas.tw:
      layer[].add(x.int16, y.int16)
      clear(layer.tiles[i].buffer, color)
      inc(i) # Next Tile

when isMainModule:
  var # Create Window and GUI
    win = newGUIWindow(1024, 600, nil)
    root = newTTileImage(4096, 4096)
  # Reload Canvas Texture
  #root.clear(0xFF0000FF'u32)
  root.canvas.add()
  root.canvas.add()
  root.canvas.add()
  root.canvas.add()
  root.canvas.add()
  #let layer = root.canvas[0]
  #layer[].add(1, 1)
  #layer[].add(0, 0)
  #layer[].add(2, 2)
  #layer[].add(3, 3)
  #layer[].add(3, 1)
  #clear(layer.tiles[0].buffer, 0xBB00FF00'u32)
  #clear(layer.tiles[1].buffer, 0xBBFFFF00'u32)
  #clear(layer.tiles[2].buffer, 0xBB00FFFF'u32)
  #clear(layer.tiles[3].buffer, 0xBB0000FF'u32)
  #clear(layer.tiles[4].buffer, 0xBBFF00FF'u32)
  root.canvas.fill(0, 0xBB00FF00'u32)
  let layer = root.canvas[1]
  layer.ox = 127
  layer.oy = 127
  root.canvas.fill(1, 0xBB0000FF'u32)
  root.canvas.fill(2, 0xBB00FFFF'u32)
  root.canvas.fill(3, 0xBB0FF0FF'u32)
  root.canvas.fill(4, 0x55FF00FF'u32)
  root.canvas.composite()
  root.refresh()
  # Run GUI Program
  var running = 
    win.open(root)
  while running:
    # Render Main Program
    glClearColor(0.6, 0.6, 0.6, 1.0)
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
    # Render GUI
    running = win.tick()
  # Close Window and Dispose Resources
  win.close()
