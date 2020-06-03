# RGBA8 Pixel Format
# 256x256-Tiled Canvas

type
  NMask* = uint8 # 8bit Mask
  NPixel* = uint32 # RGBA8 Pixel
  NTile* = ref array[65536, NPixel] 
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
    w*, rw*, sw*: int32
    h*, rh*, sh*: int32
    layers: seq[NLayer]
    # Canvas Cache
    buffer*: seq[NPixel]
  # Layer-Layer Composition
  #NBlendBounds = enum
  #  boundLeft, boundRight
  #  boundTop, boundDown

# -------------------------------
# CANVAS BASIC MANIPULATION PROCS
# -------------------------------

proc newCanvas*(w, h: int16): NCanvas =
  # Set Dimensions
  result.w = w; result.h = h
  # Set Residual Dimensions
  result.rw = 256 - (w mod 256)
  result.rh = 256 - (h mod 256)
  # Set Canvas Amortized Dimensions
  result.sw = result.w + result.rw
  result.sh = result.h + result.rh
  # Alloc Canvas Pixel Buffer with Amortized
  setLen(result.buffer, result.sw * result.sh)

# -- Clearing --
proc clear*(tile: NTile) =
  zeroMem(cast[pointer](tile), 
    65536 * NPixel.sizeof)

proc clear*(layer: var NLayer) =
  layer.x = 0; layer.y = 0
  layer.tiles.setLen(0)

# Todo: Clear Parallel
proc clear*(canvas: var NCanvas) =
  zeroMem(addr canvas.buffer[0], 
    cast[uint32](canvas.sw) * 
    cast[uint32](canvas.sh) * 
    cast[uint32](sizeof NPixel))

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

# Temporal Pointer Aritmetic
template `+=`(p: pointer, s: int32) =
  {.emit: [p, " += ", s, ";"].}

# a: Coordinate, b: Dimension
template clip(a, b: int32) =
  if a < 0:
    b = a + 256
    if b <= 0:
      continue
    else: a = 0
  elif b > 256:
    b = 256
  elif b <= 0:
    continue

proc composite*(canvas: var NCanvas, layer: var NLayer) =
  var # Positions and Strides
    ss, so: int32
    x, y, w, h: int32
    dst, src: ptr NPixel
  let # Shorcut for Width
    ds = canvas.sw
  for tile in mitems(layer.tiles):
    # Tile Canvas Coordinates
    x = (tile.x shl 8) + layer.x
    y = (tile.y shl 8) + layer.y
    # Clip X Bound
    w = canvas.sw - x; clip(x, w)
    h = canvas.sh - y; clip(y, h)
    # Set X Stride
    ss = 256 - w
    # Prepare Source Cursor
    if x == 0: so += ss
    if y == 0: so += (256 - h) shl 8
    # Set Source and Destination Pointers
    src = addr tile.buffer[so]
    dst = addr canvas.buffer[
      y * ds + x]
    # Blend Pixels
    while h > 0:
      blend(dst, src, w)
      dst += ds; src += ss
      # Next Row
      dec(h)
    # Reset Cursor
    so = 0

proc composite*(canvas: var NCanvas) =
  # Composite All Layers
  for layer in mitems(canvas.layers):
    if lfHidden in layer.flags:
      continue # Check if not Hidden
    canvas.composite(layer)

# ---------------------------------
# LAYER-LAYER MERGERING COMPOSITION
# ---------------------------------

discard """
proc merge(dst, src: var NLayer) =
  let # Constants
    # Tile X Offsets
    tox = src.ox shr 8
    pox = cast[uint16](src.ox) mod 256
    rox = cast[uint16](256 - pox) # Residual
    # Tile Y Offsets
    toy = src.oy shr 8
    poy = cast[uint16](src.oy) mod 256
    roy = cast[uint16](256 - poy) # Residual
    # Blending Function (There Will more blend modes)
    #blend: NBlendFunc = blend_normal
  var # Iterator Variables
    bounds: set[NBlendBounds]
    pdst, psrc: NTile
    tx, ty, ts: int16
    di, de: uint32
  for tile in mitems(src.tiles):
    psrc = tile.buffer
    # Get Current Tile
    tx = tile.x + tox
    ty = tile.y + toy
    # Check Left-Right Boundaries
    if tx >= 0 and tx < dst.tw: bounds.incl boundLeft
    if pox > 0 and tx + 1 >= 0 and tx + 1 < dst.tw:
      bounds.incl boundRight
    # Check Top-Down Boundaries
    if ty >= 0 and ty < dst.th: bounds.incl boundTop
    if poy > 0 and ty + 1 >= 0 and ty + 1 < dst.th:
      bounds.incl boundDown
    # Is Visible at any Bound?
    if bounds == {}: continue
    # -----------------------
    # Composite Left-Top Tile
    ts = ty * dst.tw + tx # Tile at
    if {boundLeft, boundTop} <= bounds:
      pdst = dst.tiles[ts] # Lookup Tile
      di = poy shl 8 + pox; de = roy
      while de > 0:
        blend(pdst[di], 
          psrc[di], rox)
        di += 256; dec(de)
    # ------------------------
    # Composite Right-Top Tile
    ts += 1 # Next Tile at X
    if {boundRight, boundTop} <= bounds:
      pdst = dst.tiles[ts] # Lookup Tile
      di = poy shl 8; de = roy
      while de > 0:
        blend(pdst[di], 
          psrc[di], pox)
        di += 256; dec(de)
    # -------------------------
    # Composite Right-Down Tile
    ts += dst.tw # Next Tile at Y
    if {boundRight, boundDown} <= bounds:
      pdst = dst.tiles[ts] # Lookup Tile
      di = 0; de = poy
      while de > 0:
        blend(pdst[di], 
          psrc[di], pox)
        di += 256; dec(de)
    # ------------------------
    # Composite Left-Down Tile
    ts -= 1 # Prev Tile at X
    if {boundLeft, boundDown} <= bounds:
      pdst = dst.tiles[ts] # Lookup Tile
      di = pox; de = poy
      while de > 0:
        blend(pdst[di], 
          psrc[di], rox)
        di += 256; dec(de)
    # -- Clear Checks --
    bounds = {}
"""