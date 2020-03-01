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
  BUFStatus = enum # Bitmap Buffer Status
    bufNormal, bufDirty, bufResize
  CTXAtlas* = object
    # FT2 FONT FACE
    face: FT2Face
    # SKYLINE BIN PACKING
    w, h: int32 # Dimensions
    nodes: seq[SKYNode]
    # GLYPHS INFORMATION
    lookup: seq[uint16]
    glyphs: seq[TEXGlyph]
    # GLYPH ATLAS BITMAP
    buffer: seq[byte]
    status: BUFStatus
    x1, x2, y1, y2: int16
    # OPENGL INFORMATION
    texID*: uint32 # Texture
    whiteU*, whiteV*: int16
    rw*, rh*: float32 # Normalized
    # OFFSET Y - TOP TO BOTTOM
    offsetY*: int16

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

proc renderFallback(atlas: var CTXAtlas) =
  # Add A Glyph for a white rectangle
  atlas.glyphs.add TEXGlyph(
    glyphIDX: 0, # Use Invalid IDX
    w: atlas.offsetY shr 1, # W is Half H
    h: atlas.offsetY, # H is Font Size
    xo: 1, yo: atlas.offsetY, # xBearing, yBearing
    advance: atlas.offsetY shr 1 + 2 # *[]*
  ) # End Add Glyph to Glyph Cache
  # Alloc White Rectangle
  var i = len(atlas.buffer)
  atlas.buffer.setLen(i + atlas.offsetY * atlas.offsetY shr 1)
  while i < len(atlas.buffer): 
    atlas.buffer[i] = high(byte); inc(i)

proc renderCharcode(atlas: var CTXAtlas, code: uint16) =
  let glyphIDX = ft2_getCharIndex(atlas.face, code)
  if glyphIDX != 0 and ft2_loadGlyph(atlas.face, glyphIDX, FT_LOAD_RENDER) == 0:
    let slot = atlas.face.glyph # Shorcut
    # -- Add Glyph to Glyph Cache
    atlas.glyphs.add TEXGlyph(
      glyphIDX: glyphIDX, # Save FT2 Index
      # Save new dimensions, very small values
      w: cast[int16](slot.bitmap.width),
      h: cast[int16](slot.bitmap.rows),
      # Save position offsets, very small values
      xo: cast[int16](slot.bitmap_left), # xBearing
      yo: cast[int16](slot.bitmap_top), # yBearing
      advance: cast[int16](slot.advance.x shr 6)
    ) # End Add Glyph to Glyph Cache
    # -- Copy Bitmap to temporal buffer
    # Expand Temporal Buffer for Copy Bitmap
    let i = len(atlas.buffer) # Pivot Pixel Index before Expand
    atlas.buffer.setLen(i + int slot.bitmap.width * slot.bitmap.rows)
    # Copy Bitmap To Temporal Buffer
    if i < len(atlas.buffer): # Is Really Allocated?
      copyMem(addr atlas.buffer[i], slot.bitmap.buffer, 
        slot.bitmap.width * slot.bitmap.rows)
    # -- Save Glyph Index at Lookup
    atlas.lookup[code] = uint16(high atlas.glyphs)
  else: atlas.lookup[code] = 0xFFFF

proc renderCharset(atlas: var CTXAtlas, charset: openArray[uint16]) =
  var dest: seq[byte] # Arranged Buffer
  # -- Render Fallback Glyph
  renderFallback(atlas)
  block: # -- Render Charset Ranges
    var # Iterators
      s, e: uint16 # Charcode Iter
      i = 0 # Range Iter
    while i < len(charset):
      s = charset[i] # Start
      e = charset[i+1] # End
      # Check if lookup is big enough
      if int32(e) >= len(atlas.lookup):
        atlas.lookup.setLen(1 + int32 e)
      elif int32(s) >= len(atlas.lookup):
        atlas.lookup.setLen(1 + int32 s)
      # Render Charcodes one by one
      while s <= e: # Iterate Charcodes
        renderCharcode(atlas, s)
        inc(s) # Next Charcode
      i += 2 # Next Range Pair
  block: # -- Alloc Arranged Atlas Buffer
    let side = len(atlas.buffer).float32.sqrt().ceil().int.nextPowerOfTwo()
    # Set new Atlas Diemsions
    atlas.w = cast[int32](side shl 1)
    atlas.h = cast[int32](side)
    # Set Normalized Atlas Dimensions for get MAD
    atlas.rw = 1 / atlas.w # vertex.u * uDim.w
    atlas.rh = 1 / atlas.h # vertex.v * uDim.h
    # Add Initial Skyline Node
    atlas.nodes.add SKYNode(w: int16 atlas.w)
    # Alloc Buffer with new dimensions
    dest.setLen(side*side shl 1)
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
      copyMem(addr dest[pixel], addr atlas.buffer[cursor], glyph.w)
      cursor += glyph.w; pixel += atlas.w; inc(i) # Next Pixel Row
    # Save Texture UV Coordinates Box
    glyph.x1 = point.x; glyph.x2 = point.x + glyph.w
    glyph.y1 = point.y; glyph.y2 = point.y + glyph.h
  # -- Use Fallback for Locate White Pixel
  atlas.whiteU = atlas.glyphs[0].x1
  atlas.whiteV = atlas.glyphs[0].y1
  # -- Copy Arranged Atlas to Texture
  glGenTextures(1, addr atlas.texID)
  glBindTexture(GL_TEXTURE_2D, atlas.texID)
  # Clamp Atlas to Edge
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, cast[GLint](GL_CLAMP_TO_EDGE))
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, cast[GLint](GL_CLAMP_TO_EDGE))
  # Use Nearest Pixel Filter
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, cast[GLint](GL_NEAREST))
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, cast[GLint](GL_NEAREST))
  # Swizzle pixel components to 1-1-1-RED
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_R, GL_ONE)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_G, GL_ONE)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_B, GL_ONE)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_A, cast[GLint](GL_RED))
  # Copy Arranged Bitmap Buffer to Texture
  glTexImage2D(GL_TEXTURE_2D, 0, cast[int32](GL_R8), atlas.w, atlas.h, 0, GL_RED,
      GL_UNSIGNED_BYTE, addr dest[0])
  # Unbind White Pixel Texture
  glBindTexture(GL_TEXTURE_2D, 0)
  # -- Replace Current Buffer
  atlas.buffer = dest

proc renderOnDemand(atlas: var CTXAtlas, code: uint16): ptr TEXGlyph =
  let glyphIDX = ft2_getCharIndex(atlas.face, code)
  if glyphIDX != 0 and ft2_loadGlyph(atlas.face, glyphIDX, FT_LOAD_RENDER) == 0:
    var # Auxiliar Vars
      glyph: ptr TEXGlyph
      buffer: cstring
    block: # -- Save New Glyph to Glyphs Seq
      let slot = atlas.face.glyph # Shorcut
      # Expand Glyphs for a New Glyph
      atlas.glyphs.setLen(1 + atlas.glyphs.len)
      glyph = addr atlas.glyphs[^1]
      # Save FT2 Glyph Index
      glyph.glyphIDX = glyphIDX
      # Save Bitmap Dimensions
      glyph.w = cast[int16](slot.bitmap.width)
      glyph.h = cast[int16](slot.bitmap.rows)
      # Save Position Offsets
      glyph.xo = cast[int16](slot.bitmap_left)
      glyph.yo = cast[int16](slot.bitmap_top)
      glyph.advance = cast[int16](slot.advance.x shr 6)
      # Set Aux Buffer Pointer
      buffer = slot.bitmap.buffer
    block: # -- Arrange Glyph To Atlas
      var point = pack(atlas, glyph.w, glyph.h)
      if point.x == -1 or point.y == -1:
        let stride = atlas.w # Prev W
        # Expand Atlas To Next Power Of Two
        if atlas.w == atlas.h:
          atlas.w *= 2; atlas.rw *= 0.5
          atlas.nodes.add SKYNode(
            x: int16 stride, y: 0, 
            w: int16 atlas.w - stride)
        else: atlas.h *= 2; atlas.rh *= 0.5
        # Move Buffer to a new Seq
        var # Copy Rows
          dest: seq[byte]
          i, k: int32
        dest.setLen(atlas.w * atlas.h)
        while i < len(atlas.buffer):
          copyMem(addr dest[k], addr atlas.buffer[i], stride)
          i += stride; k += atlas.w
        # Replace Buffer With New One
        atlas.buffer = dest
        # Try Pack Again, Guaranted
        point = pack(atlas, glyph.w, glyph.h)
        # Mark as Invalid
        atlas.status = bufResize
      elif atlas.status == bufNormal:
        atlas.status = bufDirty
      # Save New Packed UV Coordinated to Glyph
      glyph.x1 = point.x; glyph.x2 = point.x + glyph.w
      glyph.y1 = point.y; glyph.y2 = point.y + glyph.h
      # Extend Dirty Rect
      if atlas.status == bufDirty:
        atlas.x1 = min(atlas.x1, glyph.x1)
        atlas.y1 = min(atlas.y1, glyph.y1)
        atlas.x2 = max(atlas.x2, glyph.x2)
        atlas.y2 = max(atlas.y2, glyph.y2)
    # -- Copy New Glyph To Atlas Buffer
    var # Copy Rows Iterator
      pixel = atlas.w * glyph.y1 + glyph.x1
      i: int16 # Pixel Row
    while i < glyph.h:
      copyMem(addr atlas.buffer[pixel], 
        addr buffer[glyph.w * i], glyph.w)
      pixel += atlas.w; inc(i)
    # -- Save Glyph Index at Lookup
    atlas.lookup[code] = uint16(high atlas.glyphs)
    glyph # Return Recently Created Glyph
  else: atlas.lookup[code] = 0xFFFF; addr atlas.glyphs[0]

# -------------------
# ATLAS CREATION PROC
# -------------------

proc newCTXAtlas*(ft2: FT2Library, charset: openArray[uint16]): CTXAtlas =
  # 1-A -- Create New Face, TODO: Use FT_New_Memory_Face
  if ft2_newFace(ft2, "data/font.ttf", 0, addr result.face) != 0:
    echo "ERROR: failed loading gui font file"
  if ft2_setCharSize(result.face, 0, 10 shl 6, 96, 96) != 0:
    echo "WARNING: font size was not setted properly"
  # 2 -- Set max y offset for top-to-bottom positioning
  result.offsetY = # Ascender - -Descender = Offset Y
    (result.face.ascender + result.face.descender) shr 6
  # 3 -- Render Selected Charset
  renderCharset(result, charset)

# ----------------------
# ATLAS ON RUNNING PROCS
# ----------------------

# Very fast uint16 Rune Iterator
iterator runes16*(str: string): uint16 =
  var # Small Iterator
    i = 0'i32 # 2gb string?
    result: uint16 # 2byte
  while i < len(str):
    if str[i].uint8 <= 128:
      result = str[i].uint16
      inc(i, 1) # Move 1 Byte
    elif str[i].uint8 shr 5 == 0b110:
      result = # Use 2 bytes
        (str[i].uint16 and 0x1f) shl 6 or
        str[i+1].uint16 and 0x3f
      inc(i, 2) # Move 2 Bytes
    elif str[i].uint8 shr 4 == 0b1110:
      result = # Use 3 bytes
        (str[i].uint16 and 0xf) shl 12 or
        (str[i+1].uint16 and 0x3f) shl 6 or
        str[i+2].uint16 and 0x3f
      inc(i, 3) # Move 3 bytes
    else: inc(i, 1); continue
    # Yield Rune
    yield result

proc check*(atlas: var CTXAtlas) =
  case atlas.status:
  of bufNormal: return
  of bufDirty: # Has New Glyphs
    # Ajust Unpack Aligment for copy
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
    glPixelStorei(GL_UNPACK_ROW_LENGTH, atlas.w)
    glPixelStorei(GL_UNPACK_SKIP_PIXELS, atlas.x1)
    glPixelStorei(GL_UNPACK_SKIP_ROWS, atlas.y1)
    # Copy Dirty Area to Texture
    glTexSubImage2D(GL_TEXTURE_2D, 0, atlas.x1, atlas.y1, 
      atlas.x2 - atlas.x1, atlas.y2 - atlas.y1, GL_RED, 
      GL_UNSIGNED_BYTE, addr atlas.buffer[0])
    # Reset Unpack Aligment to default
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4)
    glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)
    glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0)
    glPixelStorei(GL_UNPACK_SKIP_ROWS, 0)
    # Set Buffer to Normal
    atlas.status = bufNormal
  of bufResize: # Has Been Resized
    glTexImage2D(GL_TEXTURE_2D, 0, cast[int32](GL_R8), 
      atlas.w, atlas.h, 0, GL_RED, GL_UNSIGNED_BYTE, 
      addr atlas.buffer[0])
    # Set Buffer to Normal
    atlas.status = bufNormal
  # Reset Dirty Texture Region
  atlas.x1 = cast[int16](atlas.w)
  atlas.y1 = cast[int16](atlas.h)
  atlas.x2 = 0; atlas.y2 = 0

proc lookup*(atlas: var CTXAtlas, charcode: uint16): ptr TEXGlyph =
  # Check if lookup needs expand
  if int32(charcode) >= len(atlas.lookup):
    atlas.lookup.setLen(1 + int32 charcode)
  # Get Glyph Index of the lookup
  let lookup = atlas.lookup[charcode]
  case lookup # Check Found Index
  of 0: renderOnDemand(atlas, charcode)
  of 0xFFFF: addr atlas.glyphs[0]
  else: addr atlas.glyphs[lookup]