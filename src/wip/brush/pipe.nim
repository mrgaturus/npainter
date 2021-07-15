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
  pipe.color0[0] = (r shl 7) or r
  pipe.color0[1] = (g shl 7) or g
  pipe.color0[2] = (b shl 7) or b
  # Set Alpha to 100%
  pipe.color0[3] = 32767
  # Replace Rendering Color
  pipe.color = pipe.color0

proc transparent*(pipe: var NBrushPipeline) =
  var empty: array[4, cshort]
  # Replace Base Color
  pipe.color0 = empty
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
  pipe.parallel = (s >= 5)

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

proc straight(c, a: cint): cint =
  result = cint(c.cfloat / a.cfloat * 32767.0)

# ------------------------------------
# BRUSH PIPELINE COLOR AVERAGING PROCS
# ------------------------------------

proc average*(pipe: var NBrushPipeline; blending, dilution, persistence: cint; keep: bool) =
  var
    count, opacity: cint
    r, g, b, a: cint
  # Sum Each Average Tile
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
  # Avoid Zero Division
  if count == 0: count = 1
  # Divide Color Average
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
    r = pipe.color[0]
    g = pipe.color[1]
    b = pipe.color[2]
    a = pipe.color[3]
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
  if persistence > 0 and not pipe.skip:
    r = interpolate(r, pipe.color[0], persistence)
    g = interpolate(g, pipe.color[1], persistence)
    b = interpolate(b, pipe.color[2], persistence)
    a = interpolate(a, pipe.color[3], persistence)
  # Replace Auxiliar Color
  pipe.color[0] = cshort(r)
  pipe.color[1] = cshort(g)
  pipe.color[2] = cshort(b)
  pipe.color[3] = cshort(a)

# -------------------------------
# BRUSH PIPELINE WATERCOLOR PROCS
# -------------------------------

proc water*(pipe: var NBrushPipeline) =
  let
    # Tiled Shift
    s = pipe.shift
    ss = max(s - 2, 0)
    # Tiled Size
    w = pipe.w
    h = pipe.h
    # Subdivided Dimensions
    sw = w shl (s - ss)
    sh = h shl (s - ss)
    # Fixed-Point Bilinear Steps
    fx = fixlinear(sw shl ss, sw - 1)
    fy = fixlinear(sh shl ss, sh - 1)
  var 
    tile: ptr NBrushTile
    water: ptr NBrushWater
    # Tile Index
    idx: cint
  for y in 0..<h:
    for x in 0..<w:
      tile = addr pipe.tiles[idx]
      water = addr tile.data.water
      # Water Position
      water.x = x
      water.y = y
      # Water Fixlinear
      water.fx = fx
      water.fy = fy
      # Water Dimensions
      water.s = cshort(s)
      water.ss = cshort(ss)
      # Water Buffer Stride
      water.stride = cshort(sw)
      water.rows = cshort(sh)
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
  of bnAverage, bnMarker: 
    brush_average_first(render)
  of bnWater: brush_water_first(render)
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
