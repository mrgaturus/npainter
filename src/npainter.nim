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
from math import floor

# LOAD SSE4.1
{.passC: "-msse4.1".}

# AABB / Sorting
type
  NBBox = object
    xmin, xmax: float32
    ymin, ymax: float32
  NPoint = object
    x, y: float32
  NQuad = array[4, NPoint]

type
  # Voxel Transversal 32x32
  VoxelT = ref object of GUIWidget
    quad: NQuad
    box: NBBox
    # Test Grid
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

method draw(self: VoxelT, ctx: ptr CTXRender) =
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
  # Draw Lines
  let p = point(self.rect.x, self.rect.y)
  ctx.color(high uint32)
  ctx.line(
    point(p.x + self.quad[0].x * 16, p.y + self.quad[0].y * 16),
    point(p.x + self.quad[1].x * 16, p.y + self.quad[1].y * 16)
  )
  ctx.line(
    point(p.x + self.quad[1].x * 16, p.y + self.quad[1].y * 16),
    point(p.x + self.quad[2].x * 16, p.y + self.quad[2].y * 16)
  )
  ctx.line(
    point(p.x + self.quad[2].x * 16, p.y + self.quad[2].y * 16),
    point(p.x + self.quad[3].x * 16, p.y + self.quad[3].y * 16)
  )
  ctx.line(
    point(p.x + self.quad[3].x * 16, p.y + self.quad[3].y * 16),
    point(p.x + self.quad[0].x * 16, p.y + self.quad[0].y * 16)
  )

# ----------------------
# !!! AABB RECTANGLE SORTING
# ----------------------

proc aabb(quad: NQuad): NBBox =
  var # Iterator
    i = 1
    p = quad[0]
  # Set XMax/XMin
  result.xmin = p.x
  result.xmax = p.x
  # Set YMax/YMin
  result.ymin = p.y
  result.ymax = p.y
  while i < 4:
    p = quad[i]
    # Check XMin/XMax
    if p.x < result.xmin:
      result.xmin = p.x
    elif p.x > result.xmax:
      result.xmax = p.x
    # Check YMin/YMax
    if p.y < result.ymin:
      result.ymin = p.y
    elif p.y > result.ymax:
      result.ymax = p.y
    # Next Point
    inc(i)

proc sort(quad: var NQuad, box: NBBox) =
  var # Sorted
    n: NQuad
  for p in quad:
    if p.y == box.ymax: n[0] = p
    elif p.x == box.xmin: n[1] = p
    elif p.y == box.ymin: n[2] = p
    elif p.x == box.xmax: n[3] = p
  quad = n # Replace to Sorted

# ----------------------------
# A FAST VOXEL TRAVERSAL LAZY
# ----------------------------

type # Voxel Traversal
  NTraversal = object
    # Voxel Count
    n: int32
    # Position
    x, y: int16
    # X, Y Steps
    sx, sy: int8
    # Voxel Traversal DDA
    dx, dy, error: float32

proc line(dda: var NTraversal, a, b: NPoint) =
  let # Point Distances
    dx = abs(b.x - a.x)
    dy = abs(b.y - a.y)
    # Floor X Coordinates
    x1 = floor(a.x)
    y1 = floor(a.y)
    # Floor Y Coordinates
    x2 = floor(b.x)
    y2 = floor(b.y)
  # X Incremental
  if dx == 0:
    dda.sx = 0 # No X Step
    dda.error = high(float32)
  elif b.x > a.x:
    dda.sx = 1 # Positive
    dda.n += int32(x2 - x1)
    dda.error = (x1 - a.x + 1) * dy
  else:
    dda.sx = -1 # Negative
    dda.n += int32(x1 - x2)
    dda.error = (a.x - x1) * dy
  # Y Incremental
  if dy == 0:
    dda.sy = 0 # No Y Step
    dda.error -= high(float32)
  elif b.y > a.y:
    dda.sy = 1 # Positive
    dda.n += int32(y2 - y1)
    dda.error -= (y1 - a.y + 1) * dx
  else:
    dda.sy = -1 # Negative
    dda.n += int32(y1 - y2)
    dda.error -= (a.y - y1) * dx
  # Set Start Position
  dda.x = int16(x1)
  dda.y = int16(y1)
  # Set DDA Deltas
  dda.dx = dx
  dda.dy = dy

proc stepSkip(dda: var NTraversal) =
  while dda.n > 0:
    dec(dda.n)
    # Break at Next Row
    if dda.error > 0:
      dda.y += dda.sy
      dda.error -= dda.dx
      break # Next Y
    # Next X Voxel
    dda.x += dda.sx
    dda.error += dda.dy

proc stepMin(dda: var NTraversal): int16 =
  result = dda.x
  while dda.n > 0:
    dec(dda.n)
    # Break at Next Row
    if dda.error > 0:
      dda.y += dda.sy
      dda.error -= dda.dx
      break # Next Y
    # Next X Voxel
    dda.x += dda.sx
    dda.error += dda.dy
    # Check Min X
    if dda.x < result:
      result = dda.x

proc stepMax(dda: var NTraversal): int16 =
  result = dda.x
  while dda.n > 0:
    dec(dda.n)
    # Break at Next Row
    if dda.error > 0:
      dda.y += dda.sy
      dda.error -= dda.dx
      break # Next Y
    # Next X Voxel
    dda.x += dda.sx
    dda.error += dda.dy
    # Check Max X
    if dda.x > result:
      result = dda.x

# --------------
# SCANLINE TEST PROCS
# --------------

proc scanline(self: VoxelT) =
  let quad = self.quad
  var # Traversal Variables
    left, right: NTraversal
    # MidLine Points
    mleft, mright = true
    # Iterator Variables
    x, w, y, h: int16
  # Define Starting Y
  y = floor(quad[2].y).int16
  # Define Ending Y
  h = floor(quad[0].y).int16
  if h > 32: # Clamp
    h = 32 - 1
  # Define Traversal Lines
  line(left, quad[2], quad[1])
  line(right, quad[2], quad[3])
  # Skip Outside Lines
  while y < 0:
    left.stepSkip()
    if left.n == 0 and mleft:
      line(left, quad[1], quad[0])
      # Bottom Line
      mleft = false
    right.stepSkip()
    if right.n == 0 and mright:
      line(right, quad[3], quad[0])
      # Bottom Line
      mright = false
    inc(y) # Next Line
  # Do Scanline
  while y <= h:
    # Line Start
    if left.n == 0 and mleft:
      line(left, quad[1], quad[0])
      # Bottom Line
      mleft = false
    x = left.stepMin()
    # Line Width
    if right.n == 0 and mright:
      line(right, quad[3], quad[0])
      # Bottom Line
      mright = false
    w = right.stepMax()
    # Check Scanline
    if w >= 0 and x < 32:
      # Clamp X, Y
      if x < 0: x = 0
      if w >= 32: 
        w = 32 - 1
      while x <= w:
        self.grid[y shl 5 + x] = true
        inc(x) # Next Tile
    inc(y) # Next Line

# ------------------
# VOXEL TEST METHODS
# ------------------

#[
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
]#

proc newVoxelT(): VoxelT =
  new result # Alloc
  result.flags = wStandard
  result.minimum(256, 256)
  # Left Side
  result.quad[0].x = 10
  result.quad[0].y = 20
  # Top Side
  result.quad[1].x = 20
  result.quad[1].y = 30
  # Right Side
  result.quad[2].x = 40
  result.quad[2].y = 10
  # Bottom Side
  result.quad[3].x = 50
  result.quad[3].y = 20
  # 1 - Calculate AABB
  sort(result.quad, result.quad.aabb)
  # 3 - Do Scanline
  result.scanline()

# -----------------
# TEST TILED CANVAS
# -----------------

method draw(self: TTileImage, ctx: ptr CTXRender) =
  ctx.color(high uint32)
  var r = rect(self.rect.x, self.rect.y, 
    self.canvas.w + self.canvas.rw, 
    self.canvas.h + self.canvas.rh)
  # Draw Rect
  ctx.fill(r)
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
    root = newTTileImage(1024, 1024)
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
