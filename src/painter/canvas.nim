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
    # Canvas Cache
    buffer*: seq[NPixel]
  # Clip Composition
  NBlendClip = enum
    cTop, cDown
    cLeft, cRight

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
  # Alloc Canvas Pixel Buffer with Amortized
  setLen(result.buffer, result.cw * result.ch)

# -- Clearing --
proc clear*(tile: NTile) =
  zeroMem(cast[pointer](tile), 
    4096 * NPixel.sizeof)

proc clear*(layer: var NLayer) =
  layer.x = 0; layer.y = 0
  layer.tiles.setLen(0)

# Todo: Clear Parallel
proc clear*(canvas: var NCanvas) =
  zeroMem(addr canvas.buffer[0], 
    sizeof(NPixel) * canvas.cw * canvas.ch)

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
  # -- Clip Check Template
  template scissor() =
    # Check Left-Right Boundaries
    if sx >= 0 and sx < cw: clip.incl cLeft
    if dox > 0 and sx + rox >= 0 and sx + rox < cw:
      clip.incl cRight # With X Offset
    # Check Laterals Visibility
    if clip == {}: continue
    # Check Top-Down Boundaries
    if sy >= 0 and sy < ch: clip.incl cTop
    if doy > 0 and sy + roy >= 0 and sy + roy < ch:
      clip.incl cDown # With Y Offset
  # -- Blend Template
  template blend() =
    # - Calculate Stride Width
    if {cLeft, cRight} < clip:
      sw = 64
    elif cLeft in clip:
      sw = rox
    elif cRight in clip:
      sw = dox
      sc += rox
      src += rox
    # - Set Source Cursor
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
    # - Do Clipping
    scissor()
    # - Blend Top Tiles
    if cTop in clip:
      # Set Pointer Cursors
      sc = cw * sy + sx
      src = addr tile.buffer[0]
      # Blend Pixels
      si = roy; blend()
    # - Blend Down Tiles
    if cDown in clip:
      # Set Pointer Cursors
      sc = cw * (sy + roy) + sx
      src = addr tile.buffer[roy shl 6]
      # Blend Pixels
      si = doy; blend()
    # - Clear Clip
    clip = {}

proc composite*(canvas: var NCanvas) =
  # Composite All Layers
  for layer in mitems(canvas.layers):
    if lfHidden in layer.flags:
      continue # Check if not Hidden
    canvas.composite(layer)
