from math import sqrt, ceil, nextPowerOfTwo
#import ../libs/gl
import ../libs/ft2

type # Atlas Objects
  SKYNode = object
    x, y, w: int32
  TEXGlyph = object
    glyphIDX: uint32 # FT2 Glyph Index
    x1, x2, y1, y2: float32 # UV Coords
    x, y, advance: int32 # Positioning
    w, h: uint32 # Bitmap Dimensions
  CTXAtlas* = object
    w*, h*: int32
    texID: uint32
    # FT2 FONT FACE
    face: FT2Face
    # GLYPHS INFORMATION
    charset: seq[uint16]
    glyphs: seq[TEXGlyph]
    # SKYLINE BIN PACKING
    nodes: seq[SKYNode]
    # TESTING PROPOUSES
    test*: seq[uint32]
  LANGCharset* = enum
    csLatin, csCyrillic # English, Spanish, Russian, etc
    csJapanese, csChinese, csKorean # Principal Asiatic
const # Fallback Indexes
  #NOT_LOADED = 0 # Not yet rendered in atlas
  NOT_FOUND = 0xFFFD # Not found on font face
let csRanges = # Full Latin + Asiatic/Cyrillic
  [0x0020'u16..0x00FF'u16, # 0 - Full Latin
   0x3131'u16..0x3163'u16, # 1 - Korean Start
   0xAC00'u16..0xD79D'u16, # 2 - Korean End
   0x3000'u16..0x30FF'u16, # 3 - Japanese/Chinese Start
   0x31F0'u16..0x31FF'u16, # 4 |
   0xFF00'u16..0xFFEF'u16, # 5 - Japanese End
   0x2000'u16..0x206F'u16, # 6 - Chinese End
   0x0400'u16..0x052F'u16, # 7 - Cyrillic Start
   0x2DE0'u16..0x2DFF'u16, # 8 |
   0xA640'u16..0xA69F'u16] # 9 - Cyrillic End

# -------------------------------------------
# FONTSTASH'S ATLAS SKYLINE BIN PACKING PROCS
# -------------------------------------------

proc rectFits(atlas: var CTXAtlas, idx, w,h: int32): int32 =
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

proc addSkylineNode(atlas: var CTXAtlas, idx, x,y,w,h: int32) =
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
      let shrink: int32 =
        pnode.x + pnode.w - inode.x
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

proc pack*(atlas: var CTXAtlas, w, h: int32, rx, ry: var int32): bool =
  var # Initial Best Fits
    bestIDX = -1'i32
    bestX = -1'i32
    bestY = -1'i32
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
  result = bestIDX != -1
  if result: # Can be packed
    addSkylineNode(atlas, bestIDX, bestX, bestY, w, h)
    # Return Packing Position
    rx = bestX; ry = bestY

# ---------------------------
# ATLAS GLYPH RENDERING PROCS
# ---------------------------

proc convertGlyph(slot: FT2Glyph, temp: var seq[uint32]): TEXGlyph =
  result.glyphIDX = slot.glyph_index
  # Save new dimensions
  result.w = slot.bitmap.width
  result.h = slot.bitmap.rows
  # Save position offsets
  result.x = slot.bitmap_left # xBearing
  result.y = slot.bitmap_top # yBearing
  result.advance = int32(slot.advance.x shr 6)
  # Render Glyph as RGBA8888
  var # Starting Positions
    i = temp.len # Starting Position
    j = 0'u32 # Bitmap Position
  temp.setLen(i + int result.w * result.h)
  while i < len(temp): # Only Modify Alpha Channel of a White Pixel
    temp[i] = 0x00FFFFFF'u32 or uint32(slot.bitmap.buffer[j]) shl 24
    inc(i); inc(j) # Next RGBA8888 Pixel

proc renderCharcode(atlas: var CTXAtlas, code: uint16, temp: var seq[uint32]) =
  # Extend Lookup if charcode is greater
  if int(code) > len(atlas.charset): 
    atlas.charset.setLen(int(code) + 1)
  # Render Glyph and Save Glpyh Index on charcode lookup
  if ft2_loadChar(atlas.face, culong(code), FT_LOAD_RENDER) == 0:
    atlas.glyphs.add convertGlyph(atlas.face.glyph, temp)
    atlas.charset[code] = uint16(high atlas.glyphs)
  else: atlas.charset[code] = NOT_FOUND # Use Fallback

# --------------------
# ATLAS CREATION PROCS
# --------------------

iterator charcodes(charset: LANGCharset): uint16 =
  yield 0xFFFD # Fallback Charcode
  var s, e: uint16 # Charcode Iter
  # Iterate Over Latin Charset
  s = csRanges[0].a
  e = csRanges[0].b
  while s <= e: 
    yield s; inc(s)
  # Render Other Charset
  if charset != csLatin:
    var a, b: uint8 # Iterate Ranges
    case charset # Select a Charset
    of csJapanese: a = 3; b = 5
    of csChinese: a = 3; b = 6
    of csCyrillic: a = 7; b = 9
    of csKorean: a = 1; b = 2
    else: discard # Latin was Loaded
    while a <= b:
      s = csRanges[a].a
      e = csRanges[a].b
      while s <= e:
        yield s; inc(s)
      inc(a) # Next Range

proc renderCharset(atlas: var CTXAtlas, charset: LANGCharset): seq[uint32] =
  var temp: seq[uint32] # Temporal Bitmap Buffer
  # Render Charset Glyphs
  for code in charcodes(charset):
    renderCharcode(atlas, code, temp)
  block: # Get power of two equivalent side*side
    var area: uint32 # Total used area
    # Calculate Total Area of Glyphs
    for glyph in mitems(atlas.glyphs):
      area += glyph.w * glyph.h
    # Calculate Power of Two Side
    area = uint32 nextPowerOfTwo(
      int ceil sqrt(float32 area))
    # Set new atlas dimensions
    atlas.w = int32 area; atlas.h = int32 area
    atlas.nodes.add(SKYNode(w:atlas.w))
    # Alloc Buffer with new dimensions
    result.setLen(area*area)
  # Arrange Glyphs Using Skyline
  var cursor: uint32 # Temp Cursor
  for glyph in mitems(atlas.glyphs):
    var x, y: int32 # New Position On Atlas
    discard pack(atlas, int32 glyph.w, int32 glyph.h, x, y)
    # Copy Buffer to new Position Indicated by Skyline
    var # Pixel Row Iterator
      pixel = y * atlas.w + x
      i = 0'u32 # Row Iterator
    while i < glyph.h: # Copy Pixel Rows
      copyMem(addr result[pixel], addr temp[cursor], 
        int(glyph.w) * sizeof(uint32))
      # Move to Next Pixel Row
      cursor += glyph.w
      pixel += atlas.w; inc(i)

proc newCTXAtlas*(ft2: FT2Library, charset: LANGCharset): CTXAtlas =
  # 1 -- Create New Face, TODO: Use FT_New_Memory_Face
  if ft2_newFace(ft2, "data/font.ttf", 0, addr result.face) != 0:
    echo "ERROR: failed loading ft2 font"
  #discard ft2_setPixelSizes(result.face, 0, 10)
  discard ft2_setCharSize(result.face, int32 0, int32 10 shl 6, uint32 96, uint32 96)
  echo result.face.family_name
  # 2 -- Render Charset
  result.test = renderCharset(result, charset)