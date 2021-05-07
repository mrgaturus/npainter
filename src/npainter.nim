from math import floor
import gui/[window, widget, render, event, signal]
import libs/gl
import nimPNG

# -------------------------
# Import C Code of Triangle
# -------------------------

{.compile: "wip/distort/sample.c".}
{.compile: "wip/distort/triangle.c".}
{.compile: "wip/distort/rasterize.c".}
{.compile: "wip/distort/surface.c".}

{.push header: "wip/distort/distort.h".}

type
  NTriangleFunc = distinct pointer
  NTriangleEquation {.importc: "equation_t".} = object
  NTriangleVertex {.importc: "vertex_t".} = object
    x, y, u, v: cfloat
  NTriangle = # Pass as Pointer
    array[3, NTriangleVertex]
  NTriangleDerivative {.importc: "derivative_t".} = object
  NTriangleBinning {.importc: "binning_t".} = object
  NTriangleSampler {.importc: "sampler_t".} = object
    # SW, SH -> Repeat Size
    # W, H -> Texture Size
    sw, sh, w, h: cint
    buffer: ptr cshort
    # Sampler Func
    fn: NTriangleFunc
  NTriangleRender {.importc: "fragment_t".} = object
    x, y, w, h: cint
    # Source Pixels Sampler
    sampler: ptr NTriangleSampler
    # Target Pixels
    dst_w, dst_h: cint
    dst: ptr cshort
  # -------------------------------------------
  NSurfaceVec2D {.importc: "vec2_t".} = object
    x, y: cfloat # Vector2 is only relevant here
  NSurfaceBilinear {.importc: "perspective_t".} = object
  NSurfaceCatmull {.importc: "catmull_t".} = object

{.push importc.}

# Pixel Resampling Function Pointers
proc sample_nearest(render: ptr NTriangleRender, u, v: cfloat) {.used.}
proc sample_bilinear(render: ptr NTriangleRender, u, v: cfloat) {.used.}
proc sample_bicubic(render: ptr NTriangleRender, u, v: cfloat) {.used.}

# Triangle Equation
proc eq_winding(v: ptr NTriangle): int32
proc eq_calculate(eq: ptr NTriangleEquation, v: ptr NTriangle)
proc eq_gradient(eq: ptr NTriangleEquation, v: ptr NTriangle)
proc eq_derivative(eq: ptr NTriangleEquation, dde: ptr NTriangleDerivative)

# Triangle Binning, Multiply By A Power Of Two
proc eq_binning(eq: ptr NTriangleEquation, bin: ptr NTriangleBinning, shift: cint)
# Triangle Binning Steps
proc eb_step_xy(bin: ptr NTriangleBinning, x, y: cint)
proc eb_step_x(bin: ptr NTriangleBinning)
proc eb_step_y(bin: ptr NTriangleBinning)
# Triangle Binning Trivially Count
proc eb_check(bin: ptr NTriangleBinning): int32

# Triangle Equation Realtime Rendering
proc eq_partial(eq: ptr NTriangleEquation, render: ptr NTriangleRender) {.gcsafe.}
proc eq_full(eq: ptr NTriangleEquation, render: ptr NTriangleRender) {.gcsafe.}
# Triangle Equation Rendering Subpixel Antialiasing Post-Procesing
proc eq_partial_subpixel(eq: ptr NTriangleEquation, dde: ptr NTriangleDerivative, render: ptr NTriangleRender)
proc eq_full_subpixel(eq: ptr NTriangleEquation, dde: ptr NTriangleDerivative, render: ptr NTriangleRender)

# --------------------------------------------
proc perspective_calc(surf: ptr NSurfaceBilinear, v: ptr NSurfaceVec2D, fract: cfloat)
proc perspective_evaluate(surf: ptr NSurfaceBilinear, p: ptr NTriangleVertex)

proc catmull_surface_calc(surf: ptr NSurfaceCatmull, c: ptr NSurfaceVec2D, w, h: cint)
proc catmull_surface_evaluate(surf: ptr NSurfaceCatmull, p: ptr NTriangleVertex)

{.pop.} # -- End Importing Procs

{.pop.} # -- End distort.h

# ---------------------
# Triangle Object Types
# ---------------------

type
  NImage = object
    w, h: int32
    buffer: seq[int16] 
  NTriangleAABB = object
    xmin, ymin, xmax, ymax: float32
  NTriangleBlockAABB = object
    xmin, ymin, xmax, ymax: int32
  NTriangleBlockCMD = object
    x, y, len: int32
    # FINAL: Pointer To An Object Directly
    index: ptr UncheckedArray[uint16]
    # Image Target And Source
    buffer: ptr UncheckedArray[int16]
    sampler: ptr NTriangleSampler
    # Triangle Rasterization Proc
    fn: NTriangleRasterizeFunc
  NTriangleRasterizeFunc = 
    proc (self: GUIDistort, v: var NTriangle)
  GUIDistort = ref object of GUIWidget
    # Triangle Preparation
    equation: NTriangleEquation
    sampler: NTriangleSampler
    # Image Source
    source: NImage
    # 15bit Pixel Buffer
    buffer: array[1280*720*4, int16]
    buffer_copy: array[1280*720*4, uint8]
    # Control Points
    cp, cp_aux: seq[NSurfaceVec2D]
    cp_w, cp_h, cp_grab: cint
    # Triangle Mesh
    mesh_n, mesh_m: cint
    mesh_res, mesh_s: cint
    # Triangle Mesh Buffers
    mesh_e: seq[uint16]
    mesh: seq[NTriangleVertex]
    # Triangle Mesh Rendering Proc
    mesh_fn: NTriangleRasterizeFunc
    # Surface Interpolators
    bilinear: NSurfaceBilinear
    catmull: NSurfaceCatmull
    # Triangle Blocks
    blocks: seq[NTriangleBlockCMD]
    blocks_aabb: NTriangleBlockAABB
    # OpenGL Texture
    tex: GLuint
    # Avoid Flooding
    busy: bool

proc newImage(file: string): NImage =
  let image = loadPNG32(file)
  result.w = cast[int32](image.width)
  result.h = cast[int32](image.height)
  # Set Premultiplied Buffer Size
  let size = result.w * result.h
  setLen(result.buffer, size * 4)
  # Unpack to 16bit Premultiplied
  for p in 0..<size:
    var ch: int32
    let 
      i = p shl 2
      a = cast[int32](image.data[i + 3])
    # Red Color Channel
    ch = cast[int32](
      image.data[i]) * a div 255
    result.buffer[i] = 
      cast[int16]((ch shl 7) or ch)
    # Green Color Channel
    ch = cast[int32](
      image.data[i + 1]) * a div 255
    result.buffer[i + 1] = 
      cast[int16]((ch shl 7) or ch)
    # Blue Color Channel
    ch = cast[int32](
      image.data[i + 2]) * a div 255
    result.buffer[i + 2] = 
      cast[int16]((ch shl 7) or ch)
    # Alpha Channel, Unmodified
    result.buffer[i + 3] = 
      cast[int16]((a shl 7) or a)

# -------------------------------
# AXIS ALIGNED BOUNDING BOX PROCS
# -------------------------------

proc aabb(v: NTriangle): NTriangleAABB =
  var # Iterator
    i = 1
    p = v[0]
  # Set XMax/XMin
  result.xmin = p.x
  result.xmax = p.x
  # Set YMax/YMin
  result.ymin = p.y
  result.ymax = p.y
  # Build AABB
  while i < 3:
    p = v[i]
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

proc toBlocks(box: NTriangleAABB, shift: cint): NTriangleBlockAABB =
  result.xmin = int32(box.xmin) shr shift
  result.xmax = int32(box.xmax) shr shift
  result.ymin = int32(box.ymin) shr shift
  result.ymax = int32(box.ymax) shr shift

proc expand(current: var NTriangleBlockAABB, box: NTriangleBlockAABB) =
  current.xmin = min(current.xmin, box.xmin)
  current.ymin = min(current.ymin, box.ymin)
  current.xmin = max(current.xmax, box.xmax)
  current.ymin = max(current.ymax, box.ymax)

# -------------------------------
# Copy to 8-Bit Color Buffer Proc
# -------------------------------

proc copy(self: GUIDistort, x, y, w, h: int) =
  var
    cursor_src = 
      (y * 1280 + x) shl 2
    cursor_dst: int
  # Convert to RGBA8
  for yi in 0..<h:
    for xi in 0..<w:
      self.buffer_copy[cursor_dst] = 
        cast[uint8](self.buffer[cursor_src] shr 7)
      self.buffer_copy[cursor_dst + 1] = 
        cast[uint8](self.buffer[cursor_src + 1] shr 7)
      self.buffer_copy[cursor_dst + 2] = 
        cast[uint8](self.buffer[cursor_src + 2] shr 7)
      self.buffer_copy[cursor_dst + 3] =
        cast[uint8](self.buffer[cursor_src + 3] shr 7)
      # Next Pixel
      cursor_src += 4; cursor_dst += 4
    # Next Row
    cursor_src += (1280 - w) shl 2
  # Copy To Texture
  glBindTexture(GL_TEXTURE_2D, self.tex)
  glTexSubImage2D(GL_TEXTURE_2D, 0, 
    cast[int32](x), cast[int32](y), cast[int32](w), cast[int32](h),
    GL_RGBA, GL_UNSIGNED_BYTE, addr self.buffer_copy[0])
  glBindTexture(GL_TEXTURE_2D, 0)

# ----------------------------------
# TRIANGLE ANTIALIASED RASTERIZATION
# ----------------------------------

proc bin_subpixel(eq: var NTriangleEquation, render: var NTriangleRender, aabb: NTriangleBlockAABB) =
  var 
    bin: NTriangleBinning
    dde: NTriangleDerivative
  # Calculate Triangle Derivative
  eq_derivative(addr eq, addr dde)
  # Calculate Triangle Binning
  eq_binning(addr eq, addr bin, 3)
  # Get Tiled Positions
  let
    x1 = aabb.xmin
    x2 = aabb.xmax
    y1 = aabb.ymin
    y2 = aabb.ymax
  var count: cint
  # Set Render Size to 8
  render.w = 8; render.h = 8
  # Locate Binning at X Y
  eb_step_xy(addr bin, x1, y1)
  # Iterate Each Tile
  for y in y1..y2:
    for x in x1..x2:
      count = eb_check(addr bin)
      if count > 0:
        render.x = x shl 3
        render.y = y shl 3
        if count == 3: # Full or Partial
          eq_full_subpixel(addr eq, 
            addr dde, addr render)
        else: eq_partial_subpixel(addr eq, 
          addr dde, addr render)
      # Step X Equations
      eb_step_x(addr bin)
    # Step Y Equations
    eb_step_y(addr bin)

# - MAIN SUBPIXEL RENDERING -
proc rasterize_subpixel(self: GUIDistort, v: var NTriangle) =
  if eq_winding(addr v) != 0:
    # Calculate Edge Equation with UV Equation
    eq_calculate(addr self.equation, addr v)
    eq_gradient(addr self.equation, addr v)
    # Prepare Triangle Rendering
    var render: NTriangleRender
    render.dst_w = 1280
    render.dst_h = 720
    # Subpixel Rendering Buffers
    render.dst = addr self.buffer[0]
    render.sampler = addr self.sampler
    # Render As Blocks of 8x8
    bin_subpixel(self.equation, render, 
      v.aabb.toBlocks 3)

# -------------------------------
# TRIANGLE REALTIME RASTERIZATION
# -------------------------------

proc bin_fast(eq: var NTriangleEquation, render: var NTriangleRender, aabb: NTriangleBlockAABB) =
  var bin: NTriangleBinning
  # Calculate Triangle Binning
  eq_binning(addr eq, addr bin, 3)
  # Get Tiled Positions
  let
    x1 = aabb.xmin
    x2 = aabb.xmax
    y1 = aabb.ymin
    y2 = aabb.ymax
  var count: cint
  # Set Render Size to 8
  render.w = 8; render.h = 8
  # Locate Binning at X Y
  eb_step_xy(addr bin, x1, y1)
  # Iterate Each Tile
  for y in y1..y2:
    for x in x1..x2:
      count = eb_check(addr bin)
      if count > 0:
        render.x = x shl 3
        render.y = y shl 3
        if count == 3: # Full or Partial
          eq_full(addr eq, addr render)
        else: eq_partial(addr eq, addr render)
      # Step X Equations
      eb_step_x(addr bin)
    # Step Y Equations
    eb_step_y(addr bin)

# - MAIN REALTIME RENDERING -
proc rasterize_fast(self: GUIDistort, v: var NTriangle) =
  if eq_winding(addr v) != 0:
    # Calculate Edge Equation with UV Equation
    eq_calculate(addr self.equation, addr v)
    eq_gradient(addr self.equation, addr v)
    # Prepare Triangle Rendering
    var render: NTriangleRender
    render.dst_w = 1280
    render.dst_h = 720
    # Realtime Rendering Buffers
    render.dst = addr self.buffer[0]
    render.sampler = addr self.sampler
    # Render As Blocks of 8x8
    bin_fast(self.equation, render, 
      v.aabb.toBlocks 3)

# ----------------------------------
# TRIANGLE MESH ELEMENTS CALCULATION
# ----------------------------------

proc mesh_elements_quad(self: GUIDistort; idx, ox, oy, n, s: int): int =
  result = idx
  var 
    xx, yy: int
  for y in 0..<n:
    for x in 0..<n:
      xx = ox + x
      yy = oy + y
      let
        top = cast[uint16](yy * s + xx)
        bot = top + cast[uint16](s)
      # Left Half Triangle
      self.mesh_e[result + 0] = top
      self.mesh_e[result + 1] = top + 1
      self.mesh_e[result + 2] = bot
      # Right Half Triangle
      self.mesh_e[result + 3] = bot
      self.mesh_e[result + 4] = top + 1
      self.mesh_e[result + 5] = bot + 1
      # Next Six Elements
      result += 6

proc mesh_elements(self: GUIDistort) =
  let
    n = self.mesh_n
    m = self.mesh_m
    # Mesh Resolution
    res = self.mesh_res
    # Mesh Buffer Stride
    s = self.mesh_s
    # Step Elements
    next = res * res * 6
  # Alloc Mesh Elements
  setLen(self.mesh_e, 
    next * n * m)
  var
    ox, oy: int
    # Current IDX
    idx: int
  for y in 0..<m:
    for x in 0..<n:
      # Locate Vertex Offset
      ox = x * res; oy = y * res
      # Calculate Mesh Quad Elements
      idx = mesh_elements_quad(self, 
        idx, ox, oy, res, s)

# -----------------------
# TRIANGLE MESH RENDERING
# -----------------------

proc render_mesh(self: GUIDistort) =
  let
    n = len(self.mesh_e) div 3
    fn = self.mesh_fn
  var triangle: NTriangle
  for i in 0..<n:
    # Shorcut For Avoid Repeating
    let cursor = cast[ptr UncheckedArray[uint16]](
      addr self.mesh_e[i * 3])
    triangle[0] = self.mesh[cursor[0]]
    triangle[1] = self.mesh[cursor[1]]
    triangle[2] = self.mesh[cursor[2]]
    # Render Triangle
    fn(self, triangle)
  # Copy Current Buffer
  self.copy(0, 0, 1280, 720)

# ------------------------
# TRIANGLE MESH DEFINITION
# ------------------------

proc reserve(self: GUIDistort; res: cint) =
  let
    # Dimensions
    w = self.cp_w
    h = self.cp_h
    # Grid Dimensions
    cw = w - 1
    ch = h - 1
    # Odd Resolution
    cr = res - 1
    # Triangles
    n = w + cr * cw
    m = h + cr * ch
  # Store Resolution
  self.mesh_res = res
  # Store Dimensions
  self.mesh_n = cw
  self.mesh_m = ch
  # Buffer Stride
  self.mesh_s = n
  # Alloc Mesh Vertexes
  setLen(self.mesh, n * m)
  # Alloc Mesh Elements
  mesh_elements(self)

proc unit(self: GUIDistort) =
  let
    res = self.mesh_res
    # Dimensions
    w = self.cp_w
    h = self.cp_h
    # Grid Dimensions
    cw = w - 1
    ch = h - 1
    # Odd Resolution
    cr = res - 1
    # Triangles
    n = w + cr * cw
    m = h + cr * ch
    # Normalizated Size Steps
    rn = 1.0 / cfloat(n - 1)
    rm = 1.0 / cfloat(m - 1)
    # Image Dimensions
    sw = self.sampler.sw + 2
    sh = self.sampler.sh + 2
  # Initialize As Unitary
  var
    i: int
    rx, ry: float
  for y in 0..<m:
    for x in 0..<n:
      i = y * n + x
      # Calculate Normalized
      rx = cfloat(x) * rn
      ry = cfloat(y) * rm
      # Load Current Vertex
      let v = addr self.mesh[i]
      # Store UV Coordinates
      v.u = cfloat(sw) * rx - 1.0
      v.v = cfloat(sh) * ry - 1.0
      # Store Unit Position
      v.x = rx; v.y = ry

# -------------------------------------
# PERSPECTIVE-BILINEAR MESH CALCULATION
# -------------------------------------

proc perspective_cp(self: GUIDistort, x, y: cint) =
  let
    # Image Dimensions
    sw = self.sampler.sw + 2
    sh = self.sampler.sh + 2
    # Position With Border
    xx = cfloat(x - 1)
    yy = cfloat(y - 1)
    # Position With Offset
    ox = cfloat(x - 1 + sw)
    oy = cfloat(y - 1 + sh)
  # Alloc Control Points
  setLen(self.cp, 4)
  # Set Control Points
  self.cp[0] = NSurfaceVec2D(x: xx, y: yy)
  self.cp[1] = NSurfaceVec2D(x: ox, y: yy)
  self.cp[2] = NSurfaceVec2D(x: ox, y: oy)
  self.cp[3] = NSurfaceVec2D(x: xx, y: oy)
  # Set Control Point Dimensions
  self.cp_w = 2; self.cp_h = 2

proc perspective(self: GUIDistort, fract: cfloat) =
  # Calculate Transformation
  perspective_calc(addr self.bilinear, 
    unsafeAddr self.cp[0], fract)
  # Define Unitary Mesh
  self.unit()
  # Transform Each Point
  for p in mitems(self.mesh):
    # Transform Each Point As Bilinear Transform
    perspective_evaluate(addr self.bilinear, addr p)

# --------------------------------
# CATMULL SURFACE MESH CALCULATION
# --------------------------------

proc catmull_cp(self: GUIDistort, x, y: cint; w, h: cint) =
  let
    rcx = 1.0 / cfloat(w - 1)
    rcy = 1.0 / cfloat(h - 1)
    # Bordered Position
    ox = cfloat(x - 1)
    oy = cfloat(y - 1)
    # Image Dimensions
    sw = self.sampler.sw + 2
    sh = self.sampler.sh + 2
  # Allocate Control Points
  setLen(self.cp, w * h)
  # Decide Higher Side
  let s = w + 3 + (h + 2) * w
  # Allocate Catmull CP Buffer
  setLen(self.cp_aux, s)
  # Locate Each Control Point
  var i: int
  for yy in 0..<h:
    for xx in 0..<w:
      i = yy * w + xx
      # Load Current Control
      let cp = addr self.cp[i]
      # Calculate and Store Each XY Position
      cp.x = ox + cfloat(sw * xx) * rcx
      cp.y = oy + cfloat(sh * yy) * rcy
  # Store Control Points Dimensions
  self.cp_w = w; self.cp_h = h

proc catmull(self: GUIDistort) =
  let 
    # Grid Dimensions
    w = self.cp_w
    h = self.cp_h
    # Grid Stride
    s = h + 2
  # Copy Each Point
  for x in 0..<w:
    for y in 0..<h:
      self.cp_aux[x * s + y + 1] = 
        self.cp[y * w + x]
  # Calculate Transformation
  catmull_surface_calc(addr self.catmull,
    addr self.cp_aux[0], w, h)
  # Define Unitary
  self.unit()
  # Transform Each Point
  for p in mitems(self.mesh):
    # Transform Each Point As Bilinear Transform
    catmull_surface_evaluate(addr self.catmull, addr p)

# -------------------------
# WIDGET MESH TEST CREATION
# -------------------------

proc newDistort(src: string): GUIDistort =
  new result
  # Load Source Image
  result.source = newImage(src)
  # Configure Triangle Sampler
  result.sampler.w = result.source.w
  result.sampler.h = result.source.h
  result.sampler.buffer = addr result.source.buffer[0]
  # Set Function Proc
  result.sampler.fn = cast[NTriangleFunc](sample_nearest)
  result.mesh_fn = rasterize_fast
  # Copy Buffer To Texture
  glGenTextures(1, addr result.tex)
  glBindTexture(GL_TEXTURE_2D, result.tex)
  glTexImage2D(GL_TEXTURE_2D, 0, cast[GLint](GL_RGBA8), 
    1280, 720, 0, GL_RGBA, GL_UNSIGNED_BYTE, addr result.buffer_copy[0])
  # Set Mig/Mag Filter
  glTexParameteri(GL_TEXTURE_2D, 
    GL_TEXTURE_MIN_FILTER, cast[GLint](GL_NEAREST))
  glTexParameteri(GL_TEXTURE_2D, 
    GL_TEXTURE_MAG_FILTER, cast[GLint](GL_NEAREST))
  #glGenerateMipmap(GL_TEXTURE_2D)
  glBindTexture(GL_TEXTURE_2D, 0)
  # Prepare Triangle
  result.flags = wMouse
  result.cp_grab = not 0
  #!!!! Create ThreadPool
  # result.pool = createPool(1)

proc repeat(self: GUIDistort, sw, sh: cfloat) =
  self.sampler.sw = cint floor(
    cfloat(self.sampler.w) * sw)
  self.sampler.sh = cint floor(
    cfloat(self.sampler.h) * sh)

# -----------------------
# WIDGET MESH INTERACTIVE
# -----------------------

proc cb_mesh(g: pointer, w: ptr GUITarget) =
  let self = 
    cast[GUIDistort](w[])
  # Clear Buffer
  zeroMem(addr self.buffer[0],
    self.buffer.len * int16.sizeof)
  # Calculate And Rasterize
  #perspective(self, 1.0)
  catmull(self)
  render_mesh(self)
  # Get Ready
  self.busy = false

method event*(self: GUIDistort, state: ptr GUIState) =
  if self.test(wGrab) and self.cp_grab >= 0:
    # Load Grabbed Control Point
    let cp = addr self.cp[self.cp_grab]
    # Change Position
    cp.x = state.px
    cp.y = state.py
    if not self.busy:
      var target = self.target
      pushCallback(cb_mesh, target)
      # Avoid Event Flooding
      self.busy = true
  elif state.kind == evCursorClick:
    let
      px = state.px
      py = state.py
    var cx, cy: cfloat
    for i, cp in pairs(self.cp):
      cx = cp.x
      cy = cp.y
      if (px < cx + 5.0) and px > (cx - 5.0) and 
        (py < cy + 5.0) and py > (cy - 5.0):
          self.cp_grab = cast[cint](i); break
  elif state.kind == evCursorRelease:
    self.cp_grab = not 0    

method draw(self: GUIDistort, ctx: ptr CTXRender) =
  var r: CTXRect
  ctx.color(uint32 0xFFFFFFFF)
  r = rect(0, 0, 1280, 720)
  ctx.fill(r)
  ctx.color(uint32 0xFFFFFFFF)
  ctx.texture(r, self.tex)
  # Draw Control Points
  ctx.color(uint32 0xFF2f2f2f)
  for cp in self.cp:
    r.x = cp.x - 5.0
    r.xw = cp.x + 5.0
    r.y = cp.y - 5.0
    r.yh = cp.y + 5.0
    ctx.fill(r)
  #ctx.color(self.color)
  #for v in self.quad.v:
  #  r = rect(int32 v.x - 5, int32 v.y - 5, 10, 10)
  #  ctx.fill(r)

# ------------------------
# GUI MAIN WINDOW CREATION
# ------------------------

when isMainModule:
  var # Create Basic Widgets
    win = newGUIWindow(1280, 720, nil)
    root: GUIDistort

  # Create Triangle Vertexs

  # Create Main Widget
  root = newDistort("yuh.png")
  root.repeat(1.0, 1.0)

  catmull_cp(root, 50, 50, 6, 3)
  reserve(root, 8)
  catmull(root)
  root.render_mesh()

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
