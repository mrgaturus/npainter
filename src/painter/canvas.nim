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
    x, y: int16
    buffer*: NTile
  NLayer = object
    ox*, oy*: int16
    blend: NLayerBlend
    flags: set[NLayerFlags]
    tiles*: seq[NLayerTile]
  # Canvas Object
  NCanvas* = object
    w*, rw*, tw*: int16
    h*, rh*, th*: int16
    layers: seq[NLayer]
    # Canvas Cache
    tiles*: seq[NTile]
  # Layer Composition
  NBlendBounds = enum # Tile Sub-Grid Bounds
    boundLeft, boundRight, boundTop, boundDown
  NBlendFunc = proc (dst: var NPixel, src: NPixel)

# -------------------------------
# CANVAS BASIC MANIPULATION PROCS
# -------------------------------

proc newCanvas*(w, h: int16): NCanvas =
  # Set Dimensions
  result.w = w; result.h = h
  # Set Residual Dimensions
  result.rw = w mod 256; result.rh = h mod 256
  # Set Tiled Dimensions, Residual is an extra tile
  result.tw = (w + result.rw) shr 8 + (result.rw > 0).int16
  result.th = (h + result.rh) shr 8 + (result.rh > 0).int16
  # Alloc Tile Indexes Tiled-W * Tiled-H
  result.tiles.setLen(result.tw * result.th)
  for tile in mitems(result.tiles):
    tile = new NTile

# -- Clearing --
proc clear*(tile: NTile) =
  zeroMem(addr tile[0], 
    65536 * NPixel.sizeof)

proc clear*(layer: var NLayer) =
  layer.ox = 0; layer.oy = 0
  layer.tiles.setLen(0)

proc clear*(canvas: var NCanvas) =
  for tile in mitems(canvas.tiles):
    tile.clear() # Clear Tiles

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

# -----------------------------
# TILE-CANVAS COMPOSITION PROCS
# -----------------------------
{.compile: "blend.c".} # Compile SSE4.1 Blend Modes
proc blend_normal(dst: var NPixel, src: NPixel) {.importc.}

# TODO: Can be parallelize easily, do a threadpool
proc composite(dst: var NCanvas, src: var NLayer) =
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
    blend: NBlendFunc = blend_normal
  var # Iterator Variables
    bounds: set[NBlendBounds]
    pdst, psrc: NTile
    tx, ty, ts: int16
    di, si, ei, j: uint32
  # Composite Each Tile To Canvas
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
      pdst = dst.tiles[ts]; j = pox
      di = poy shl 8 + pox; si = 0
      while di < 65536:
        blend(pdst[di], psrc[si])
        inc(di); inc(si); inc(j)
        if j == 256: # Next Stride
          di += pox; si += pox; j = pox
    # ------------------------
    # Composite Right-Top Tile
    ts += 1 # Next Tile at X
    if {boundRight, boundTop} <= bounds:
      pdst = dst.tiles[ts]
      di = poy shl 8; si = rox
      ei = 65535 - rox; j = rox
      while di <= ei:
        blend(pdst[di], psrc[si])
        inc(di); inc(si); inc(j)
        if j == 256: # Next Stride
          di += rox; si += rox; j = rox
    # -------------------------
    # Composite Right-Down Tile
    ts += dst.tw # Next Tile at Y
    if {boundRight, boundDown} <= bounds:
      pdst = dst.tiles[ts]; j = rox
      di = 0; si = roy shl 8 + rox
      while si < 65536:
        blend(pdst[di], psrc[si])
        inc(di); inc(si); inc(j)
        if j == 256: # Next Stride
          di += rox; si += rox; j = rox
    # ------------------------
    # Composite Left-Down Tile
    ts -= 1 # Prev Tile at X
    if {boundLeft, boundDown} <= bounds:
      pdst = dst.tiles[ts]
      di = pox; si = roy shl 8
      ei = 65535 - pox; j = pox
      while si <= ei:
        blend(pdst[di], psrc[si])
        inc(di); inc(si); inc(j)
        if j == 256: # Next Stride
          di += pox; si += pox; j = pox
    # Clear Checks
    bounds = {}

proc composite*(canvas: var NCanvas) =
  # Composite All Layers
  for layer in mitems(canvas.layers):
    if lfHidden in layer.flags:
      continue # Check if not Hidden
    canvas.composite(layer)
