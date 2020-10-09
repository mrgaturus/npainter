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
from omath import Value, interval, toFloat
from gui/widgets/slider import newSlider
import painter/[
  canvas, 
  voxel, 
  view,
  trash
]

import nimPNG

# LOAD SSE4.1
{.passC: "-msse4.1".}

# Triangle Raster
{.compile: "painter/triangle.c".}
type
  RPoint = object
    x, y: float32
  RTriangle = object
    p: array[3, RPoint]
    # Parameters
    u: array[3, float32]
    v: array[3, float32]


proc rasterize(pixels, mask: cstring, stride: int32, v: var RTriangle, xmin, ymin, xmax, ymax: int32) {.importc, cdecl.}

type
  # Voxel Transversal 32x32
  NMatrix = array[9, float32]
  NTracking = object
    cx, cy: float32
    x, y: float32
    s, o: float32
  TrackMode = enum
    mTranslate, mScale, mRotate
  VoxelT = ref object of GUIWidget
    # Test Matrix
    mat, mat_inv: NMatrix
    track, hold: NTracking
    hold_o: float32
    # Quad
    pivot, pivot_inv, quad, quad_inv: NQuad
    dda: NScanline
    # Test Grid
    grid: array[1024, uint8]
    # Hold Point
    mx, my: float32
    mode: TrackMode
    view: ptr NCanvasView
  # Test Image Tile
  TTileImage = ref object of GUIWidget
    mx, my: int32
    ox, oy: int32
    val: Value
    canvas: NCanvas
    engine: ptr NTrashEngine
    hold_o: float32
    mode: TrackMode
    tex: GLuint
    tex_sw: GLuint
    work: bool
    # Voxel Test
    voxel: VoxelT

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
      #ctx.fill(r.rect)
      # Next Grid Pos
      inc(cursor); r.x += 16
    r.x = self.rect.x
    r.y += 16 # Next Row
  # Draw Lines of Quad
  ctx.color(uint32 0xFF232323)
  ctx.fill rect(
    self.rect.x, self.rect.y, 16 * 16, 16 * 16
  )
  ctx.color(0xFF00FFFF'u32)
  ctx.line rect(
    self.rect.x, self.rect.y, 16 * 16, 16 * 16
  ), 1
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
  # Draw Lines of Quad Inverse
  #let p = point(self.rect.x, self.rect.y)
  var rect = GUIRect(
    x: 0, y: 0,
    w: 16 * 16, h: 16 * 16)
  ctx.push(rect)
  # Draw Background
  ctx.color(uint32 0xFF232323)
  ctx.triangle(
    point(self.quad_inv[0].x * 16, self.quad_inv[0].y * 16),
    point(self.quad_inv[1].x * 16, self.quad_inv[1].y * 16),
    point(self.quad_inv[2].x * 16, self.quad_inv[2].y * 16)
  )
  ctx.triangle(
    point(self.quad_inv[2].x * 16, self.quad_inv[2].y * 16),
    point(self.quad_inv[3].x * 16, self.quad_inv[3].y * 16),
    point(self.quad_inv[0].x * 16, self.quad_inv[0].y * 16)
  )
  ctx.color(0xFF00FFFF'u32)
  # Draw Lines
  ctx.line(
    point(self.quad_inv[0].x * 16, self.quad_inv[0].y * 16),
    point(self.quad_inv[1].x * 16, self.quad_inv[1].y * 16)
  )
  ctx.line(
    point(self.quad_inv[1].x * 16, self.quad_inv[1].y * 16),
    point(self.quad_inv[2].x * 16, self.quad_inv[2].y * 16)
  )
  ctx.line(
    point(self.quad_inv[2].x * 16, self.quad_inv[2].y * 16),
    point(self.quad_inv[3].x * 16, self.quad_inv[3].y * 16)
  )
  ctx.line(
    point(self.quad_inv[3].x * 16, self.quad_inv[3].y * 16),
    point(self.quad_inv[0].x * 16, self.quad_inv[0].y * 16)
  )
  ctx.pop()
  ctx.color(high uint32)
  ctx.line rect(
    0, 0, 16 * 16, 16 * 16
  ), 1

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
proc test_scanline(self: VoxelT) =
  self.dda.scanline(self.quad, 1)
  # Fill Grid
  for x, y in self.dda.voxels:
    self.grid[y shl 5 + x] += 1

proc test_mat(self: VoxelT) =
  mat3_canvas(self.mat, 
    self.track.cx, self.track.cy,
    self.track.x, self.track.y,
    self.track.s, self.track.o)
  mat3_canvas_inv(self.mat_inv,
    self.track.cx, self.track.cy,
    self.track.x, self.track.y, 
    self.track.s, self.track.o)
  # Perform Quad Transform
  self.quad = self.pivot
  for p in mitems(self.quad):
    p.vec2_mat3(self.mat)
  # Perform Quad Inverse Transfrom
  self.quad_inv = self.pivot
  for p in mitems(self.quad_inv):
    p.vec2_mat3(self.mat_inv)
  # Set Transform
  var mat, mat_inv: NMatrix
  mat3_canvas(mat, 
    512, 300,
    self.track.x * 16, self.track.y * 16,
    self.track.s, self.track.o)
  mat3_canvas_inv(mat_inv,
    512, 300,
    self.track.x * 16, self.track.y * 16, 
    self.track.s, self.track.o)
  self.view[].transform(addr mat_inv[0])
  self.view[].clear()
  for y in 0..<4i32:
    for x in 0..<8i32: 
      self.view[].add(x, y)
  #self.view[].add(1, 0)
  #self.view[].add(1, 1)
  #self.view[].add(1, 2)
  #self.view[].add(1, 3)
  self.view[].copy()

proc newVoxelT(): VoxelT =
  new result # Alloc
  result.flags = wMouse
  result.kind = wgFrame
  result.minimum(256, 256)
  # ! Scale Allways 1
  result.track.s = 1
  # Left Side
  result.pivot[0].x = 0
  result.pivot[0].y = 0
  # Top Side
  result.pivot[1].x = 16
  result.pivot[1].y = 0
  # Right Side
  result.pivot[2].x = 16
  result.pivot[2].y = 16
  # Bottom Side
  result.pivot[3].x = 0
  result.pivot[3].y = 16
  # Inverted Quad
  # Left Side
  result.pivot_inv[0].x = 0
  result.pivot_inv[0].y = 0
  # Top Side
  result.pivot_inv[1].x = 16
  result.pivot_inv[1].y = 0
  # Right Side
  result.pivot_inv[2].x = 16
  result.pivot_inv[2].y = 16
  # Bottom Side
  result.pivot_inv[3].x = 0
  result.pivot_inv[3].y = 16
  # Scale
  result.track.cx = 8
  result.track.cy = 8
  # 1 - Perform Scanline
  result.quad = result.pivot
  result.quad_inv = result.pivot_inv
  result.dda.dimensions(32, 32)
  result.test_scanline()

#proc sum(a: NQuad, x, y: float32): NQuad =
#  for i in 0..3:
#    result[i].x = a[i].x + x
#    result[i].y = a[i].y + y

proc translate(self: VoxelT, x, y: float32) =
  self.track.x = self.hold.x + x
  self.track.y = self.hold.y + y

proc scale(self: VoxelT, s: float32) =
  self.track.s = self.hold.s - (s / 10)
  if self.track.s < 0.1:
    self.track.s = 0.1

proc rotate(self: VoxelT, o: float32) =
  self.track.o = self.hold.o + o
  echo "raw rotation: ", o
  echo "rotation: ", self.track.o

var lock = false
proc cb_move_voxel(g: pointer, w: ptr GUITarget) =
  let self = cast[VoxelT](w[])
  zeroMem(addr self.grid, sizeof(self.grid))
  if lock:
    self.test_mat()
    lock = false
  self.test_scanline()
  #sort(self.quad, self.quad.aabb)
  #self.scanline()

from math import arctan2

method event(self: VoxelT, state: ptr GUIState) =
  if state.kind == evMouseClick:
    self.mx = float32 state.mx
    self.my = float32 state.my
    self.hold = self.track
    # Track Mode
    if (state.mods and ShiftMod) == ShiftMod:
      self.mode = mScale
    elif (state.mods and CtrlMod) == CtrlMod:
      self.mode = mRotate
      let # Obviusly will be cleaned
        c = point(self.rect.w shr 1, self.rect.h shr 1)
        p = point(state.mx - self.rect.x, state.my - self.rect.y)
      self.hold_o = arctan2(c.y - p.y, c.x - p.x)
    else: self.mode = mTranslate
  if state.kind == evMouseRelease: discard
  elif self.test(wGrab):
    case self.mode
    of mTranslate:
      translate(self,
        (float32(state.mx) - self.mx) / 16, 
        (float32(state.my) - self.my) / 16)
    of mScale:
      scale(self, (float32(state.my) - self.my) / 16)
    of mRotate:
      let # Obviusly will be cleaned
        c = point(self.rect.w shr 1, self.rect.h shr 1)
        p = point(state.mx - self.rect.x, state.my - self.rect.y)
      rotate(self, arctan2(c.y - p.y, c.x - p.x) - self.hold_o)
    var t = self.target
    if not lock:
      pushCallback(cb_move_voxel, t)
      lock = true

# -----------------
# TEST TILED CANVAS
# -----------------

method draw(self: TTileImage, ctx: ptr CTXRender) =
  ctx.color(uint32 0xFF232323)
  var r = rect(self.rect.x, self.rect.y, 
    self.canvas.cw, self.canvas.ch)
  # Draw Rect
  #ctx.fill(r)
  ctx.color(high uint32)
  ctx.texture(rect(0,0,2048,2048), self.tex)
  r = rect(80, 80, 512, 512)
  ctx.fill(r)
  ctx.texture(r, self.tex_sw)

proc newTTileImage(w, h: int16): TTileImage =
  new result # Alloc Widget
  result.flags = wMouse
  result.canvas = newCanvas(w, h)
  # Create new voxel
  result.voxel = newVoxelT()
  result.voxel.geometry(0, 0, 512, 512)

method event(self: TTileImage, state: ptr GUIState) =
  if self.test(wGrab):
    #let
    #  x = state.mx.float32 / 512 * 2048
    #  y = (512 - state.my).float32 / 512 * 2048
    let
      x = state.mx.float32
      y = 2048 - state.my.float32
    self.engine[].begin()
    glEnable(GL_BLEND)
    glBlendEquation(GL_FUNC_ADD)
    glBlendFuncSeparate(GL_DST_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA)
    self.engine[].transform(x,y,self.val.toFloat,0)
    self.engine[].draw()
    self.engine[].finish()

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
      
proc point(s: var RTriangle, i: int32, x, y, u, v: float32) =
  s.p[i] = RPoint(x: x, y: y)
  s.u[i] = u; s.v[i] = v

when isMainModule:
  var # Create Window and GUI
    win = newGUIWindow(1024, 600, nil)
    eye = newCanvasView()
    engine = newTrashEngine()
    root = newTTileImage(1024, 1024)
  # Reload Canvas Texture
  #root.clear(0xFF0000FF'u32)
  root.canvas.add()
  root.canvas.add()
  root.canvas.add()
  root.canvas.add()
  root.canvas.add()
  root.voxel.view = addr eye
  eye.viewport(1024, 600)
  eye.target(addr root.canvas)
  eye.unit(1) # Scale 1 For Now
  # Set Proyection
  block:
    var mat: NMatrix
    mat3_canvas(mat, 512, 300, 10, 10, 1.5, 0.2)
    eye.transform(addr mat[0])
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
  root.canvas.stencil(root.canvas[0][])
  root.canvas.composite()
  eye.clear()
  eye.add(1, 1)
  eye.copy()
  # Configure Engine
  engine.begin()
  glEnable(GL_BLEND)
  glBlendEquation(GL_FUNC_ADD)
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  engine.test()
  engine.clear()
  engine.transform(1024,1024,1,0)
  engine.draw()
  engine.transform(980,980,1,0)
  engine.draw()
  engine.finish()
  # Test SDF Alpha
  var p = loadPNG32("sdf.png")
  var coso: seq[uint8]
  coso.setLen(p.width*p.height)
  var i = 0
  while i < p.width*p.height:
    coso[i] = p.data[i * 4].uint8
    i += 1
  engine.mask(cast[pointer](addr coso[0]))
  # --------
  root.tex = engine.tex
  root.engine = addr engine
  block: # Slider
    root.val.interval(0, 1)
    let slider = newSlider(addr root.val, 4)
    slider.geometry(20, 20, 500, slider.hint.h)
    root.add slider
  # Test Software Rasterizer
  var pixels: seq[uint32]
  pixels.setLen(1024*1024)
  var triangle: RTriangle
  const SCALE = 1024
  when defined(benchmark):
    from times import cpuTime
    let tt = cpuTime() + 1
    var count: int32
    while cpuTime() < tt:
      triangle.point(0, 0, 0, 0, 0)
      triangle.point(1, SCALE, 0, 1, 0)
      triangle.point(2, SCALE, SCALE, 1, 1)
      rasterize(cast[cstring](addr pixels[0]), cast[cstring](addr coso[0]), SCALE, triangle, 0, 0, SCALE, SCALE)
      triangle.point(0, SCALE, SCALE, 1, 1)
      triangle.point(1, 0, SCALE, 0, 1)
      triangle.point(2, 0, 0, 0, 0)
      rasterize(cast[cstring](addr pixels[0]), cast[cstring](addr coso[0]), SCALE, triangle, 0, 0, SCALE, SCALE)
      inc count
    echo "CPU Brush Engine FPS: ", count
  else:
    triangle.point(0, 0, 0, 0, 0)
    triangle.point(1, SCALE, 0, 1, 0)
    triangle.point(2, SCALE, SCALE, 1, 1)
    rasterize(cast[cstring](addr pixels[0]), cast[cstring](addr coso[0]), SCALE, triangle, 0, 0, SCALE, SCALE)
    triangle.point(0, SCALE, SCALE, 1, 1)
    triangle.point(1, 0, SCALE, 0, 1)
    triangle.point(2, 0, 0, 0, 0)
    rasterize(cast[cstring](addr pixels[0]), cast[cstring](addr coso[0]), SCALE, triangle, 0, 0, SCALE, SCALE)
  # Generate Texture
  glGenTextures(1, addr root.tex_sw)
  glBindTexture(GL_TEXTURE_2D, root.tex_sw)
  glTexImage2D(GL_TEXTURE_2D, 0, cast[GLint](GL_RGBA8), 
    SCALE, SCALE, 0, GL_RGBA, GL_UNSIGNED_BYTE, addr pixels[0])
  # Set Mig/Mag Filter
  glTexParameteri(GL_TEXTURE_2D, 
    GL_TEXTURE_MIN_FILTER, cast[GLint](GL_LINEAR_MIPMAP_NEAREST))
  glTexParameteri(GL_TEXTURE_2D, 
    GL_TEXTURE_MAG_FILTER, cast[GLint](GL_NEAREST))
  glGenerateMipmap(GL_TEXTURE_2D)
  glBindTexture(GL_TEXTURE_2D, 0)
  # Run GUI Program
  if win.open(root):
    while true:
      win.handleEvents() # Input
      if win.handleSignals(): break
      win.handleTimers() # Timers
      # Render Main Program
      glClearColor(0.6, 0.6, 0.8, 1.0)
      glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
      # Render GUI
      eye.render()
      win.render()
  # Close Window
  win.close()
