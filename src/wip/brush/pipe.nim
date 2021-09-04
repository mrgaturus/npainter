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
    color0: array[4, cint]
    color1: array[4, cint]
    # Current Rendering Color
    color: array[4, cint]
    # Alpha Mask & Blend
    alpha*, flow*: cint
    # Rendering Blocks
    w, h, shift: cint
    # Rendering Region
    rx, ry, rw, rh: cint
    # Rendering Blocks
    tiles: seq[NBrushTile]
    # Thread Pool Pointer
    pool*: NThreadPool
    # Pipeline Status
    parallel*, skip*: bool

# -----------------------------------
# BRUSH PIPELINE COLOR INITIALIZATION
# -----------------------------------

proc color*(pipe: var NBrushPipeline; r, g, b: cint) =
  pipe.color[0] = (r shl 8) or r
  pipe.color[1] = (g shl 8) or g
  pipe.color[2] = (b shl 8) or b
  # Set Alpha to 100%
  pipe.color[3] = 65535
  # Replace Base Color
  pipe.color0 = pipe.color
  pipe.color1 = pipe.color

proc transparent*(pipe: var NBrushPipeline) =
  var empty: array[4, cint]
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
    # Region Size
    rw = x2 - x1
    rh = y2 - y1
    # Region Steps
    sw = rw / shift
    sh = rh / shift
    # Canvas Dimensions
    cw = pipe.canvas.w
    ch = pipe.canvas.h
  var
    x = cfloat(x1)
    y = cfloat(y1)
    # Integer Position
    prev_x, xx = x1
    prev_y, yy = y1
    # Cliped Position
    xx1, xx2, yy1, yy2: cint
    # Current Tile
    idx: cint
  # Reserve Rendering Tiles
  setLen(pipe.tiles, shift * shift)
  # Arrange Y Tiles
  for i in 0 ..< shift:
    y += sh
    yy = cint(y)
    # Clip Y Position
    yy1 = max(prev_y, 0)
    yy2 = min(yy, ch)
    # Arrange X Tiles
    for j in 0 ..< shift:
      x += sw
      xx = cint(x)
      # Clip X Position
      xx1 = max(prev_x, 0)
      xx2 = min(xx, cw)
      block:
        # Current Tile
        let
          tile = addr pipe.tiles[idx]
          render = addr tile.render
        # Configure Tile
        configure(tile, pipe)
        # Current Position
        render.x = xx1
        render.y = yy1
        # Rendering Size
        render.w = xx2 - xx1
        render.h = yy2 - yy1
      # Change Prev X
      prev_x = xx
      # Next Tile
      inc(idx)
    # Reset X Step
    prev_x = x1
    x = cfloat(x1)
    # Change Prev Y
    prev_y = yy
  # Region Size
  pipe.rw = rw
  pipe.rh = rh
  # Tiled Size
  pipe.w = shift
  pipe.h = shift
  # Region Position
  pipe.rx = x1
  pipe.ry = y1
  # Parallel Condition
  pipe.parallel = shift > 5

# --------------------------------
# BRUSH PIPELINE COLOR FIX16 PROCS
# --------------------------------

proc sqrt_65535*(x: cint): cint =
  var
    a = cuint(x shl 16)
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

proc mul_65535*(a, b: cint): cint =
  var calc: cuint
  # Calculate Interpolation
  calc = cuint(a) * cuint(b)
  calc = (calc + 65535) shr 16
  # Cast Back to Int
  result = cast[cint](calc)

proc mix_65535(a, b, fract: cint): cint =
  var calc: cuint
  # Calculate Interpolation
  calc = cuint(a) * cuint(65535 - fract)
  calc += cuint(b) * cuint(fract)
  calc = (calc) shr 16
  # Cast Back to Int
  result = cast[cint](calc)

proc fix_65535(size, scale: cint): cint =
  var calc: float32
  calc = 1.0 / float32(size)
  # Calculate Step
  calc *= float32(scale)
  calc *= 65536.0
  # Convert Step
  result = cint(calc)

# ------------------------------------
# BRUSH PIPELINE COLOR AVERAGING PROCS
# ------------------------------------

proc average*(pipe: var NBrushPipeline; blending, dilution, persistence: cint) =
  var
    count, opacity: cint
    r, g, b, a: cint
    # Dilution & Persistence
    dull, weak: cint
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
    # Calculate Averaged Opacity
    opacity = cint(aa div count)
    # Calculate Averaged Color
    if opacity > 255:
      var w = 65535.0 / float(aa)
      # Apply Weigthed Average
      r = cint(rr.float * w)
      g = cint(gg.float * w)
      b = cint(bb.float * w)
      a = cint(aa.float * w)
      # Ajust Color Quantization
      weak = mix_65535(8, 12, dilution)
      weak = cast[cint](1 shl weak) - 1
      # Apply Color Quantization
      r = mix_65535(r and not weak, r or 0x3, opacity)
      g = mix_65535(g and not weak, g or 0x3, opacity)
      b = mix_65535(b and not weak, b or 0x3, opacity)
      a = mix_65535(a and not weak, a or 0x3, opacity)
    else:
      r = pipe.color1[0]
      g = pipe.color1[1]
      b = pipe.color1[2]
      a = pipe.color1[3]
      # Straight Opacity
      if not pipe.skip:
        opacity = pipe.color[3]
      else: opacity = 65535 - dilution
  # Calculate Persistence
  if not pipe.skip:
    case pipe.blend
    of bnAverage, bnWater:
      dull = sqrt_65535(pipe.flow)
    of bnMarker:
      dull = cint(opacity / pipe.alpha * 65535.0)
      dull = min(dull, 65535)
    else: dull = 65535
    # Ajust Persistence With Opacity
    weak = 65535 - sqrt_65535(persistence)
    weak = 65535 - mul_65535(weak, dull)
  # Interpolate With Blending
  r = mix_65535(pipe.color0[0], r, blending)
  g = mix_65535(pipe.color0[1], g, blending)
  b = mix_65535(pipe.color0[2], b, blending)
  a = mix_65535(pipe.color0[3], a, blending)
  # Interpolate With Persistence
  if persistence > 0 and not pipe.skip:
    r = mix_65535(r, pipe.color1[0], weak)
    g = mix_65535(g, pipe.color1[1], weak)
    b = mix_65535(b, pipe.color1[2], weak)
    a = mix_65535(a, pipe.color1[3], weak)
  # Replace Blended Color
  pipe.color1[0] = r
  pipe.color1[1] = g
  pipe.color1[2] = b
  pipe.color1[3] = a
  # Calculate Dilution Opacity Amount
  dull = mix_65535(65535, opacity, dilution)
  # Apply Current Dilution
  r = mul_65535(r, dull)
  g = mul_65535(g, dull)
  b = mul_65535(b, dull)
  a = mul_65535(a, dull)
  # Interpolate With Persistence
  if persistence > 0 and not pipe.skip:
    r = mix_65535(r, pipe.color[0], weak)
    g = mix_65535(g, pipe.color[1], weak)
    b = mix_65535(b, pipe.color[2], weak)
    a = mix_65535(a, pipe.color[3], weak)
  # Replace Current Color
  pipe.color[0] = r
  pipe.color[1] = g
  pipe.color[2] = b
  pipe.color[3] = a

# -------------------------------
# BRUSH PIPELINE WATERCOLOR PROCS
# -------------------------------

proc convolve(buffer: ptr UncheckedArray[cint], x, y, w, h: cint): array[4, cint] =
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
      if buffer[cursor + 3] < 65536:
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
  cursor = result[3]
  if count > 1 and cursor > 0:
    let w = cursor / (cursor * count)
    result[0] = cint(result[0].float * w)
    result[1] = cint(result[1].float * w)
    result[2] = cint(result[2].float * w)
    result[3] = cint(result[3].float * w)

proc blur(pipe: var NBrushPipeline, buffer: ptr UncheckedArray[cint]) =
  let 
    dst = cast[ptr UncheckedArray[cushort]](
      pipe.canvas.buffer1)
    # Tiled Dimensions
    w = pipe.w
    h = pipe.h
  # Current Pixel
  var 
    pixel: array[4, cint]
    cursor, opacity: cint
    # Current Color
    color = pipe.color
  # Blur Each Pixel
  for y in 0 ..< h:
    for x in 0 ..< w:
      # Apply Blur to Current Pixel
      pixel = convolve(buffer, x, y, w, h)
      # Current Opacity
      opacity = pixel[3]
      # Blend With Current Color
      pixel[0] += color[0] - mul_65535(color[0], opacity)
      pixel[1] += color[1] - mul_65535(color[1], opacity)
      pixel[2] += color[2] - mul_65535(color[2], opacity)
      pixel[3] += color[3] - mul_65535(color[3], opacity)
      # Store Current Pixel
      dst[cursor + 0] = cast[cushort](pixel[0])
      dst[cursor + 1] = cast[cushort](pixel[1])
      dst[cursor + 2] = cast[cushort](pixel[2])
      dst[cursor + 3] = cast[cushort](pixel[3])
      # Next Pixel
      cursor += 4

proc water*(pipe: var NBrushPipeline) =
  let
    w = pipe.w
    h = pipe.h
    # Pivot Position
    rx = pipe.rx
    ry = pipe.ry
    # Fixlinear Step Deltas
    fx = fix_65535(pipe.rw, w - 1)
    fy = fix_65535(pipe.rh, h - 1)
  var
    buffer = cast[ptr UncheckedArray[cint]](
      pipe.canvas.buffer1)
    # Pixel Average
    cursor, count: cint
    r, g, b, a: cint
  # Locate Buffer to Auxiliar Buffer
  buffer = cast[buffer.type](addr buffer[w * h * 2])
  # Arrange Each Pixel
  for tile in mitems(pipe.tiles):
    let avg = addr tile.data.water
    # Get Current Color Average
    count = avg.count
    if count > 0:
      r = avg.total[0] div count
      g = avg.total[1] div count
      b = avg.total[2] div count
      a = avg.total[3] div count
    else: # Dead Pixel
      r = 65536
      g = 65536
      b = 65536
      a = 65536
    # Store Current Pixel
    buffer[cursor + 0] = r
    buffer[cursor + 1] = g
    buffer[cursor + 2] = b
    buffer[cursor + 3] = a
    # Fixlinear Steps
    avg.fx = fx
    avg.fy = fy
    # Filinear Position
    avg.x = (tile.render.x - rx) * fx
    avg.y = (tile.render.y - ry) * fy
    # Filinear Stride
    avg.stride = cast[cint](w)
    # Next Tile & Pixel
    cursor += 4
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
