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

# Scanline Array
type
  NScanline = array[32, int8]
# Line Clipping
type
  ClipSides = enum
    csInside #0000
    csLeft, csRight
    csBottom, csTop
  ClipFlags = set[ClipSides]
const TEST_SIDE = float32(32)
# AABB / Sorting
type
  NBBox = object
    xmin, xmax: float32
    ymin, ymax: float32
  NPoint = object
    x, y: float32
  NLine = object
    a, b: NPoint
  NRect = array[4, NPoint]

type
  # Voxel Transversal 32x32
  VoxelT = ref object of GUIWidget
    quad: NRect
    box: NBBox
    # Test Grid
    grid: array[1024, bool]
    # Scanline Buffers
    sl, sr: array[32, int8]
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
  # Draw Scanline
  let
    ymin = int32 self.box.ymin
    ymax = int32 self.box.ymax
    px = self.rect.x
    py = self.rect.y
  # Left
  ctx.color(0xFF2f7f2f.uint32)
  for y in ymin..ymax:
    r.y = py + (y.int32 shl 4)
    r.x = px + (self.sl[y].int16 shl 4)
    # Fill Rect
    ctx.fill(r.rect)
  # Right
  ctx.color(0xFF7f7f2f.uint32)
  for y in ymin..ymax:
    r.y = py + (y.int32 shl 4)
    r.x = px + (self.sr[y].int16 shl 4)
    # Fill Rect
    ctx.fill(r.rect)
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

# ------------------------
# !!!!! A Fast Voxel Transversal
# ------------------------

from math import floor

proc voxel(a, b: NPoint, s: var NScanline) =
  let # Point Distances
    dx = abs(b.x - a.x)
    dy = abs(b.y - a.y)
    # Floor X Coordinates
    x1 = floor(a.x)
    y1 = floor(a.y)
    # Floor Y Coordinates
    x2 = floor(b.x)
    y2 = floor(b.y)
  var # Voxel Steps
    stx, sty: int8
    error: float32
    # Voxel Number
    n: int32 = 1
    # Position
    x, y: int8
  # X Incremental
  if dx == 0:
    stx = 0 # No X Step
    error = high(float32)
  elif b.x > a.x:
    n += int32(x2 - x1); stx = 1
    error = (x1 - a.x + 1) * dy
  else: # Negative X Direction
    n += int32(x1 - x2); stx = -1
    error = (a.x - x1) * dy
  # Y Incremental
  if dy == 0:
    sty = 0 # No Y Step
    error -= high(float32)
  elif b.y > a.y:
    n += int32(y2 - y1); sty = 1
    error -= (y1 - a.y + 1) * dx
  else: # Negative Y Direction
    n += int32(y1 - y2); sty = -1
    error -= (a.y - y1) * dx
  # Set Start Position
  x = int8(x1); y = int8(y1)
  # Voxel Iterator
  while n > 0:
    if x < 32 and y < 32:
      s[y] = x # Replace
    # DDA Step
    if error > 0:
      # Next Y
      y += sty
      error -= dx
    else:
      # Next X
      x += stx
      error += dy
    dec(n) # Next Voxel

# ------------------------------
# !!!! Cohen Sutherland Line Clipping
# ------------------------------

proc flags(p: NPoint): ClipFlags =
  # Test Laterals
  if p.x < 0:
    result.incl csLeft
  elif p.x > TEST_SIDE:
    result.incl csRight
  # Test Superiors
  if p.y < 0:
    result.incl csBottom
  elif p.y > TEST_SIDE:
    result.incl csTop

proc clip(line: var NLine, a, b: NPoint): bool =
  var # Variables
    x, y, m: float32
    c1, c2, c: ClipFlags
  # Clip Flags
  c1 = flags(a)
  c2 = flags(b)
  # Clip Loop
  while true:
    # Test Inside or Outside
    if (c1 + c2) == {}: return true
    elif (c1 * c2) != {}: return false
    # Who is Outside?
    elif c1 == {}: c = c2
    else: c = c1
    # Calculate Slope
    x = a.x; y = a.y # Cache
    m = (b.y - y) / (b.x - x)
    # Clip Superiors
    if csTop in c: 
      x += (TEST_SIDE - y) / m
      y = TEST_SIDE # Top
    elif csBottom in c: 
      x += (0 - y) / m
      y = 0 # Bottom
    # Clip Laterals
    elif csRight in c:
      y += (TEST_SIDE - x) * m
      x = TEST_SIDE # Right
    elif csLeft in c:
      y += (0 - x) * m
      x = 0 # Left
    # Replace Point
    if c == c1:
      line.a.x = x
      line.a.y = y
      # Check Clip State
      c1 = flags(line.a)
    else: # C2
      line.b.x = x
      line.b.y = y
      # Check Clip State
      c2 = flags(line.b)

# ----------------------
# !!! AABB RECTANGLE SORTING
# ----------------------

proc aabb(rect: NRect): NBBox =
  var # Iterator
    p = rect[0]
    i: int32 = 1
  # Set XMax/XMin
  result.xmin = p.x
  result.xmax = p.x
  # Set YMax/YMin
  result.ymin = p.y
  result.ymax = p.y
  while i < 4:
    p = rect[i]
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

proc sort(rect: NRect, box: NBBox): NRect =
  for p in rect:
    if p.y == box.ymax:
      result[0] = p
    elif p.x == box.xmin:
      result[1] = p
    elif p.y == box.ymin:
      result[2] = p
    elif p.x == box.xmax:
      result[3] = p

# --------------
# SCANLINE TEST PROCS
# --------------

proc scanline(self: VoxelT) =
  var i = 0
  for t in self.sl:
    if t != 0:
      echo "min y: ", i
      echo "it's x: ", t
      break
    inc i
  let # Maximun Vertical
    h = min(int32 self.box.ymax, 32)
  var # Minimun Vertical
    y = max(int32 self.box.ymin, 0)
    x, w: int32 # Horizontal
  # Do Scanline
  while y <= h:
    x = self.sl[y]
    w = self.sr[y]
    while x <= w:
      # Put Voxel on Test Grid
      self.grid[y shl 5 + x] = true
      inc(x) # Next Voxel
    inc(y) # Next Row

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
  result.quad[0].y = 15
  # Top Side
  result.quad[1].x = 20
  result.quad[1].y = 10
  # Right Side
  result.quad[2].x = 30
  result.quad[2].y = 20
  # Bottom Side
  result.quad[3].x = 15
  result.quad[3].y = 30
  # 1 - Calculate AABB
  result.box = aabb(result.quad)
  # 2 - Sort Points
  result.quad = sort(result.quad, result.box)
  echo result.quad
  # 3 - Clip and Define Scanlines
  var line: NLine
  # Scanline Left Side
  line.a = result.quad[0]; line.b = result.quad[1]
  if line.clip(result.quad[0], result.quad[1]):
    voxel(line.a, line.b, result.sl)

  line.a = result.quad[2]; line.b = result.quad[1]
  if line.clip(result.quad[2], result.quad[1]):
    voxel(line.a, line.b, result.sl)
  # Scanline Right Side
  line.a = result.quad[2]; line.b = result.quad[3]
  if line.clip(result.quad[2], result.quad[3]):
    voxel(line.a, line.b, result.sr)

  line.a = result.quad[0]; line.b = result.quad[3]
  if line.clip(result.quad[0], result.quad[3]):
    voxel(line.a, line.b, result.sr)
  echo result.sl
  echo result.sr
  # Fill Scanline
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
