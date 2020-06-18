# RGBA8 Pixel Format
# 256x256 Tiled Canvas
# 64x64   Tiled Layers

type
  NMask* = uint8 # 8bit Mask
  NPixel* = uint32 # RGBA8 Pixel
  NTile* = ref array[4096, NPixel]
  # Layer Objects
  NLayerBlend = enum
    lbNormal
  NLayerFlags = enum
    lfHidden,
    lfLocked,
    lfClipAlpha, # TODO
    lfClipGroup # TODO
  NLayerTile = object
    x*, y*: int32
    buffer*: NTile
  NLayer = object
    x*, y*: int32
    blend*: NLayerBlend
    flags*: set[NLayerFlags]
    tiles*: seq[NLayerTile]
  # Canvas Object
  NCanvas* = object
    w*, rw*, cw*: int32
    h*, rh*, ch*: int32
    layers: seq[NLayer]
    # Canvas Buffer & Mask
    buffer*: seq[NPixel]
    mask*: seq[NPixel]
    # Canvas Tile Stencil
    stencil*: seq[bool]
  # Clip Composition
  NBlendClip = enum
    cTopLeft, cTopRight
    cDownLeft, cDownRight

# -------------------------------
# CANVAS BASIC MANIPULATION PROCS
# -------------------------------

proc newCanvas*(w, h: int16): NCanvas =
  # Set New Dimensions
  result.w = w; result.h = h
  # Set Residual Dimensions
  result.rw = 256 - (w mod 256)
  result.rh = 256 - (h mod 256)
  # Set Canvas Amortized Dimensions
  result.cw = result.w + result.rw
  result.ch = result.h + result.rh
  # Alloc Canvas Pixel Buffer
  setLen(result.buffer,
    result.cw * result.ch)
  # Alloc Canvas Pixel Mask
  setLen(result.mask,
    result.buffer.len)
  # Alloc Canvas Stencil
  setLen(result.stencil,
    result.buffer.len shr 12)

# -- Clearing Canvas Buffers --
proc clearPixels*(canvas: var NCanvas) =
  # TODO: Clear only stenciled
  zeroMem(addr canvas.buffer[0],
    len(canvas.buffer) * NPixel.sizeof)

proc clearMask*(canvas: var NCanvas) =
  zeroMem(addr canvas.mask[0],
    len(canvas.mask) * NPixel.sizeof)

proc clearStencil*(canvas: var NCanvas) =
  zeroMem(addr canvas.stencil[0],
    len(canvas.stencil) * bool.sizeof)

# -- Clearing Tile/Layers --
proc clear*(tile: NTile) =
  zeroMem(cast[pointer](tile), 
    4096 * NPixel.sizeof)

proc clear*(layer: var NLayer) =
  layer.x = 0; layer.y = 0
  layer.tiles.setLen(0)

# -- Add / Delete Layer Tiles --
proc add*(layer: var NLayer, x, y: int16) =
  layer.tiles.add(
    NLayerTile(
      x: x, y: y,
      buffer: new NTile)
  ) # Alloc New Tile

proc del*(layer: var NLayer, tile: NTile) =
  var i: int32
  while i < len(layer.tiles):
    if layer.tiles[i].buffer == tile: 
      layer.tiles.del(i); break
    inc(i); # Next Layer

# -- Add / Delete Canvas Layers --
proc add*(canvas: var NCanvas) =
  setLen(canvas.layers, 
    canvas.layers.len + 1)

proc del*(canvas: var NCanvas, idx: int32) =
  canvas.layers.delete(idx)

template `[]`*(canvas: var NCanvas, idx: int32): 
  ptr NLayer = addr canvas.layers[idx]

# ------------------------------
# LAYER-CANVAS COMPOSITION PROCS
# ------------------------------

{.compile: "blend.c".} # Compile SSE4.1 Blend Modes
proc blend(dst, src: pointer, n: int32) {.importc.}

# Pointer Aritmetic for Optimization
template `+=`(p: pointer, s: int32) =
  {.emit: [p, " += ", s, ";"].}

proc composite*(canvas: var NCanvas, layer: var NLayer) =
  let # Constants
    # Canvas Dimensions
    cw = canvas.cw
    ch = canvas.ch
    # Tile X Constants
    pox = layer.x
    dox = pox and 0x3f
    rox = 64 - dox
    # Tile Y Constants
    poy = layer.y
    doy = poy and 0x3f
    roy = 64 - doy
  var # Pointer Cursors
    dst, src: ptr NPixel
    clip: set[NBlendClip]
    sx, sy, sc, si, sw: int32
  # -- Scissor Template
  template scissor() =
    # Check Left-Right Boundaries
    if sx >= 0 and sx < cw:
      clip = clip + {cTopLeft, cDownLeft}
    if dox > 0 and sx + rox >= 0 and sx + rox < cw:
      clip = clip + {cTopRight, cDownRight}
    # Check Top-Down Boundaries
    if sy < 0 or sy >= ch:
      clip = clip - {cTopLeft, cTopRight}
    if doy == 0 or sy + roy < 0 or sy + roy >= ch:
      clip = clip - {cDownLeft, cDownRight}
    # Check Tile Visibility
    if clip == {}: continue
  # -- Stencil Template
  template stencil() =
    discard
  # -- Blend Template
  template blend(left, right: NBlendClip) =
    # - Calculate Stride Width
    if {left, right} <= clip:
      sw = 64
    elif left in clip:
      sw = rox
    elif right in clip:
      sw = dox
      sc += rox
      src += rox
    # - Set Destination Cursor
    dst = addr canvas.buffer[sc]
    # - Blend Strides
    while si > 0:
      blend(dst, src, sw)
      dst += cw; src += 64
      dec(si) # Next Row
  # -- Composite Each Tile
  for tile in mitems(layer.tiles):
    sx = (tile.x shl 6) + pox
    sy = (tile.y shl 6) + poy
    # - Do Clipping Tests
    scissor(); stencil()
    # - Blend Top Tiles
    if clip * {cTopLeft, cTopRight} != {}:
      # Set Strides and Cursors
      sc = cw * sy + sx; si = roy
      src = addr tile.buffer[0]
      # Blend Pixel Strides
      blend(cTopLeft, cTopRight)
    # - Blend Down Tiles
    if clip * {cDownLeft, cDownRight} != {}:
      # Set Strides and Cursors
      sc = cw * (sy + roy) + sx; si = doy
      src = addr tile.buffer[roy shl 6]
      # Blend Pixel Strides
      blend(cDownLeft, cDownRight)
    # - Clear Clip
    clip = {}

proc composite*(canvas: var NCanvas) =
  # Composite All Layers
  for layer in mitems(canvas.layers):
    if lfHidden in layer.flags:
      continue # Skip Hidden
    canvas.composite(layer)
