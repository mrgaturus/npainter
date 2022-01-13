from math import log2

type
  NMipmap = object
    w, h, offset: cint
  NTexture* = object
    # Buffer Size
    w, h, bytes: cint
    # Mipmapped Texture
    levels: seq[NMipmap]
    buffer: seq[uint8]
  NTextureMap = ptr UncheckedArray[uint8]
  NTextureRaw* = object
    w*, h*, level*: cint
    # Buffer Pointer
    buffer*: pointer

# -----------------------------------------
# TEXTURE GRAYSCALE MIPMAP GENERATION PROCS
# -----------------------------------------

proc average(tex: NTextureRaw, x, y: cint): uint8 =
  let
    w = tex.w
    h = tex.h
    # Pixel Buffer Mapping
    map = cast[NTextureMap](tex.buffer)
  var 
    pixel: cint
    # Current Cursor
    c1, c0 = y * w + x
    next = cint(x < w - 1)
  # Step Y Position
  if y < h - 1: c1 += w
  # Sum Pixel Neighbours
  pixel += cast[cint](map[c0 + 0])
  pixel += cast[cint](map[c0 + next])
  pixel += cast[cint](map[c1 + 0])
  pixel += cast[cint](map[c1 + next])
  # Return Averaged Pixel
  result = cast[uint8](pixel shr 2)

proc downscale(tex: NTextureRaw, map: NTextureMap): cint =
  let
    sw = max(tex.w shr 1, 1)
    sh = max(tex.h shr 1, 1)
  var pixel: uint8
  for y in 0 ..< sh:
    for x in 0 ..< sw:
      let
        xx = x shl 1
        yy = y shl 1
      pixel = average(tex, xx, yy)
      map[result] = pixel
      # Step Pixel
      inc(result)

proc mipmaps(tex: var NTexture) =
  var 
    mip: NMipmap
    # Texture Accesor
    raw: NTextureRaw
    map: NTextureMap
    # Buffer Size
    w = tex.w
    h = tex.h
    offset = w * h
  # Add First Offset
  mip.w = w
  mip.h = h
  mip.offset = 0
  tex.levels.add(mip)
  # Initialize Accesor
  raw.w = w
  raw.h = h
  raw.buffer = addr tex.buffer[0]
  # Initialize Buffer Target Mapping
  map = cast[NTextureMap](addr tex.buffer[offset])
  # Create Each Mipmap
  while w > 1 and h > 1:
    mip.offset = offset
    offset += downscale(raw, map)
    # Reduce Mipmap by One
    w = max(w shr 1, 1)
    h = max(h shr 1, 1)
    # Set Current Mipmap
    mip.w = w
    mip.h = h
    tex.levels.add(mip)
    # Set Current Accesor
    raw.w = w
    raw.h = h
    raw.buffer = map
    # Step Buffet Target Mapping
    map = cast[NTextureMap](addr tex.buffer[offset])

# -----------------------------------
# TEXTURE ACCESSOR MANIPULATION PROCS
# -----------------------------------

proc raw*(tex: ptr NTexture, scale: cfloat): NTextureRaw =
  let 
    level = max(0, -log2(scale).cint)
    mip = addr tex.levels[level]
  # Set Current Accesor
  result.w = mip.w
  result.h = mip.h
  result.buffer = addr tex.buffer[mip.offset]
  # Set Current Level
  result.level = level

# ----------------------
# TEXTURE CREATION PROCS
# ----------------------

proc newTexture*(w, h: cint, buffer: seq[uint8]): NTexture =
  result.buffer = buffer
  # Duplicate Buffer Length
  let l = result.buffer.len
  setLen(result.buffer, l shl 1)
  # Store Buffer Size
  result.bytes = cast[cint](l)
  # Set Buffer Dimensions
  result.w = w
  result.h = h
  # Calculate Mipmaps
  result.mipmaps()

# ------------------------------------
# DEBUG PROOF OF CONCEPT TESTING PROCS
# ------------------------------------
import nimPNG

proc newPNGTexture*(file: string): NTexture =
  let 
    b = loadPNG32(file)
    w = cast[cint](b.width)
    h = cast[cint](b.height)
  var
    cursor, calc: cint
    buffer: seq[uint8]
  # Convert Image to BlackWhite
  buffer.setLen(b.data.len shr 2)
  for p in mitems(buffer):
    let
      r = cast[cint](b.data[cursor + 0])
      g = cast[cint](b.data[cursor + 1])
      b = cast[cint](b.data[cursor + 2])
    # Calculate Grayscale Count
    calc = r * 13932 + g * 46870 + b * 4733
    calc = (calc + 65535) shr 16
    # Store Grayscaled
    p = cast[uint8](calc)
    # Step Four Pixels
    cursor += 4
  # Create New Texture
  result = newTexture(w, h, buffer)

proc debug*(tex: NTexture, file: string) =
  var buffer: seq[uint8]
  buffer.setLen(tex.bytes shl 2)
  for id, level in pairs(tex.levels):
    let
      w = level.w
      h = level.h
      offset = level.offset
      bytes = w * h
    var cursor: cint
    for i in 0 ..< bytes:
      let b = tex.buffer[i + offset]
      buffer[cursor + 0] = b
      buffer[cursor + 1] = b
      buffer[cursor + 2] = b
      buffer[cursor + 3] = 255
      # Next Pixel
      cursor += 4
    # Store PNG File
    discard savePNG32($id & file, buffer, w, h)
