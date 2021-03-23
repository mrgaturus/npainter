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
  NTriangleRender {.importc: "fragment_t".} = object
    x, y, w, h: cint
    # Source Pixels
    src_w, src_h: cint
    src: ptr cshort
    # Target Pixels
    dst_w, dst_h: cint
    # Target Pointers
    dst, mask: ptr cshort
    # Sampler Func
    sample_fn: NTriangleFunc

{.push importc.}
# Sampling Procs
proc sample_nearest(render: ptr NTriangleRender, u, v: cfloat) {.used.}
proc sample_bilinear(render: ptr NTriangleRender, u, v: cfloat) {.used.}
proc sample_bicubic(render: ptr NTriangleRender, u, v: cfloat) {.used.}

# Triangle Equation
proc eq_winding(v: ptr NTriangle): int32
proc eq_calculate(eq: ptr NTriangleEquation, v: ptr NTriangle)
proc eq_derivative(eq: ptr NTriangleEquation, dde: ptr NTriangleDerivative)

# Triangle Binning
proc eq_binning(eq: ptr NTriangleEquation, bin: ptr NTriangleBinning)
# Triangle Binning Steps
proc eb_step_xy(bin: ptr NTriangleBinning, x, y: cfloat)
proc eb_step_x(bin: ptr NTriangleBinning)
proc eb_step_y(bin: ptr NTriangleBinning)
# Triangle Binning Trivially Count
proc eb_check(bin: ptr NTriangleBinning): int32

# Triangle Equation Realtime Rendering
proc eq_partial(eq: ptr NTriangleEquation, render: ptr NTriangleRender)
proc eq_full(eq: ptr NTriangleEquation, render: ptr NTriangleRender)
proc eq_partial_subpixel(eq: ptr NTriangleEquation, dde: ptr NTriangleDerivative, render: ptr NTriangleRender)
proc eq_full_subpixel(eq: ptr NTriangleEquation, dde: ptr NTriangleDerivative, render: ptr NTriangleRender)
{.pop.}

{.pop.}

# ---------------------
# Triangle Object Types
# ---------------------

type
  NTriangleAABB = object
    xmin, ymin, xmax, ymax: float32
  GUIImage = object
    w, h: int32
    buffer: seq[int16] 
  GUIDistort = ref object of GUIWidget
    verts: NTriangle
    # Triangle Preparation
    equation: NTriangleEquation
    render: NTriangleRender
    # 15bit Pixel Buffer
    source: GUIImage
    buffer: array[1280*720*4, int16]
    mask, backup: array[1280*720*4, int16]
    # 15 bit to 8 bit Buffer
    buffer_copy: array[1280*720*4, uint8]
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

proc render_subpixel(eq: var NTriangleEquation, render: var NTriangleRender) =
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
  eb_step_xy(addr bin, cfloat x1, cfloat y1)
  # Iterate Each Tile
  for y in y1..y2:
    for x in x1..x2:
      count = eb_check(addr bin)
      if count > 0:
        render.x = x shl 3
        render.y = y shl 3
        if count == 3: # Full or Partial
          eq_full_subpixel(addr eq, addr dde, addr render)
        else: eq_partial_subpixel(addr eq, addr dde, addr render)
      # Step X Equations
      eb_step_x(addr bin)
    # Step Y Equations
    eb_step_y(addr bin)

proc render(eq: var NTriangleEquation, render: var NTriangleRender) =
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
  eb_step_xy(addr bin, cfloat x1, cfloat y1)
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

proc render(self: GUIDistort, v: var NTriangle) =
  if eq_winding(addr v) != 0:
    eq_calculate( # Calculate Triangle Equation
      addr self.equation, addr v)
    # Prepare Triangle Rendering
    var render: NTriangleRender
    render.dst_w = 1280
    render.dst_h = 720
    render.dst = addr self.buffer[0]
    echo cast[uint](render.dst)
    # Source Image
    render.src_w = self.source.w
    render.src_h = self.source.h
    render.src = addr self.source.buffer[0]
    # Set Function Proc
    render.sample_fn = cast[NTriangleFunc](sample_bicubic)
    # Set Rendering Interval
    interval(render, v)
    # Render Triangle
    render(self.equation, render)
    self.copy(0, 0, 1280, 720)

proc render_subpixel(self: GUIDistort, v: var NTriangle) =
  if eq_winding(addr v) != 0:
    eq_calculate( # Triangle Equation
      addr self.equation, addr v)
    # Prepare Triangle Rendering
    var render: NTriangleRender
    render.dst_w = 1280
    render.dst_h = 720
    # Subpixel Rendering Buffers
    render.dst = addr self.buffer[0]
    render.mask = addr self.mask[0]
    # Source Image
    render.src_w = self.source.w
    render.src_h = self.source.h
    render.src = addr self.source.buffer[0]
    # Set Function Proc
    render.sample_fn = cast[NTriangleFunc](sample_bilinear)
    # Set Rendering Interval
    interval(render, v)
    # Render Triangle with Subpixel Rendering
    render_subpixel(self.equation, render)
    self.copy(0, 0, 1280, 720)

proc newDistort(src: string): GUIDistort =
  new result
  # Load Source Image
  result.source = newImage(src)
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
  
  # Render Triangle A
  var triangle: NTriangle
  triangle[0] = NTriangleVertex(
    x: 10, y: 10, u: 0, v: 0)
  triangle[1] = NTriangleVertex(
    x: 40, y: 180, u: 180, v: 0)
  triangle[2] = NTriangleVertex(
    x: 250, y: 200, u: 180, v: 180)
  #render_subpixel(root, triangle)
  # Render Triangle C
  triangle[0] = NTriangleVertex(
    x: 10, y: 10, u: 0, v: 0)
  triangle[1] = NTriangleVertex(
    x: 700, y: 30, u: 180, v: 0)
  triangle[2] = NTriangleVertex(
    x: 20, y: 100, u: 180, v: 180)
  #render_subpixel(root, triangle)
  root.flags = wMouse
  # Render Triangle B
  triangle[0] = NTriangleVertex(
    x: 512, y: 400, u: 180, v: 180)
  triangle[1] = NTriangleVertex(
    x: 10, y: 512, u: 0, v: 180)
  triangle[2] = NTriangleVertex(
    x: 10, y: 10, u: 0, v: 0)
  #render_subpixel(root, triangle)
  # Render Triangle B
  triangle[0] = NTriangleVertex(
    x: 512, y: 400, u: 180, v: 180)
  triangle[1] = NTriangleVertex(
    x: 800, y: 600, u: 240, v: 240)
  triangle[2] = NTriangleVertex(
    x: 10, y: 512, u: 0, v: 180)
  #render_subpixel(root, triangle)
  # Render Triangle B
  triangle[2] = NTriangleVertex(
    x: 700, y: 10, u: 180, v: 0)
  triangle[1] = NTriangleVertex(
    x: 512, y: 400, u: 180, v: 180)
  triangle[0] = NTriangleVertex(
    x: 800, y: 600, u: 240, v: 240)
  #render_subpixel(root, triangle)
  # Render Triangle B
  triangle[0] = NTriangleVertex(
    x: 10, y: 512, u: 180, v: 0)
  triangle[1] = NTriangleVertex(
    x: 800, y: 600, u: 180, v: 180)
  triangle[2] = NTriangleVertex(
    x: 800, y: 700, u: 240, v: 240)
  #render_subpixel(root, triangle)
  # Render Triangle B
  triangle[0] = NTriangleVertex(
    x: 10, y: 512, u: 180, v: 0)
  triangle[1] = NTriangleVertex(
    x: 800, y: 700, u: 180, v: 180)
  triangle[2] = NTriangleVertex(
    x: 10, y: 700, u: 240, v: 240)
  #render_subpixel(root, triangle)
  # #[---------------------
  # Render Triangle B
  triangle[0] = NTriangleVertex(
    x: 10, y: 10, u: 0, v: 0)
  triangle[1] = NTriangleVertex(
    x: 500, y: 10, u: 980, v: 0)
  triangle[2] = NTriangleVertex(
    x: 500, y: 500, u: 980, v: 980)
  #render(root, triangle)
  # Render Triangle B
  triangle[0] = NTriangleVertex(
    x: 500, y: 500, u: 980, v: 980)
  triangle[1] = NTriangleVertex(
    x: 300, y: 500, u: 0, v: 980)
  triangle[2] = NTriangleVertex(
    x: 10, y: 10, u: 0, v: 0)
  render_subpixel(root, triangle)
  # ]#
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
