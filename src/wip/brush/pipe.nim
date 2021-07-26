import ../../spmc
include ffi

# ------------------------------
# BRUSH ENGINE ABSTRACTION TYPES
# ------------------------------

type
  NBrushShape* = enum
    bsCircle
    bsBlotmap
    bsBitmap
  NBrushBlend* = enum
    bnPencil, bnAirbrush
    bnFunc, bnFlat, bnEraser
    # Water Color Brushes
    bnAverage, bnWater, bnMarker
    # Special Brushes
    bnBlur, bnSmudge
  # -------------------
  NBrushMask {.union.} = object
    circle*: NBrushCircle
    blotmap*: NBrushBlotmap
    bitmap*: NBrushBitmap
  NBrushData {.union.} = object
    average: NBrushAverage
    water: NBrushWater
    smudge: NBrushSmudge
  NBrushTile = object
    shape: NBrushShape
    blend: NBrushBlend
    # Rendering Shape Data
    mask: ptr NBrushMask
    tex: ptr NBrushTexture
    # Rendering Blend Data
    data: NBrushData
    render: NBrushRender
  # ----------------------
  NBrushPipeline* = object
    # Brush Pipeline Target
    canvas*: NBrushCanvas
    # Brush Texture Pointers
    tex0*, tex1*: NBrushTexture
    # Brush Rendering Kind
    shape*: NBrushShape
    blend*: NBrushBlend
    # Brush Shape Mask
    mask*: NBrushMask
    # Base Rendering Color
    color0: array[4, cshort]
    color1: array[4, cshort]
    # Current Rendering Color
    color: array[4, cshort]
    # Alpha Mask & Blend
    alpha*, flow*: cint
    # Rendering Size
    w, h, shift: cint
    # Rendering Blocks
    tiles: seq[NBrushTile]
    # Thread Pool Pointer
    pool*: NThreadPool
    # Pipeline Status
    parallel*, skip*: bool

# -----------------------------------
# BRUSH PIPELINE COLOR INITIALIZATION
# -----------------------------------

proc color*(pipe: var NBrushPipeline; r, g, b: cshort) =
  pipe.color[0] = (r shl 7) or r
  pipe.color[1] = (g shl 7) or g
  pipe.color[2] = (b shl 7) or b
  # Set Alpha to 100%
  pipe.color[3] = 32767
  # Replace Base Color
  pipe.color0 = pipe.color
  pipe.color1 = pipe.color

proc transparent*(pipe: var NBrushPipeline) =
  var empty: array[4, cshort]
  # Replace Current Color
  pipe.color = empty
  # Replace Base Color
  pipe.color0 = empty
  pipe.color1 = empty

# -----------------------------------
# BRUSH PIPELINE TILES INITIALIZATION
# -----------------------------------

proc configure(tile: ptr NBrushTile, pipe: var NBrushPipeline) =
  let render = addr tile.render
  # Shape & Blend Kind
  tile.shape = pipe.shape
  tile.blend = pipe.blend
  # Shape & Texture
  tile.mask = addr pipe.mask
  tile.tex = addr pipe.tex1
  # Rendering Target & Color
  render.canvas = addr pipe.canvas
  render.color = addr pipe.color
  # Rendering Opacity
  render.alpha = pipe.alpha
  render.flow = pipe.flow
  # Tile Rendering Blend Data
  render.opaque = addr tile.data

proc reserve*(pipe: var NBrushPipeline; x1, y1, x2, y2, shift: cint) =
  let
    s = clamp(shift - 2, 1, 7)
    # Current Target Canvas
    canvas = addr pipe.canvas
    # Block Size
    size = cint(1 shl s)
    # Canvas Residual
    rw = canvas.w and (size - 1)
    rh = canvas.h and (size - 1)
    # Canvas Tiled Dimensions
    cw = (canvas.w shr s)
    ch = (canvas.h shr s)
    # Canvas Tiled + Residual
    zw = cw + cint(rw > 0)
    zh = ch + cint(rh > 0)
  var
    # Tiled Initial
    xx1 = x1 shr s
    yy1 = y1 shr s
    # Tiled Final
    xx2 = (x2 shr s) + 1
    yy2 = (y2 shr s) + 1
  # Clip Reserved Region
  if xx1 < 0: xx1 = 0
  if yy1 < 0: yy1 = 0
  if xx2 >= zw: xx2 = zw
  if yy2 >= zh: yy2 = zh
  # Tiled Dimensions
  let
    pw = max(xx2 - xx1, 0)
    ph = max(yy2 - yy1, 0)
  # Reserve Tiled Regions
  setLen(pipe.tiles, pw * ph)
  # Tile Index
  var
    idx: int
    px, py: cint
  # Locate Each Tile
  for ty in 0..<ph:
    for tx in 0..<pw:
      let
        tile = addr pipe.tiles[idx]
        render = addr tile.render
      # Calculate Position
      px = xx1 + tx
      py = yy1 + ty
      # Configure Tile
      configure(tile, pipe)
      # Rendering Position
      render.x = px shl s
      render.y = py shl s
      # Rendering Dimensions
      render.w = if px == cw: rw else: size
      render.h = if py == ch: rh else: size
      # Next Tile
      inc(idx)
  # Store Dimensions
  pipe.w = pw
  pipe.h = ph
  # Store Shift
  pipe.shift = s
  # Set Parallel Check
  pipe.parallel = (s >= 4)

# --------------------------------
# BRUSH PIPELINE COLOR FIX15 PROCS
# --------------------------------

proc sqrt_32767*(x: cint): cint =
  var
    a = cuint(x shl 15)
    # Aproximation
    rem, root: cuint
  # Try Hard Square Root
  for i in 0 ..< 16:
    root = root shl 1
    rem = # Binary Magic
      (rem shl 2) or (a shr 30)
    a = a shl 2
    if root < rem:
      rem -= root or 1
      root += 2
  # Return Estimated
  result = cast[cint](root shr 1)

proc div_32767*(c: cint): cint =
  result = (c + 32767) shr 15
  result = (c + result) shr 15

proc fixlinear(size, scale: cint): cint =
  var calc: float32
  calc = 1.0 / float32(size)
  # Calculate Step
  calc *= float32(scale)
  calc *= 32768.0
  # Convert Step
  result = cint(calc)

proc interpolate(a, b, fract: cint): cint =
  result = (b - a) * fract
  result = div_32767(result)
  result = a + result

# ------------------------------------
# BRUSH PIPELINE COLOR AVERAGING PROCS
# ------------------------------------

proc average*(pipe: var NBrushPipeline; blending, dilution, persistence: cint; keep: bool) =
  var
    count, opacity: cint
    r, g, b, a: cint
  # Sum Each Average Tile
  block:
    var rr, gg, bb, aa: int64
    for tile in mitems(pipe.tiles):
      let avg = addr tile.data.average
      # Sum Color Count
      count += avg.count
      # Sum Color Channels
      rr += avg.total[0]
      gg += avg.total[1]
      bb += avg.total[2]
      aa += avg.total[3]
    # Avoid Zero Division
    if count == 0: count = 1
    # Divide Color Average
    if aa > 0:
      let w = 32767.0 / cfloat(aa)
      # Apply Weigthed Average
      r = cint(rr.cfloat * w)
      g = cint(gg.cfloat * w)
      b = cint(bb.cfloat * w)
      a = cint(aa.cfloat * w)
    # Calculate Current Opacity
    opacity = cint(aa div count)
  # Quantize Averaged Color
  if not pipe.skip:
    r = interpolate(r shr 7 shl 7, r, opacity)
    g = interpolate(g shr 7 shl 7, g, opacity)
    b = interpolate(b shr 7 shl 7, b, opacity)
    a = interpolate(a shr 7 shl 7, a, opacity)
  # Interpolate With Blending
  r = interpolate(pipe.color0[0], r, blending)
  g = interpolate(pipe.color0[1], g, blending)
  b = interpolate(pipe.color0[2], b, blending)
  a = interpolate(pipe.color0[3], a, blending)
  # Blend With Current Color
  r += pipe.color1[0] - div_32767(pipe.color1[0] * a)
  g += pipe.color1[1] - div_32767(pipe.color1[1] * a)
  b += pipe.color1[2] - div_32767(pipe.color1[2] * a)
  a += pipe.color1[3] - div_32767(pipe.color1[3] * a)
  # Calculate Dilution Opacity Interpolation
  opacity = interpolate(32767, opacity, dilution)
  # Interpolate With Persistence
  if persistence > 0 and not pipe.skip:
    r = interpolate(r, pipe.color1[0], persistence)
    g = interpolate(g, pipe.color1[1], persistence)
    b = interpolate(b, pipe.color1[2], persistence)
    a = interpolate(a, pipe.color1[3], persistence)
  # Replace Blended Color
  pipe.color1[0] = cshort(r)
  pipe.color1[1] = cshort(g)
  pipe.color1[2] = cshort(b)
  pipe.color1[3] = cshort(a)
  # Apply Current Opacity
  r = div_32767(r * opacity)
  g = div_32767(g * opacity)
  b = div_32767(b * opacity)
  a = div_32767(a * opacity)
  # Interpolate With Persistence
  if persistence > 0 and not pipe.skip:
    r = interpolate(r, pipe.color[0], persistence)
    g = interpolate(g, pipe.color[1], persistence)
    b = interpolate(b, pipe.color[2], persistence)
    a = interpolate(a, pipe.color[3], persistence)
  # Replace Current Color
  pipe.color[0] = cshort(r)
  pipe.color[1] = cshort(g)
  pipe.color[2] = cshort(b)
  pipe.color[3] = cshort(a)

# -------------------------------
# BRUSH PIPELINE WATERCOLOR PROCS
# -------------------------------

proc convolve(buffer: ptr UncheckedArray[cshort], x, y, w, h: cint): array[4, cint] =
  let
    x1 = max(x - 1, 0)
    y1 = max(y - 1, 0)
    x2 = min(x + 1, w - 1)
    y2 = min(y + 1, h - 1)
  # Current Position
  var 
    count: cint
    cursor, cursor_row =
      (y1 * w + x1) shl 2
  # Convolve Pixels
  for yy in y1 .. y2:
    cursor = cursor_row
    # Convolve Row
    for xx in x1 .. x2:
      if buffer[cursor + 3] >= 0:
        result[0] += buffer[cursor + 0]
        result[1] += buffer[cursor + 1]
        result[2] += buffer[cursor + 2]
        result[3] += buffer[cursor + 3]
        # Add Count
        inc(count)
      # Next Pixel
      cursor += 4
    # Next Pixel Stride
    cursor_row += w shl 2
  # Divide Pixel
  if count > 1:
    result[0] = result[0] div count
    result[1] = result[1] div count
    result[2] = result[2] div count
    result[3] = result[3] div count

proc blur(pipe: var NBrushPipeline, buffer: ptr UncheckedArray[cshort]) =
  let 
    dst = cast[buffer.type](pipe.canvas.buffer1)
    # Tiled Dimensions
    w = pipe.w
    h = pipe.h
    # Pixel Color
    color = pipe.color
  # Current Pixel
  var 
    pixel: array[4, cint]
    cursor, opacity: cint
  # Blur Each Pixel
  for y in 0 ..< h:
    for x in 0 ..< w:
      if buffer[cursor + 3] > 0:
        pixel[0] = buffer[cursor + 0]
        pixel[1] = buffer[cursor + 1]
        pixel[2] = buffer[cursor + 2]
        pixel[3] = buffer[cursor + 3]
      else: # Convolve Dead Pixel
        pixel = convolve(buffer, x, y, w, h)
      # Current Opacity
      opacity = pixel[3]
      # Blend With Current Color
      pixel[0] += color[0] - div_32767(color[0] * opacity)
      pixel[1] += color[1] - div_32767(color[1] * opacity)
      pixel[2] += color[2] - div_32767(color[2] * opacity)
      pixel[3] += color[3] - div_32767(color[3] * opacity)
      # Store Current Pixel
      dst[cursor + 0] = cast[cshort](pixel[0])
      dst[cursor + 1] = cast[cshort](pixel[1])
      dst[cursor + 2] = cast[cshort](pixel[2])
      dst[cursor + 3] = cast[cshort](pixel[3])
      # Next Pixel
      cursor += 4

proc water*(pipe: var NBrushPipeline; keep: bool) =
  let
    w = pipe.w
    h = pipe.h
    # Block Size
    s = pipe.shift
    size = cint(1 shl s)
    # Fixlinear Step Deltas
    fx = fixlinear(w shl s, w - 1)
    fy = fixlinear(h shl s, h - 1)
  var
    buffer = cast[ptr UncheckedArray[cshort]](
      pipe.canvas.buffer1)
    # Current Position
    idx, cursor: int
    # Current Block Average
    avg: ptr NBrushWater
    # Pixel Average
    count, r, g, b, a: cint
  # Locate Buffer to Auxiliar Buffer
  buffer = cast[buffer.type](addr buffer[w * h * 4])
  # Arrange Each Pixel
  for y in 0 ..< h:
    for x in 0 ..< w:
      avg = addr pipe.tiles[idx].data.water
      # Get Current Color Average
      count = avg.count
      if count > 0:
        r = avg.total[0] div count
        g = avg.total[1] div count
        b = avg.total[2] div count
        a = avg.total[3] div count
      else: # Dead Pixel
        r = 0xFFFF
        g = 0xFFFF
        b = 0xFFFF
        a = 0xFFFF
      # Store Current Pixel
      buffer[cursor + 0] = cast[cshort](r)
      buffer[cursor + 1] = cast[cshort](g)
      buffer[cursor + 2] = cast[cshort](b)
      buffer[cursor + 3] = cast[cshort](a)
      # Fixlinear Steps
      avg.fx = fx
      avg.fy = fy
      # Filinear Position
      avg.x = x * size * fx
      avg.y = y * size * fy
      # Filinear Stride
      avg.stride = cast[cint](w)
      # Next Tile & Pixel
      inc(idx); cursor += 4
  # Apply Blur
  pipe.blur(buffer)

# --------------------------
# BRUSH MULTI-THREADED PROCS
# --------------------------

proc mt_stage0(tile: ptr NBrushTile) =
  let 
    render = addr tile.render
    mask = addr tile.mask
  # -- Render Brush Shape Mask
  case tile.shape
  of bsCircle: brush_circle_mask(render, addr mask.circle)
  of bsBlotmap: brush_blotmap_mask(render, addr mask.blotmap)
  of bsBitmap: brush_bitmap_mask(render, addr mask.bitmap)
  # -- Render Brush Texture Mask
  if not isNil(tile.tex.buffer):
    brush_texture_mask(render, tile.tex)
  # -- Render Brush Clipping
  if not isNil(render.canvas.clip) or 
  not isNil(render.canvas.alpha):
    brush_clip_blend(render)
  # -- Stage0 Blending Mode
  case tile.blend
  of bnPencil, bnAirbrush: 
    brush_normal_blend(render)
  of bnFunc: brush_func_blend(render)
  of bnFlat: brush_flat_blend(render)
  of bnEraser: brush_erase_blend(render)
  # Watercolor Blending Modes
  of bnAverage, bnWater, bnMarker:
    brush_water_first(render)
  # Special Blending Modes
  of bnBlur: brush_blur_first(render)
  of bnSmudge:
    if render.alpha > 0:
      brush_smudge_first(render)
      brush_smudge_blend(render)
    # Change Current Copy Position
    tile.data.smudge.x = mask.circle.x
    tile.data.smudge.y = mask.circle.y

proc mt_stage1(tile: ptr NBrushTile) =
  let render = addr tile.render
  # -- Stage1 Blending Mode
  case tile.blend
  of bnAverage: brush_normal_blend(render)
  of bnWater: brush_water_blend(render)
  of bnMarker: brush_flat_blend(render)
  of bnBlur: brush_blur_blend(render)
  # Doesn't Need Stage1
  else: discard

# ---------------------
# BRUSH PROC DISPATCHER
# ---------------------

proc dispatch_stage0*(pipe: var NBrushPipeline) =
  let pool = pipe.pool
  # Check if tile is 64x64
  if pipe.parallel:
    for tile in mitems(pipe.tiles):
      pool.spawn(mt_stage0, addr tile)
    pool.sync()
  else: # Single Threaded
    for tile in mitems(pipe.tiles):
      mt_stage0(addr tile)

proc dispatch_stage1*(pipe: var NBrushPipeline) =
  let pool = pipe.pool
  # Check if tile is 64x64
  if pipe.parallel:
    for tile in mitems(pipe.tiles):
      pool.spawn(mt_stage1, addr tile)
    pool.sync()
  else: # Single Threaded
    for tile in mitems(pipe.tiles):
      mt_stage1(addr tile)
