from math import sqrt, ceil, nextPowerOfTwo
import ../libs/gl
import ../libs/ft2

type # Atlas Objects
  SKYNode = object
    x, y, w: int16
  TEXGlyph = object
    glyphIDX*: uint32 # FT2 Glyph Index
    x1*, x2*, y1*, y2*: int16 # UV Coords
    xo*, yo*, advance*: int16 # Positioning
    w*, h*: int16 # Bitmap Dimensions
  CTXAtlas* = object
    # FT2 FONT FACE
    face: FT2Face
    # SKYLINE BIN PACKING
    w, h: int32 # Dimensions
    nodes: seq[SKYNode]
    # GLYPHS INFORMATION
    lookup*: seq[uint16]
    glyphs*: seq[TEXGlyph]
    # OPENGL INFORMATION
    texID*: uint32 # Texture
    whiteU*, whiteV*: int16
    nW*, nH*: float32 # Normalized

let # Charset Common Ranges for Preloading
  csLatin* = # English, Spanish, etc.
    [0x0020'u16, 0x00FF'u16]
  csKorean* = # All Korean letters
    [0x0020'u16, 0x00FF'u16,
     0x3131'u16, 0x3163'u16,
     0xAC00'u16, 0xD79D'u16]
  csJapaneseChinese* = # Hiragana, Katakana
    [0x0020'u16, 0x00FF'u16,
     0x2000'u16, 0x206F'u16,
     0x3000'u16, 0x30FF'u16,
     0x31F0'u16, 0x31FF'u16,
     0xFF00'u16, 0xFFEF'u16]
  csCyrillic* = # Russian, Euraska, etc.
    [0x0020'u16, 0x00FF'u16,
     0x0400'u16, 0x052F'u16,
     0x2DE0'u16, 0x2DFF'u16,
     0xA640'u16, 0xA69F'u16]
  # Charsets from dear imgui

# -------------------------------------------
# FONTSTASH'S ATLAS SKYLINE BIN PACKING PROCS
# -------------------------------------------

proc rectFits(atlas: var CTXAtlas, idx: int32, w,h: int16): int16 =
  if atlas.nodes[idx].x + w > atlas.w: return -1
  var # Check if there is enough space at location i
    y = atlas.nodes[idx].y
    spaceLeft = w
    i = idx
  while spaceLeft > 0:
    if i == len(atlas.nodes): 
      return -1
    y = max(y, atlas.nodes[i].y)
    if y + h > atlas.h: 
      return -1
    spaceLeft -= atlas.nodes[i].w
    inc(i)
  return y # Yeah, Rect Fits

proc addSkylineNode(atlas: var CTXAtlas, idx: int32, x,y,w,h: int16) =
  block: # Add New Node, not OOM checked
    var node: SKYNode
    node.x = x; node.y = y+h; node.w = w
    atlas.nodes.insert(node, idx)
  var i = idx+1 # New Iterator
  # Delete skyline segments that fall under the shadow of the new segment
  while i < len(atlas.nodes):
    let # Prev Node and i-th Node
      pnode = addr atlas.nodes[i-1]
      inode = addr atlas.nodes[i]
    if inode.x < pnode.x + pnode.w:
      let shrink =
        pnode.x - inode.x + pnode.w
      inode.x += shrink
      inode.w -= shrink
      if inode.w <= 0:
        atlas.nodes.delete(i)
        dec(i) # Reverse i-th
      else: break
    else: break
    inc(i) # Next Node
  # Merge same height skyline segments that are next to each other
  i = 0 # Reset Iterator
  while i < high(atlas.nodes):
    let # Next Node and i-th Node
      nnode = addr atlas.nodes[i+1]
      inode = addr atlas.nodes[i]
    if inode.y == nnode.y:
      inode.w += nnode.w
      atlas.nodes.delete(i+1)
      dec(i) # Reverse i-th
    inc(i) # Next Node

proc pack*(atlas: var CTXAtlas, w, h: int16): tuple[x, y: int16] =
  var # Initial Best Fits
    bestIDX = -1'i32
    bestX = -1'i16
    bestY = -1'i16
  block: # Find Best Fit
    var # Temporal Vars
      bestH = atlas.h
      bestW = atlas.w
      i: int32 = 0
    while i < len(atlas.nodes):
      let y = atlas.rectFits(i, w, h)
      if y != -1: # Fits
        let node = addr atlas.nodes[i]
        if y + h < bestH or y + h == bestH and node.w < bestW:
          bestIDX = i
          bestW = node.w
          bestH = y + h
          bestX = node.x
          bestY = y
      inc(i) # Next Node
  if bestIDX != -1: # Can be packed
    addSkylineNode(atlas, bestIDX, bestX, bestY, w, h)
    # Return Packing Position
    result.x = bestX; result.y = bestY
  else: result.x = -1; result.y = -1

# ---------------------------
# ATLAS GLYPH RENDERING PROCS
# ---------------------------

proc renderCharcode(atlas: var CTXAtlas, code: uint16, temp: var seq[uint32]) =
  if ft2_loadChar(atlas.face, code, FT_LOAD_RENDER) == 0:
    let slot = atlas.face.glyph # Shorcut
    # -- Add Glyph to Glyph Cache
    atlas.glyphs.add TEXGlyph(
      glyphIDX: slot.glyph_index,
      # Save new dimensions, very small values
      w: cast[int16](slot.bitmap.width),
      h: cast[int16](slot.bitmap.rows),
      # Save position offsets, very small values
      xo: cast[int16](slot.bitmap_left), # xBearing
      yo: cast[int16](slot.bitmap_top), # yBearing
      advance: cast[int16](slot.advance.x shr 6)
    ) # End Add Glyph to Glyph Cache
    # -- Render Glyph as RGBA8888
    var # Copy pixels to temporal buffer
      i = len(temp) # Starting Position
      j: uint32 # Bitmap Position
    # Expand Temporal Buffer for Copy Bitmap
    temp.setLen(i + int slot.bitmap.width * slot.bitmap.rows)
    # Copy and Convert Pixels to RGBA8888
    while i < len(temp): # Merge Pixel to alpha channel of a White Pixel
      temp[i] = cast[uint32](slot.bitmap.buffer[j]) shl 24 or 0x00FFFFFF
      inc(i); inc(j) # Next RGBA8888 Pixel and 8bit Pixel
    # -- Save Glyph Index at Lookup
    if code != 0xFFFF: # No save in Fallback
      atlas.lookup[code] = uint16(high atlas.glyphs)
  elif code != 0xFFFF: atlas.lookup[code] = 0xFFFF

proc renderCharset(atlas: var CTXAtlas, charset: openArray[uint16]) =
  var temp, dest: seq[uint32] # Temporal Buffers
  # -- Render Fallback Glyph
  renderCharcode(atlas, 0xFFFF, temp)
  # -- Render Charset Ranges
  block: # s..e pairs
    var # Iterators
      s, e: uint16 # Charcode Iter
      i = 0 # Range Iter
    while i < len(charset):
      s = charset[i] # Start
      e = charset[i+1] # End
      # Check if lookup is big enough
      if int(e) >= len(atlas.lookup):
        atlas.lookup.setLen(1 + int e)
      elif int(s) >= len(atlas.lookup):
        atlas.lookup.setLen(1 + int s)
      # Render Charcodes one by one
      while s <= e: # Iterate Charcodes
        renderCharcode(atlas, s, temp)
        inc(s) # Next Charcode
      i += 2 # Next Range Pair
  # -- Alloc Arranged Atlas Buffer
  block: # Get power of two side*2 * side
    var area: uint32 # Total used area
    # Calculate Total Area of Glyphs
    for glyph in mitems(atlas.glyphs):
      area += # Avoid overflow
        cast[uint32](glyph.w) * 
        cast[uint32](glyph.h)
    # Calculate Next Power of Two Side using Calculated Area
    area = area.float32.sqrt().ceil().int.nextPowerOfTwo().uint32
    # Set new Atlas Diemsions
    atlas.w = cast[int32](area shl 1)
    atlas.h = cast[int32](area)
    # Set Normalized Atlas Dimensions for get MAD
    atlas.nW = 1 / atlas.w # vertex.u * uDim.w 
    atlas.nH = 1 / atlas.h # vertex.v * uDim.h
    # Add Initial Skyline Node
    atlas.nodes.add SKYNode(w: int16 atlas.w)
    # Alloc Buffer with new dimensions
    dest.setLen(area*area shl 1)
  # -- Arrange Glyphs Using Skyline
  var # Aux Pixel Vars
    cursor: int32 # Buffer Cursor
    point: tuple[x, y: int16] # Arranged
  for glyph in mitems(atlas.glyphs):
    point = pack(atlas, glyph.w, glyph.h)
    var # Copy Glyph Bitmap To New Position
      pixel = atlas.w * point.y + point.x
      i: int16 # Bitmap Row Iterator
    while i < glyph.h: # Copy Glyph Pixel Rows
      copyMem(addr dest[pixel], addr temp[cursor], int(glyph.w) * 4)
      cursor += glyph.w; pixel += atlas.w; inc(i) # Next Pixel Row
    # Save Texture UV Coordinates Box
    glyph.x1 = point.x; glyph.x2 = point.x + glyph.w
    glyph.y1 = point.y; glyph.y2 = point.y + glyph.h
  # -- Put a White Pixel in Atlas
  point = pack(atlas, 1, 1)
  dest[atlas.w * point.y + point.x] = high(uint32)
  atlas.whiteU = point.x; atlas.whiteV = point.y
  # -- Copy Arranged Atlas to Texture
  glGenTextures(1, addr atlas.texID)
  glBindTexture(GL_TEXTURE_2D, atlas.texID)
  # Clamp Atlas to Edge
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, cast[GLint](GL_CLAMP_TO_EDGE))
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, cast[GLint](GL_CLAMP_TO_EDGE))
  # Use Nearest Pixel Filter
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, cast[GLint](GL_NEAREST))
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, cast[GLint](GL_NEAREST))
  # Copy Arranged Bitmap Buffer to Texture
  glTexImage2D(GL_TEXTURE_2D, 0, cast[int32](GL_RGBA8), atlas.w, atlas.h, 0, GL_RGBA,
      GL_UNSIGNED_BYTE, addr dest[0])
  # Unbind White Pixel Texture
  glBindTexture(GL_TEXTURE_2D, 0)

# -------------------
# ATLAS CREATION PROC
# -------------------

proc newCTXAtlas*(ft2: FT2Library, charset: openArray[uint16]): CTXAtlas =
  # 1-A -- Create New Face, TODO: Use FT_New_Memory_Face
  if ft2_newFace(ft2, "data/font.ttf", 0, addr result.face) != 0:
    echo "ERROR: failed loading gui font file"
  if ft2_setCharSize(result.face, 0, 10 shl 6, 96, 96) != 0:
    echo "WARNING: font size was not setted properly"
  # 2 -- Render Selected Charset
  renderCharset(result, charset)