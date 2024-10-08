# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2021 Cristian Camilo Ruiz <mrgaturus>
from bitops import fast_log2
# Import Multithreading
import nogui/async/pool
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
    # Blur & Smudge
    blur: NBrushBlur
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
    yy = cint(y + 0.5)
    # Clip Y Position
    yy1 = max(prev_y, 0)
    yy2 = min(yy, ch)
    # Arrange X Tiles
    for j in 0 ..< shift:
      x += sw
      xx = cint(x + 0.5)
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

proc clip(pipe: var NBrushPipeline) =
  let
    # Canvas Dimensions
    cw = pipe.canvas.w
    ch = pipe.canvas.h
  var
    # Region Position
    x1 = pipe.rx
    y1 = pipe.ry
    # Region Size
    x2 = x1 + pipe.rw
    y2 = y1 + pipe.rh
  # Clip Current Region
  x1 = clamp(x1, 0, cw)
  y1 = clamp(y1, 0, ch)
  x2 = clamp(x2, 0, cw)
  y2 = clamp(y2, 0, ch)
  # Change Region Position
  pipe.rx = x1
  pipe.ry = y1
  # Change Region Size
  pipe.rw = x2 - x1
  pipe.rh = y2 - y1

# --------------------------------
# BRUSH PIPELINE COLOR FIX16 PROCS
# --------------------------------

proc sqrt_65535(x: cint): cint =
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

proc mul_65535(a, b: cint): cint =
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
  calc = (calc + 65535) shr 16
  # Cast Back to Int
  result = cast[cint](calc)

proc fix_65535(size, scale: cint): cint =
  var calc = scale / size
  # Convert to Fix16
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
      # Calculate Weigthed Average
      let w = 65536.0 / float(aa)
      # Apply Weigthed Average
      r = cint(rr.float * w)
      g = cint(gg.float * w)
      b = cint(bb.float * w)
      # Calculate Opacity
      weak = opacity
      # Ajust Opacity for Marker
      if pipe.blend == bnMarker:
        weak = cint(weak / pipe.alpha * 65535.0)
        weak = min(weak, 65535)
      # Calculate Color Quantization
      weak = (65535 - weak) shr 8
      # Calculate Mask Quantization
      if weak > 0:
        weak = fast_log2(weak).cint
        dull = cint(1 shl weak) - 1
        # Apply Mask Quantization
        r = min(r and not dull, 65535)
        g = min(g and not dull, 65535)
        b = min(b and not dull, 65535)
      # Full Opacity
      a = 65535
    else:
      r = pipe.color1[0]
      g = pipe.color1[1]
      b = pipe.color1[2]
      a = pipe.color1[3]
      # Straight Opacity
      if not pipe.skip:
        opacity = pipe.color[3]
      else: opacity = 65535 - dilution
  # Ajust Blended Color
  if not pipe.skip:
    # Reduce Blending at Low
    if opacity < 1024:
      weak = sqrt_65535(opacity shl 6)
      # Interpolate to Current Color
      r = mix_65535(pipe.color0[0], r, weak)
      g = mix_65535(pipe.color0[1], g, weak)
      b = mix_65535(pipe.color0[2], b, weak)
      a = mix_65535(pipe.color0[3], a, weak)
    # Ajust Persistence Flow
    dull = sqrt_65535(pipe.flow)
    # Ajust Persistence With Flow
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

proc glass*(pipe: var NBrushPipeline, blending, persistence: cint) =
  var
    count: cint
    r, g, b, a: cint
    # Persistence
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
    # Divide Color Average
    if count > 0:
      r = cint(rr div count)
      g = cint(gg div count)
      b = cint(bb div count)
      a = cint(aa div count)
  # Apply Blending Amount
  r = mul_65535(r, blending)
  g = mul_65535(g, blending)
  b = mul_65535(b, blending)
  a = mul_65535(a, blending)
  # Interpolate With Persistence
  if persistence > 0 and not pipe.skip:
    # Ajust Persistence Flow
    dull = sqrt_65535(pipe.flow)
    # Ajust Persistence With Flow
    weak = 65535 - sqrt_65535(persistence)
    weak = 65535 - mul_65535(weak, dull)
    # Apply Persistence Interpolation
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
  # Divide Pixel Average
  cursor = result[3]
  if count > 0 and cursor > 0:
    let w = 65535.0 / float(cursor)
    result[0] = cint(result[0].float * w)
    result[1] = cint(result[1].float * w)
    result[2] = cint(result[2].float * w)
    # Calculate Alpha Average
    result[3] = cursor div count

proc blur(pipe: var NBrushPipeline, buffer: ptr UncheckedArray[cint], amount: cint) =
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
  let
    # Current Color
    color0 = pipe.color
    color1 = pipe.color1
    dilution = color0[3]
  # Blur Each Pixel
  for y in 0 ..< h:
    for x in 0 ..< w:
      # Apply Blur to Current Pixel
      pixel = convolve(buffer, x, y, w, h)
      # Current Opacity
      opacity = pixel[3]
      # Select Color Blending
      if amount <= 0:
        # Premultiply Alpha for Transparency
        pixel[0] = mul_65535(pixel[0], opacity)
        pixel[1] = mul_65535(pixel[1], opacity)
        pixel[2] = mul_65535(pixel[2], opacity)
        # Get Interpolation
        opacity = -amount
        # Interpolate Current Pixel
        pixel[0] = mix_65535(color0[0], pixel[0], opacity)
        pixel[1] = mix_65535(color0[1], pixel[1], opacity)
        pixel[2] = mix_65535(color0[2], pixel[2], opacity)
        pixel[3] = mix_65535(color0[3], pixel[3], opacity)
      else:
        # Ajust Opacity
        if dilution < 65535:
          opacity = cint(opacity / dilution * 65535.0)
          # Clamp Ajusted Opacity
          opacity = min(opacity, 65535)
        # Apply Current Amount
        if amount < 65535:
          opacity = mul_65535(opacity, amount)
        # Interpolate Current Opacity
        pixel[0] = mix_65535(color1[0], pixel[0], opacity)
        pixel[1] = mix_65535(color1[1], pixel[1], opacity)
        pixel[2] = mix_65535(color1[2], pixel[2], opacity)
        # Apply Current Dilution
        if dilution < 65535:
          pixel[0] = mul_65535(pixel[0], dilution)
          pixel[1] = mul_65535(pixel[1], dilution)
          pixel[2] = mul_65535(pixel[2], dilution)
        pixel[3] = dilution
      # Store Current Pixel
      dst[cursor + 0] = cast[cushort](pixel[0])
      dst[cursor + 1] = cast[cushort](pixel[1])
      dst[cursor + 2] = cast[cushort](pixel[2])
      dst[cursor + 3] = cast[cushort](pixel[3])
      # Next Pixel
      cursor += 4

proc water*(pipe: var NBrushPipeline, amount: cint) =
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
  pipe.blur(buffer, amount)

# -------------------------
# BRUSH PIPELINE BLUR PROCS
# -------------------------

proc blur*(pipe: var NBrushPipeline, size: cfloat) =
  # Scale Divisor Size
  let
    scale_w = 1.0 + (pipe.rw / pipe.w - 1.0) * size
    scale_h = 1.0 + (pipe.rh / pipe.h - 1.0) * size
    # Calculate Maximun Scale
    scale = max(scale_w, scale_h)
  # Clip Region Area
  pipe.clip()
  # Clip Scaled Size
  let
    # Region Position
    rx = pipe.rx
    ry = pipe.ry
    # Region Size
    rw = pipe.rw
    rh = pipe.rh
    # Calculate Scaled Size, Minimun 1
    sw = ceil(rw.float / scale).cint
    sh = ceil(rh.float / scale).cint
    # Calculate Scaled Level
    level = log2(scale).cint
    offset = cint(scale * 32768.0)
    # Calculate Fractional Downscale
    down_fx = fix_65535(sw, rw)
    down_fy = fix_65535(sh, rh)
    # Calculate Fractional Upscale
    up_fx = fix_65535(rw, sw)
    up_fy = fix_65535(rh, sh)
  # Configure Each Tile
  for tile in mitems(pipe.tiles):
    let
      render = addr tile.render
      b = addr tile.data.blur
    # Set Region Position
    b.x = cast[cshort](render.x - rx)
    b.y = cast[cshort](render.y - ry)
    # Set Region Size
    b.w = cast[cshort](rw)
    b.h = cast[cshort](rh)
    # Set Scaled Size
    b.sw = cast[cshort](sw)
    b.sh = cast[cshort](sh)
    # Set Downscale Fractional
    b.down_fx = down_fx
    b.down_fy = down_fy
    # Set Upscale Fractional
    b.up_fx = up_fx
    b.up_fy = up_fy
    # Set Offset Fractional
    b.offset = offset
    # Replace Current Level
    render.alpha = level
  # Override Parallel Check
  pipe.parallel = max(rw, rh) >= 32

proc smudge*(pipe: var NBrushPipeline, dx, dy: cfloat) =
  let
    # Current Position
    fx = cint(dx * 65536.0)
    fy = cint(dy * 65536.0)
  # Replace Copy Position
  for tile in mitems(pipe.tiles):
    let s = addr tile.data.smudge
    # Don't Copy First Point
    if pipe.alpha > 65535:
      s.dx = 0
      s.dy = 0
    else: # Fix16 Delta
      s.dx = fx
      s.dy = fy

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
  of bnSmudge: brush_smudge_first(render)

proc mt_stage1(tile: ptr NBrushTile) =
  let render = addr tile.render
  # -- Stage1 Blending Mode
  case tile.blend
  of bnAverage: brush_normal_blend(render)
  of bnWater: brush_water_blend(render)
  of bnMarker: brush_flat_blend(render)
  of bnBlur: brush_blur_blend(render)
  of bnSmudge: brush_smudge_blend(render)
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
