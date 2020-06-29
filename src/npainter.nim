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

type
  # Voxel Transversal 32x32
  VoxelT = ref object of GUIWidget
    x1, y1, x2, y2: float32
    grid: array[1024, bool]
  # Test Image Tile
  TTCursor = object
    x, y: int32
  TTileImage = ref object of GUIWidget
    mx, my: int32
    ox, oy: int32
    canvas: NCanvas
    tex: GLuint
    cur: TTCursor
    work: bool
    # Voxel Test
    voxel: VoxelT
  TEnum = enum
    eNothing

# ------------------------
# A Fast Voxel Transversal
# ------------------------

method draw(self: VoxelT, ctx: ptr CTXRender) =
  ctx.color(0x2F2F2F2F.uint32)
  var # Each Tile
    r: GUIRect
    cursor: int16
  # Define Rect
  r.x = self.rect.x
  r.y = self.rect.y
  r.w = 16; r.h = 16
  # Draw Each Tile
  for y in 0..<32:
    for x in 0..<32:
      ctx.color if self.grid[cursor]:
        0xFF2f2f7f.uint32
      else: 0xFF2F2F2F.uint32
      # Fill Tile
      ctx.fill(r.rect)
      # Next Grid Pos
      inc(cursor); r.x += 16
    r.x = self.rect.x
    r.y += 16 # Next Row
  # Draw Line - Dirty
  ctx.color(uint32.high)
  let # Shortcut Convert
    rx = float32(self.rect.x)
    ry = float32(self.rect.y)
  ctx.triangle(
    point(rx + self.x1 * 16, ry + self.y1 * 16),
    point(rx + self.x1 * 16, ry + self.y1 * 16),
    point(rx + self.x2 * 16, ry + self.y2 * 16)
  )

from math import floor

proc transversal(self: VoxelT) =
  let # Point Distances
    dx = abs(self.x2 - self.x1)
    dy = abs(self.y2 - self.y1)
    # Floor X Coordinates
    x1 = floor(self.x1)
    y1 = floor(self.y1)
    # Floor Y Coordinates
    x2 = floor(self.x2)
    y2 = floor(self.y2)
  var # Voxel Steps
    stx, sty: int8
    error: float32
    # Voxel Number
    n: int32 = 1
    # Grid Index
    i: int32
  # X Incremental
  if dx == 0:
    stx = 0 # No X Step
    error = high(float32)
  elif self.x2 > self.x1:
    n += int32(x2 - x1); stx = 1
    error = (x1 - self.x1 + 1) * dy
  else: # Negative X Direction
    n += int32(x1 - x2); stx = -1
    error = (self.x1 - x1) * dy
  # Y Incremental
  if dy == 0:
    sty = 0 # No Y Step
    error -= high(float32)
  elif self.y2 > self.y1:
    n += int32(y2 - y1); sty = 1
    error -= (y1 - self.y1 + 1) * dx
  else: # Negative Y Direction
    n += int32(y1 - y2); sty = -1
    error -= (self.y1 - y1) * dx
  # Set Voxel Grid Index
  i = int32(y1 * 32 + x1)
  sty *= 32 # Stride
  # Iterate Each Voxel
  while n > 0:
    # Put Current Voxel
    self.grid[i] = true
    # DDA Step
    if error > 0:
      i += sty
      error -= dx
    else:
      i += stx
      error += dy
    dec(n) # Next Voxel

method event(self: VoxelT, state: ptr GUIState) =
  state.mx -= self.rect.x
  state.my -= self.rect.y
  if state.eventType == evMouseClick:
    self.x1 = float32(state.mx) / 16
    self.y1 = float32(state.my) / 16
  elif self.test(wGrab):
    self.x2 = float32(state.mx) / 16
    self.y2 = float32(state.my) / 16
    zeroMem(addr self.grid[0], 1024)
    self.transversal()

proc newVoxelT(): VoxelT =
  new result # Alloc
  result.flags = wStandard
  result.minimum(256, 256)

# -----------------
# TEST TILED CANVAS
# -----------------

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
    result.canvas.cw, result.canvas.ch, 0, GL_RGBA, 
    GL_UNSIGNED_BYTE, nil)
  glBindTexture(GL_TEXTURE_2D, 0)
  # Create new voxel
  result.voxel = newVoxelT()
  result.voxel.geometry(0, 0, 512, 512)

proc refresh(self: TTileImage) =
  glBindTexture(GL_TEXTURE_2D, self.tex)
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 
    self.canvas.cw, self.canvas.ch, GL_RGBA, 
    GL_UNSIGNED_BYTE, addr self.canvas.buffer[0])
  glBindTexture(GL_TEXTURE_2D, 0)

method event(self: TTileImage, state: ptr GUIState) =
  if state.eventType == evMouseClick:
    if (state.mods and ShiftMod) == 0:
      self.mx = state.mx; self.my = state.my
      self.ox = self.canvas[4].x
      self.oy = self.canvas[4].y
    elif self.voxel.test(wFramed):
      self.voxel.close()
    else: # Open On Cursor Position
      self.voxel.move(state.mx, state.my)
      self.voxel.open()
  elif self.test(wGrab):
    if not self.work:
      var t = TTCursor(
        x: self.ox + state.mx - self.mx,
        y: self.oy + state.my - self.my)
      pushSignal(cast[GUITarget](self), eNothing, t)
      self.work = true

method notify*(self: TTileImage, sig: GUISignal) =
  let m = convert(sig.data, TTCursor)[]
  var b, c, d: float32
  self.canvas[4].x = m.x
  self.canvas[4].y = m.y
  self.canvas.stencil(self.canvas[4][])
  b = cpuTime()
  self.canvas.composite()
  c = cpuTime()
  self.refresh()
  d = cpuTime()
  echo "composite: ", c - b, "  upload: ", d - c
  self.work = false

proc clear(tile: NTile, col: NPixel) =
  var i: int32
  while i < 4096:
    tile[i] = col; inc(i)

proc fill(canvas: var NCanvas, idx: int32, color: uint32) =
  let layer = canvas[idx]
  var i: int32
  for y in 0..<canvas.ch shr 6:
    for x in 0..<canvas.cw shr 6:
      layer[].add(x.int16, y.int16)
      clear(layer.tiles[i].buffer, color)
      inc(i) # Next Tile

#[
proc fill(canvas: var NCanvas, idx, w, h: int32, color: uint32) =
  let layer = canvas[idx]
  var i: int32
  #for y in 0..<w:
  #  for x in 0..<h:
  layer[].add(w.int16, h.int16)
  clear(layer.tiles[i].buffer, color)
  inc(i) # Next Tile
]#

when isMainModule:
  var # Create Window and GUI
    win = newGUIWindow(1024, 600, nil)
    root = newTTileImage(1023, 1023)
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
  root.canvas.fill(0, 0xFF00FF00'u32)
  let layer = root.canvas[1]
  layer.x = 64
  layer.y = 64
  root.canvas.fill(1, 0xFF0000FF'u32)
  root.canvas.fill(2, 0xFF00FFFF'u32)
  root.canvas.fill(3, 0xFFFFF0FF'u32)
  root.canvas[3].x = 128
  root.canvas[3].y = 128
  root.canvas.fill(4, 0xBB000000'u32)
  #root.canvas[0][].add(0, 0)
  #root.canvas[0][].add(1, 1)
  #clear(root.canvas[0].tiles[0].buffer, 0xBB000000'u32)
  #clear(root.canvas[0].tiles[1].buffer, 0xBB000000'u32)
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
