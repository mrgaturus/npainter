type
  SKYNode = object
    x, y, w: int32
  TEXGlyph = object
    glyphIDX: uint32 # FT2
    x1, x2, y1, y2: float32
  CTXAtlas* = object
    w, h: int32
    texID: uint32
    # GLYPHS INFORMATION
    charset: seq[uint16]
    glyphs: seq[TEXGlyph]
    # SKYLINE BIN PACKING
    nodes: seq[SKYNode]
  
# -------------------
# ATLAS CREATION PROC
# -------------------

proc newCTXAtlas*(w, h: int32): CTXAtlas =
  # Set Atlas Dimensions
  result.w = w; result.h = h
  # Add Initial Node
  result.nodes.add(SKYNode(w:w))

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
        let node = atlas.nodes[i]
        if y + h < bestH or (y + h == bestH and node.w < bestW):
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