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

# LOAD SSE4.1
{.passC: "-msse4.1".}

type # Test Image Tile
  TTileImage = ref object of GUIWidget
    mx, my: int32
    canvas: NCanvas
    tex: GLuint

method draw(self: TTileImage, ctx: ptr CTXRender) =
  ctx.color(high uint32)
  var r = GUIRect(x: self.rect.x, y: self.rect.y, 
    w: self.canvas.w + self.canvas.rw, 
    h: self.canvas.h + self.canvas.rh)
  ctx.fill rect(r)
  ctx.texture(r, self.tex)
  # Division Lines
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
  elif self.test(wGrab):
    self.canvas[0].ox += cast[int16](state.mx - self.mx)
    self.canvas[0].oy += cast[int16](state.my - self.my)
    self.canvas.clear()
    self.canvas.composite()
    self.refresh()
    self.mx = state.mx; self.my = state.my

proc clear(tile: NTile, col: NPixel) =
  var i: int32
  while i < 65536:
    tile[i] = col; inc(i)

when isMainModule:
  var # Create Window and GUI
    win = newGUIWindow(1024, 600, nil)
    root = newTTileImage(768, 768)
  # Reload Canvas Texture
  #root.clear(0xFF0000FF'u32)
  root.canvas.add()
  let layer = root.canvas[0]
  layer[].add(1, 1)
  layer[].add(0, 0)
  layer[].add(2, 2)
  clear(layer.tiles[0].buffer, 0xBB00FF00'u32)
  clear(layer.tiles[1].buffer, 0xBBFFFF00'u32)
  clear(layer.tiles[2].buffer, 0xBB00FFFF'u32)
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
