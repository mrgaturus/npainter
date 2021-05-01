from math import floor
import gui/[window, widget, render, event, signal]
import libs/gl
import nimPNG

# -------------------------
# Import C Code of Triangle
# -------------------------
{.passC: "-msse4.1".}

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

# Sampling Procs
proc sample_nearest(render: ptr NTriangleRender, u, v: cfloat) {.used.}
proc sample_bilinear(render: ptr NTriangleRender, u, v: cfloat) {.used.}
proc sample_bicubic(render: ptr NTriangleRender, u, v: cfloat) {.used.}

# Triangle Equation
proc eq_winding(v: ptr NTriangle): int32
proc eq_calculate(eq: ptr NTriangleEquation, v: ptr NTriangle)
proc eq_gradient(eq: ptr NTriangleEquation, v: ptr NTriangle)
proc eq_derivative(eq: ptr NTriangleEquation, dde: ptr NTriangleDerivative)

# Triangle Binning
proc eq_binning(eq: ptr NTriangleEquation, bin: ptr NTriangleBinning)
# Triangle Binning Steps
proc eb_step_xy(bin: ptr NTriangleBinning, x, y: cint)
proc eb_step_x(bin: ptr NTriangleBinning)
proc eb_step_y(bin: ptr NTriangleBinning)
# Triangle Binning Trivially Count
proc eb_check(bin: ptr NTriangleBinning): int32

# Triangle Equation Realtime Rendering
proc eq_partial(eq: ptr NTriangleEquation, render: ptr NTriangleRender)
proc eq_full(eq: ptr NTriangleEquation, render: ptr NTriangleRender)
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
  NTriangleAABB = object
    xmin, ymin, xmax, ymax: float32
  NTriangleRasterizeFunc = 
    proc (self: GUIDistort, v: var NTriangle)
  GUIImage = object
    w, h: int32
    buffer: seq[int16] 
  GUIDistort = ref object of GUIWidget
    # Triangle Preparation
    equation: NTriangleEquation
    sampler: NTriangleSampler
    # 15bit Pixel Buffer
    source: GUIImage
    buffer: array[1280*720*4, int16]
    mask, backup: array[1280*720*4, int16]
    buffer_copy: array[1280*720*4, uint8]
    # Control Points
    cp_w, cp_h: int
    cp: seq[NSurfaceVec2D]
    # Triangle Mesh
    mesh_n, mesh_m: cint
    mesh_res, mesh_s: cint
    # Triangle Mesh Buffer & Proc
    mesh: seq[NTriangleVertex]
    mesh_fn: NTriangleRasterizeFunc
    # Surface Interpolators
    bilinear: NSurfaceBilinear
    catmull: NSurfaceCatmull
    catmull_cp: seq[NSurfaceVec2D]
    # OpenGL Texture
    tex: GLuint

proc newImage(file: string): GUIImage =
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

proc interval(render: var NTriangleRender, v: NTriangle) =
  var result: NTriangleAABB
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
  # Set Interval
  render.x = int32(result.xmin)
  render.y = int32(result.ymin)
  render.w = int32(result.xmax) - render.x
  render.h = int32(result.ymax) - render.y

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

proc bin_subpixel(eq: var NTriangleEquation, render: var NTriangleRender) =
  var 
    bin: NTriangleBinning
    dde: NTriangleDerivative
  # Calculate Triangle Derivative
  eq_derivative(addr eq, addr dde)
  # Create New Triangle Binner
  eq_binning(addr eq, addr bin)
  # Get Tiled Positions
  let
    x1 = render.x shr 3
    x2 = (render.x + render.w) shr 3
    y1 = render.y shr 3
    y2 = (render.y + render.h) shr 3
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
    # Set Rendering Interval
    interval(render, v)
    # Render As Binning
    bin_subpixel(self.equation, render)

# -------------------------------
# TRIANGLE REALTIME RASTERIZATION
# -------------------------------

proc bin_fast(eq: var NTriangleEquation, render: var NTriangleRender) =
  var 
    bin: NTriangleBinning
  # Create New Triangle Binner
  eq_binning(addr eq, addr bin)
  # Get Tiled Positions
  let
    x1 = render.x shr 3
    x2 = (render.x + render.w) shr 3
    y1 = render.y shr 3
    y2 = (render.y + render.h) shr 3
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
    # Set Rendering Interval
    interval(render, v)
    # Check AABB and Decide Binning
    bin_fast(self.equation, render)

# -----------------------
# TRIANGLE MESH RENDERING
# -----------------------

proc render_quad(self: GUIDistort; ox, oy, n, s: int) =
  let fn = self.mesh_fn
  var # Walker
    xx, yy: int
    a, b: NTriangle
  for y in 0..<n:
    for x in 0..<n:
      xx = ox + x
      yy = oy + y
      let 
        top = yy * s + xx
        bot = top + s
      a[0] = self.mesh[top]
      a[1] = self.mesh[top + 1]
      a[2] = self.mesh[bot]
      # Left Half Quad
      b[0] = a[2]; b[1] = a[1]
      b[2] = self.mesh[bot + 1]
      # Render Both Triangles
      fn(self, a); fn(self, b)

proc render_mesh(self: GUIDistort) =
  let
    n = self.mesh_n
    m = self.mesh_m
    # Mesh Resolution
    res = self.mesh_res
    # Mesh Buffer Stride
    s = self.mesh_s
  var 
    ox, oy: int
  for y in 0..<m:
    for x in 0..<n:
      # Locate Vertex Offset
      ox = x * res; oy = y * res
      # Render Mesh Quad by Resolution
      render_quad(self, ox, oy, res, s)
  # Copy Current Buffer
  self.copy(0, 0, 1280, 720)

# ------------------------
# TRIANGLE MESH DEFINITION
# ------------------------

proc unit(self: GUIDistort; w, h, res: cint) =
  let
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
  # Alloc Mesh Vertexes
  setLen(self.mesh, n * m)
  # Store Resolution
  self.mesh_res = res
  # Store Dimensions
  self.mesh_n = cw
  self.mesh_m = ch
  # Buffer Stride
  self.mesh_s = n
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
      inc(i) # Next Vertex

proc perspective(self: GUIDistort, controls: array[4, NSurfaceVec2D], fract: cfloat) =
  # Calculate Transformation
  perspective_calc(addr self.bilinear, 
    unsafeAddr controls[0], fract)
  # Define Unitary
  self.unit(2, 2, 32)
  # Transform Each Point
  for p in mitems(self.mesh):
    # Transform Each Point As Bilinear Transform
    perspective_evaluate(addr self.bilinear, addr p)

proc catmull(self: GUIDistort, controls: seq[NSurfaceVec2D], w, h: cint) =
  let s = h + 2
  # Prepare Catmull Buffer
  var cp: seq[NSurfaceVec2D]
  cp.setLen(w + 3 + s * w)
  # Copy Each Point
  for x in 0..<w:
    for y in 0..<h:
      cp[x * s + y + 1] = 
        controls[y * w + x]
  # Store Catmull Buffer
  shallowCopy(self.catmull_cp, cp)
  # Calculate Transformation
  catmull_surface_calc(addr self.catmull,
    addr self.catmull_cp[0], w, h)
  # Define Unitary Quads
  self.unit(w, h, 16)
  # Transform Each Point
  for p in mitems(self.mesh):
    # Transform Each Point As Bilinear Transform
    catmull_surface_evaluate(addr self.catmull, addr p)

# ------------------
# MESH TEST CREATION
# ------------------

proc newDistort(src: string): GUIDistort =
  new result
  # Load Source Image
  result.source = newImage(src)
  # Configure Triangle Sampler
  result.sampler.w = result.source.w
  result.sampler.h = result.source.h
  result.sampler.buffer = addr result.source.buffer[0]
  # Set Function Proc
  result.sampler.fn = cast[NTriangleFunc](sample_bilinear)
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
  #result.verts = v1

proc repeat(self: GUIDistort, sw, sh: cfloat) =
  self.sampler.sw = cint floor(
    cfloat(self.sampler.w) * sw)
  self.sampler.sh = cint floor(
    cfloat(self.sampler.h) * sh)

method draw(self: GUIDistort, ctx: ptr CTXRender) =
  ctx.color(uint32 0xFFFFFFFF)
  #ctx.color(uint32 0xFFFF2f2f)
  var r = rect(0, 0, 1280, 720)
  ctx.fill(r)
  ctx.color(uint32 0xFFFFFFFF)
  ctx.texture(r, self.tex)
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

  #[
  var controls: seq[NSurfaceVec2D]
  controls.setLen(4 * 4)

  controls[0] = NSurfaceVec2D(x: 0, y: 0)
  controls[1] = NSurfaceVec2D(x: 234, y: 0)
  controls[2] = NSurfaceVec2D(x: 468, y: 0)
  controls[3] = NSurfaceVec2D(x: 702, y: 0)

  controls[4] = NSurfaceVec2D(x: 0, y: 234)
  controls[5] = NSurfaceVec2D(x: 600, y: 100)
  controls[6] = NSurfaceVec2D(x: 468, y: 234)
  controls[7] = NSurfaceVec2D(x: 702, y: 234)

  controls[8] = NSurfaceVec2D(x: 0, y: 468)
  controls[9] = NSurfaceVec2D(x: 234, y: 468)
  controls[10] = NSurfaceVec2D(x: 468, y: 468)
  controls[11] = NSurfaceVec2D(x: 702, y: 468)

  controls[12] = NSurfaceVec2D(x: 0, y: 702)
  controls[13] = NSurfaceVec2D(x: 234, y: 702)
  controls[14] = NSurfaceVec2D(x: 468, y: 702)
  controls[15] = NSurfaceVec2D(x: 702, y: 702)

  #for p in mitems(controls):
  #  p.x += 10; p.y += 10

  catmull(root, controls, 4, 4)
  shallowCopy(root.cp, controls)

  ]#

  # #[
  var quad: array[4, NSurfaceVec2D]
  #quad[0] = NSurfaceVec2D(x: 500, y: 10)
  #quad[1] = NSurfaceVec2D(x: 100, y: 500)
  #quad[2] = NSurfaceVec2D(x: 1280, y: 720)
  #quad[3] = NSurfaceVec2D(x: 10, y: 100)

  #quad[0] = NSurfaceVec2D(x: 100, y: 10)
  #quad[1] = NSurfaceVec2D(x: 120, y: 600)
  #quad[2] = NSurfaceVec2D(x: 1280, y: 720)
  #quad[3] = NSurfaceVec2D(x: 110, y: 10)

  quad[0] = NSurfaceVec2D(x: 0, y: 0)
  quad[1] = NSurfaceVec2D(x: 702, y: 0)
  quad[2] = NSurfaceVec2D(x: 702, y: 702)
  quad[3] = NSurfaceVec2D(x: 0, y: 702)

  root.perspective(quad, 1.0)
  # ]#
  root.render_mesh()
  
  #root.render_mesh_subpixel()

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
