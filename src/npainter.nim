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
    grid: array[1024, uint8]
    # Hold Point
    pivot: NQuad
    mx, my: float32
  # Test Image Tile
  TTileImage = ref object of GUIWidget
    mx, my: int32
    ox, oy: int32
    canvas: NCanvas
    tex: GLuint
    work: bool
    # Voxel Test
    voxel: VoxelT
  TTMove = object
    x, y: int32
    image: GUITarget

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
      ctx.color if self.grid[cursor] == 1:
        0xFF2f2f7f.uint32
      elif self.grid[cursor] > 1:
        0xFF002f00.uint32
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
  for p in quad: # Sort Using AABB
    if p.y == box.ymax: n[0] = p
    elif p.x == box.xmin: n[1] = p
    elif p.y == box.ymin: n[2] = p
    elif p.x == box.xmax: n[3] = p
  quad = n # Replace to Sorted

# -----------------------------------
# !!! A FAST VOXEL TRAVERSAL SCANLINE
# -----------------------------------

type # Voxel Traversal
  NLane = object
    min, max: int16
  NScanline = object
    # Voxel Count
    n: int32
    # Dimensions
    w, h: int16
    # Position
    x, y: int16
    # X, Y Steps
    sx, sy: int8
    # Voxel Traversal DDA
    dx, dy, error: float32
    # Scanline Lanes Buffer
    lanes: array[64, NLane]

# -- DDA Voxel Traversal
proc line(dda: var NScanline, a, b: NPoint) =
  let # Point Distances
    dx = abs(b.x - a.x)
    dy = abs(b.y - a.y)
    # Floor X Coordinates
    x1 = floor(a.x)
    y1 = floor(a.y)
    # Floor Y Coordinates
    x2 = floor(b.x)
    y2 = floor(b.y)
  # Reset Count
  dda.n = 1
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

proc lane(dda: var NScanline): ptr NLane =
  # Check Current Y Bounds
  if dda.y >= 0 and dda.y < dda.h:
    result = addr dda.lanes[dda.y]

proc left(dda: var NScanline) =
  var lane = dda.lane()
  # Do DDA Loop
  while dda.n > 0:
    # Clamp to Bounds
    if not isNil(lane):
      lane.min = max(dda.x, 0)
    # Next Lane
    if dda.error > 0:
      dda.y += dda.sy
      dda.error -= dda.dx
      # Lookup Lane
      lane = dda.lane()
    else: # Next X
      dda.x += dda.sx
      dda.error += dda.dy
    # Next Voxel
    dec(dda.n)

proc right(dda: var NScanline) =
  var lane = dda.lane()
  # Do DDA Loop
  while dda.n > 0:
    # Clamp to Bounds
    if not isNil(lane):
      lane.max = 
        min(dda.x, dda.w - 1)
    # Next Lane
    if dda.error > 0:
      dda.y += dda.sy
      dda.error -= dda.dx
      # Lookup Lane
      lane = dda.lane()
    else: # Next X
      dda.x += dda.sx
      dda.error += dda.dy
    # Next Voxel
    dec(dda.n)

# --------------------------
# !!! Scanline Prototype Proc
# --------------------------

proc scanline(self: VoxelT) =
  var # Voxel Scanline
    lane: NLane
    dda: NScanline # HEAVY!!!!
    # Vertical Interval
    y1 = floor(self.quad[2].y).int32
    y2 = floor(self.quad[0].y).int32
  # Clamp Intervals
  if y1 < 0: y1 = 0
  if y2 >= 32: y2 = 31
  # Clear DDA / Set Outside
  dda.w = 32; dda.h = 32
  # Calculate Minimun/Left Lanes
  dda.line(self.quad[0], self.quad[1]); dda.left()
  dda.line(self.quad[2], self.quad[1]); dda.left()
  # Calculate Maximun/Right Lanes
  dda.line(self.quad[2], self.quad[3]); dda.right()
  dda.line(self.quad[0], self.quad[3]); dda.right()
  # Do Scanline of Lanes
  while y1 <= y2:
    lane = dda.lanes[y1]
    #echo lane.repr
    while lane.min <= lane.max:
      # Fill Auxiliar Grid
      self.grid[y1 shl 5 + lane.min] += 1
      inc(lane.min) # Next Voxel
    inc(y1) # Next Lane

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
  result.flags = wMouse
  result.kind = wgFrame
  result.minimum(256, 256)
  # Left Side
  result.quad[0].x = -4
  result.quad[0].y = 8
  # Top Side
  result.quad[1].x = 8
  result.quad[1].y = -4
  # Right Side
  result.quad[2].x = 32
  result.quad[2].y = 10
  # Bottom Side
  result.quad[3].x = 8
  result.quad[3].y = 32
  # 1 - Calculate AABB
  sort(result.quad, result.quad.aabb)
  # 3 - Do Scanline
  result.scanline()

proc sum(a: NQuad, x, y: float32): NQuad =
  for i in 0..3:
    result[i].x = a[i].x + x
    result[i].y = a[i].y + y
  echo result.repr

proc cb_move_voxel(g: pointer, w: ptr GUITarget) =
  let self = cast[VoxelT](w[])
  zeroMem(addr self.grid, sizeof(self.grid))
  sort(self.quad, self.quad.aabb)
  self.scanline()

method event(self: VoxelT, state: ptr GUIState) =
  if state.kind == evMouseClick:
    self.mx = float32 state.mx
    self.my = float32 state.my
    self.pivot = self.quad
  elif self.test(wGrab):
    self.quad = 
      sum(self.pivot, 
        (float32(state.mx) - self.mx) / 16, 
        (float32(state.my) - self.my) / 16)
    var t = self.target
    pushCallback(cb_move_voxel, t)

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
  result.flags = wMouse
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

proc cb_point(g: pointer, data: ptr TTMove) =
  let self = cast[TTileImage](data.image)
  var b, c, d: float32
  self.canvas[4].x = data.x
  self.canvas[4].y = data.y
  self.canvas.stencil(self.canvas[4][])
  b = cpuTime()
  self.canvas.composite()
  c = cpuTime()
  self.refresh()
  d = cpuTime()
  echo "composite: ", c - b, "  upload: ", d - c
  self.work = false

method event(self: TTileImage, state: ptr GUIState) =
  if state.kind == evMouseClick:
    if (state.mods and ShiftMod) == 0:
      self.mx = state.mx; self.my = state.my
      self.ox = self.canvas[4].x
      self.oy = self.canvas[4].y
    elif self.voxel.test(wVisible):
      self.voxel.close()
    else: # Open On Cursor Position
      self.voxel.open()
      self.voxel.move(state.mx, state.my)
  elif self.test(wGrab):
    if not self.work:
      var t = TTMove(
        x: self.ox + state.mx - self.mx,
        y: self.oy + state.my - self.my,
        image: self.target)
      pushCallback(cb_point, t)
      self.work = true

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
  if win.open(root):
    while true:
      win.handleEvents() # Input
      if win.handleSignals(): break
      win.handleTimers() # Timers
      # Render Main Program
      glClearColor(0.6, 0.6, 0.6, 1.0)
      glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
      # Render GUI
      win.render()
  # Close Window
  win.close()
