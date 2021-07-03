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
    # Base & Averaged Colors
    color0: array[4, cshort]
    color1: array[4, cshort]
    # Rendering Color
    color: array[4, cshort]
    # Alpha Mask & Blend
    alpha*, flow*: cint
    # Rendering Size
    w, h, shift: cint
    # Rendering Blocks
    tiles: seq[NBrushTile]
    # Thread Pool Pointer
    pool*: NThreadPool
    # Thread Pool Check
    parallel*: bool

# -----------------------------------
# BRUSH PIPELINE COLOR INITIALIZATION
# -----------------------------------

proc color*(pipe: var NBrushPipeline; r, g, b: cshort) =
  pipe.color0[0] = (r shl 7) or r
  pipe.color0[1] = (g shl 7) or g
  pipe.color0[2] = (b shl 7) or b
  # Set Alpha to 100%
  pipe.color0[3] = 32767
  # Replace Averaged Color
  pipe.color1 = pipe.color0
  # Replace Rendering Color
  pipe.color = pipe.color0

proc transparent*(pipe: var NBrushPipeline) =
  var empty: array[4, cshort]
  # Replace Base & Averaged
  pipe.color0 = empty
  pipe.color1 = empty
  # Replace Rendering Color
  pipe.color = empty

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
    s = min(shift, 6)
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
    pw = xx2 - xx1
    ph = yy2 - yy1
  # Reserve Tiled Regions
  if pw > 0 and ph > 0:
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

proc interpolate(a, b, fract: cint): cint =
  result = (b - a) * fract
  result = div_32767(result)
  result = a + result

proc straight(c, a: cint): cint =
  result = cint(c.cfloat / a.cfloat * 32767.0)

# ------------------------------------
# BRUSH PIPELINE COLOR AVERAGING PROCS
# ------------------------------------

proc average*(pipe: var NBrushPipeline; blending, dilution, persistence: cint; keep: bool) =
  var
    count, opacity: cint
    r, g, b, a: cint
  # only occurs on some blends
  case pipe.blend
  of bnAverage, bnWater, bnMarker:
    for tile in mitems(pipe.tiles):
      let avg = addr tile.data.average
      # Sum Color Count
      if keep:
        count += avg.count0
      else: count += avg.count1
      # Sum Each Color Channel
      r += avg.color_sum[0]
      g += avg.color_sum[1]
      b += avg.color_sum[2]
      a += avg.color_sum[3]
    if count == 0: count = 1
    # Divide Color Average and Convert
    r = r div count shl 4
    g = g div count shl 4
    b = b div count shl 4
    a = a div count shl 4
    # Keep Opacity?
    if keep:
      opacity = div_32767(blending * opacity)
      opacity = interpolate(blending, opacity, 1024)
      # Replace Blending Count
      unsafeAddr(blending)[] = opacity
    # Backup Opacity
    opacity = a
    # Calculate Straigth
    if a > 0:
      r = straight(r, a)
      g = straight(g, a)
      b = straight(b, a)
      # Complete Opacity
      a = 32767
    else: # Dont Interpolate
      r = pipe.color1[0]
      g = pipe.color1[1]
      b = pipe.color1[2]
      a = pipe.color1[3]
    # Interpolate With Blending
    r = interpolate(pipe.color0[0], r, blending)
    g = interpolate(pipe.color0[1], g, blending)
    b = interpolate(pipe.color0[2], b, blending)
    a = interpolate(pipe.color0[3], a, blending)
    # Calculate Dilution Opacity
    opacity = interpolate(
      32767, opacity, dilution)
    # Interpolate with Dilution
    r = div_32767(r * opacity)
    g = div_32767(g * opacity)
    b = div_32767(b * opacity)
    a = div_32767(a * opacity)
    # Interpolate With Persistence
    if pipe.alpha == 32767:
      r = interpolate(r, pipe.color1[0], persistence)
      g = interpolate(g, pipe.color1[1], persistence)
      b = interpolate(b, pipe.color1[2], persistence)
      a = interpolate(a, pipe.color1[3], persistence)
    # Replace Skip Check
    pipe.alpha = 32767
    # Replace Auxiliar Color
    pipe.color1[0] = cshort(r)
    pipe.color1[1] = cshort(g)
    pipe.color1[2] = cshort(b)
    pipe.color1[3] = cshort(a)
    # Replace Rendering Color
    pipe.color = pipe.color1
  else: discard

# -------------------------------
# BRUSH PIPELINE WATERCOLOR PROCS
# -------------------------------

proc fixed(size, scale: cint): cint =
  var calc: float32
  calc = 1.0 / float32(size)
  # Calculate Step
  calc *= float32(scale)
  calc *= 32768.0
  # Convert Step
  result = cint(calc)

proc average(water: ptr NBrushWater; keep: bool): array[4, cint] =
  var r, g, b, a, count: cint
  # Load Each Color Channel
  r = water.color_sum[0]
  g = water.color_sum[1]
  b = water.color_sum[2]
  a = water.color_sum[3]
  # Keep Opacity?
  count = if keep:
    water.count0
  else: water.count1
  # Divide Color Average and Convert
  r = (r div count shl 7) or r
  g = (g div count shl 7) or g
  b = (b div count shl 7) or b
  a = (a div count shl 7) or a
  # Keep Opacity?
  if not keep and a > 0:
    # Convert to Straight
    r = straight(r, a)
    g = straight(g, a)
    b = straight(b, a)
    # Set Alpha to 100%
    a = 32767
  # Return Color
  result[0] = r
  result[1] = g
  result[2] = b
  result[3] = a

proc water*(pipe: var NBrushPipeline; keep: bool) =
  let 
    color = pipe.color
    # Tiled Dimensions
    w = pipe.w
    h = pipe.h
    # Tiled Shift
    s = pipe.shift
    # Tiled Dimension
    size = cint(1) shl s
    # Fixed Bilinear Steps
    fx = fixed(size, w - 1)
    fy = fixed(size, h - 1)
  var 
    tile: ptr NBrushTile
    water: ptr NBrushWater
    # Pixel Averaging
    avg: array[4, cint]
    # Pixel Destintation Target
    pixel: ptr array[4, cshort]
    # Tile Index
    idx: int
  # Ensure that is Watercolor Brush
  if pipe.blend == bnWater:
    let buffer = # Load Auxiliar Buffer
      cast[ptr UncheckedArray[cshort]](
        pipe.canvas.buffer1)
    for y in 0..<h:
      for x in 0..<w:
        tile = addr pipe.tiles[idx]
        water = addr tile.data.water
        # Block Pixel Averaging
        avg = average(water, keep)
        # Blend With Current Color
        avg[0] += color[0] - div32767(color[0] * avg[3])
        avg[1] += color[1] - div32767(color[1] * avg[3])
        avg[2] += color[2] - div32767(color[2] * avg[3])
        avg[3] += color[3] - div32767(color[3] * avg[3])
        # Pointer To Current Watercolor Pixel
        pixel = cast[pixel.type](addr buffer[idx shl 2])
        # Store Current Color
        pixel[0] = cshort(avg[0])
        pixel[1] = cshort(avg[1])
        pixel[2] = cshort(avg[2])
        pixel[3] = cshort(avg[3])
        # Water Position, Bilinear
        water.x = fx * size * x
        water.y = fy * size * y
        # Water Dimensions
        water.w = w
        water.h = h
        # Water Interpolation
        water.count0 = fx
        water.count1 = fy
        # Next Tile
        inc(idx)

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
    if render.alpha == 0:
      brush_smudge_first(render)
      brush_smudge_blend(render)
    # Change Current Copy Position
    tile.data.smudge.x = mask.circle.x
    tile.data.smudge.y = mask.circle.y
    # Remove Skip
    render.alpha = 0

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
