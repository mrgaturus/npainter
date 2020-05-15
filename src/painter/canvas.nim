# RGBA8 Pixel Format
# 256x256-Tiled Canvas

type
  NMask* = uint8 # 8bit Mask
  NPixel* = uint32 # RGBA8 Pixel
  NTile = ref array[65536, NPixel]
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
    buffer: NTile
  NLayer = object
    ox, oy: int16
    blend: NLayerBlend
    flags: set[NLayerFlags]
    tiles: seq[NLayerTile]
  # Canvas Object
  NCanvas* = object
    w, rw, tw: int32
    h, rh, th: int32
    layers: seq[NLayer]
    # Canvas Cache
    tiles: seq[NTile]

# ------------------------------
# LAYER BASIC MANIPULATION PROCS
# ------------------------------

proc clear*(tile: NTile) =
  zeroMem(addr tile[0], 
    65536 * NPixel.sizeof)

proc clear*(layer: var NLayer) =
  layer.ox = 0; layer.oy = 0
  layer.tiles.setLen(0)

proc addTile*(layer: var NLayer, x, y: int16) =
  layer.tiles.add(
    NLayerTile(
      x: x, y: y,
      buffer: new NTile)
  ) # Alloc New Tile

# -------------------------------
# CANVAS BASIC MANIPULATION PROCS
# -------------------------------

proc newCanvas*(w, h: int16): NCanvas =
  # Set Dimensions
  result.w = w; result.h = h
  # Set Residual Dimensions
  result.rw = w mod 256
  result.rh = h mod 256
  # Set Tiled Dimensions, Residual is an extra tile
  result.tw = (w + result.rw) shr 8 + (result.rw > 0).int32
  result.th = (h + result.rh) shr 8 + (result.rh > 0).int32
  # Alloc Tile Indexes Tiled-W * Tiled-H
  result.tiles.setLen(result.tw * result.th)

proc addLayer*(canvas: var NCanvas) =
  setLen(canvas.layers, 
    canvas.layers.len + 1)

proc delLayer*(canvas: var NCanvas, idx: int32) =
  canvas.layers.delete(idx)

# ----------------------------
# LAYER FULL COMPOSITION PROCS
# ----------------------------

