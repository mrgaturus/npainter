import ../libs/gl

const # XYUVRGBA 20bytes
  STRIDE_SIZE = sizeof(float32)*4 + sizeof(uint32)
type
  # GUI RECT AND COLOR
  GUIRect* = object
    x*, y*, w*, h*: int32
  GUIColor* = uint32
  # Clip Levels
  CTXCommand = object
    offset, size, base: int32
    clip: GUIRect
  # Vertex Format XYUVRGBA
  CTXVertex = object
    x, y, u, v: float32
    color: uint32
  CTXVertexMap = # Fast Modify Pointer
    ptr UncheckedArray[CTXVertex]
  CTXElementMap = # Elements
    ptr UncheckedArray[uint16]
  # Allocated Buffers
  CTXCanvas* = object
    # Buffer Objects
    vao, ebo, vbo: GLuint
    white: GLuint
    # Viewport
    w, h: int32
    # Color and Clips
    color*: uint32
    levels: seq[GUIRect]
    # Vertex index
    pivot: int32
    cursor: uint16
    # Write Pointers
    pVert: CTXVertexMap
    pElement: CTXElementMap
    # Allocated Buffer Data
    cmds: seq[CTXCommand]
    elements: seq[uint16]
    verts: seq[CTXVertex]

# -------------------------
# GUI CANVAS CREATION PROCS
# -------------------------

proc newCTXCanvas*(): CTXCanvas =
  # -- Gen VAOs and Batch VBO
  glGenVertexArrays(1, addr result.vao)
  glGenBuffers(2, addr result.ebo)
  # Bind Batch VAO and VBO
  glBindVertexArray(result.vao)
  glBindBuffer(GL_ARRAY_BUFFER, result.vbo)
  # Bind Elements Buffer to current VAO
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, result.ebo)
  # Vertex Attribs XYVUVRGBA 20bytes
  glVertexAttribPointer(0, 2, cGL_FLOAT, false, STRIDE_SIZE, 
    cast[pointer](0)) # VERTEX
  glVertexAttribPointer(1, 2, cGL_FLOAT, false, STRIDE_SIZE, 
    cast[pointer](sizeof(float32)*2)) # UV COORDS
  glVertexAttribPointer(2, 4, GL_UNSIGNED_BYTE, true, STRIDE_SIZE, 
    cast[pointer](sizeof(float32)*4)) # COLOR
  # Enable Vertex Attribs
  glEnableVertexAttribArray(0)
  glEnableVertexAttribArray(1)
  glEnableVertexAttribArray(2)
  # Unbind VAO and VBO
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  glBindVertexArray(0)
  # -- Gen White Pixel Texture
  glGenTextures(1, addr result.white)
  glBindTexture(GL_TEXTURE_2D, result.white)
  # Clamp white pixel to edge
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, cast[GLint](GL_CLAMP_TO_EDGE))
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, cast[GLint](GL_CLAMP_TO_EDGE))
  # Use Nearest Pixel
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, cast[GLint](GL_NEAREST))
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, cast[GLint](GL_NEAREST))
  # Alloc White Pixel
  block:
    var white = 0xFFFFFFFF'u32
    glTexImage2D(GL_TEXTURE_2D, 0, cast[int32](GL_RGBA8), 1, 1, 0, GL_RGBA,
        GL_UNSIGNED_BYTE, addr white)
  # Unbind White Pixel Texture
  glBindTexture(GL_TEXTURE_2D, 0)

# --------------------------
# GUI RENDER PREPARING PROCS
# --------------------------

proc viewport*(ctx: var CTXCanvas, w, h: int32) =
  ctx.w = w; ctx.h = h

proc makeCurrent*(ctx: var CTXCanvas) =
  # Clear Buffers
  setLen(ctx.cmds, 0)
  setLen(ctx.elements, 0)
  setLen(ctx.verts, 0)
  # Reset Pivot
  ctx.pivot = 0
  # Clear Clipping Levels
  setLen(ctx.levels, 0)
  ctx.color = 0 # Nothing Color
  # Bind Batch VAO and Atlas
  glBindVertexArray(ctx.vao)
  glBindBuffer(GL_ARRAY_BUFFER, ctx.vbo)
  glBindTexture(GL_TEXTURE_2D, ctx.white)

proc clearCurrent*(ctx: var CTXCanvas) =
  # Upload Elements
  glBufferData(GL_ELEMENT_ARRAY_BUFFER, 
    len(ctx.elements)*sizeof(uint16),
    addr ctx.elements[0], GL_STREAM_DRAW)
  # Upload Verts
  glBufferData(GL_ARRAY_BUFFER,
    len(ctx.verts)*sizeof(CTXVertex),
    addr ctx.verts[0], GL_STREAM_DRAW)
  # Draw Clipping Commands
  if len(ctx.cmds) > 0:
    glEnable(GL_SCISSOR_TEST)
    for cmd in mitems(ctx.cmds):
      glScissor( # Clip Region
        cmd.clip.x, ctx.h - cmd.clip.y - cmd.clip.h, 
        cmd.clip.w, cmd.clip.h) # Clip With Correct Y
      glDrawElementsBaseVertex( # Draw Command
        GL_TRIANGLES, cmd.size, GL_UNSIGNED_SHORT,
        cast[pointer](cmd.offset * sizeof(uint16)),
        cmd.base) # Base Vertex Index
    glDisable(GL_SCISSOR_TEST)
  # Unbind Texture, VBO and VAO
  glBindTexture(GL_TEXTURE_2D, 0)
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  glBindVertexArray(0)

# ------------------------
# GUI PAINTER HELPER PROCS
# ------------------------

proc defaultCMD(ctx: ptr CTXCanvas, eSize: int32) =
  ctx.cmds.add( # Default CMD if is not Defined
    CTXCommand( # Viewport Same Clip
      size: eSize, # Initial Size
      clip: GUIRect(w: ctx.w, h: ctx.h)))

proc addCMD(ctx: ptr CTXCanvas, clip: var GUIRect) =
  let size = # Check if last CMD has size
    if len(ctx.cmds) > 0: 
      ctx.cmds[^1].size
    else: 0
  if size == 0:
    ctx.pivot = 
      int32(ctx.verts.len)
    ctx.cmds.add(
      CTXCommand(
        offset: int32(
          len(ctx.elements)
        ), base: ctx.pivot, 
        clip: clip))
  else: # Change Clip of last
    ctx.cmds[^1].clip = clip

proc addVerts(ctx: ptr CTXCanvas, vSize, eSize: int32) =
  # Set Current Vertex Index
  ctx.cursor = uint16(len(ctx.verts) - ctx.pivot)
  # Set New Vertex and Elements Lenght
  ctx.verts.setLen(len(ctx.verts) + vSize)
  ctx.elements.setLen(len(ctx.elements) + eSize)
  # Add Elements Count to CMD
  if len(ctx.cmds) > 0: ctx.cmds[^1].size += eSize
  else: defaultCMD(ctx, eSize) # Aux CMD
  # Set Write Pointers
  ctx.pVert = cast[CTXVertexMap](addr ctx.verts[^vSize])
  ctx.pElement = cast[CTXElementMap](addr ctx.elements[^eSize])

# ----------------------
# GUI DRAWING TEMPLATES
# ----------------------

# Last Vert Index + Offset
template triangle(emap: CTXElementMap, o,a,b,c: int32) =
  emap[o] = ctx.cursor + a
  emap[o+1] = ctx.cursor + b
  emap[o+2] = ctx.cursor + c

## X,Y,U,V,COLOR
template vertex(a,b,c,d: float32, col: uint32): CTXVertex =
  CTXVertex(x:a,y:b,u:c,v:d,color:col)

# -----------------------
# GUI CLIP/COLOR LEVELS PROCS
# -----------------------

proc intersect(ctx: ptr CTXCanvas, rect: var GUIRect): GUIRect =
  let
    prev = addr ctx.levels[^1]
    x1 = clamp(rect.x, prev.x, prev.x + prev.w)
    y1 = clamp(rect.y, prev.y, prev.y + prev.h)
    x2 = clamp(prev.x + prev.w, rect.x, rect.x + rect.w)
    y2 = clamp(prev.y + prev.h, rect.y, rect.y + rect.h)
  result.x = x1
  result.y = y1
  result.w = abs(x2 - x1)
  result.h = abs(y2 - y1)

proc push*(ctx: ptr CTXCanvas, rect: var GUIRect) =
  var clip = if len(ctx.levels) > 0:
    ctx.intersect(rect)
  else: rect # First Level
  ctx.addCMD(clip) # New Command
  ctx.levels.add(clip) # New level

proc pop*(ctx: ptr CTXCanvas) =
  ctx.levels.setLen(
    max(len(ctx.levels) - 1, 0))
  if len(ctx.levels) > 0: # Pop Level
    ctx.addCMD(ctx.levels[^1]) # New Command

# --------------
# GUI BASIC DRAW
# --------------

proc fill*(ctx: ptr CTXCanvas, rect: var GUIRect) =
  ctx.addVerts(4, 6)
  block: # Rect Triangles
    let
      x = float32 rect.x
      y = float32 rect.y
      xw = x + float32 rect.w
      yh = y + float32 rect.h
    ctx.pVert[0] = vertex(x, y, 0, 0, ctx.color)
    ctx.pVert[1] = vertex(xw, y, 0, 0, ctx.color)
    ctx.pVert[2] = vertex(x, yh, 0, 0, ctx.color)
    ctx.pVert[3] = vertex(xw, yh, 0, 0, ctx.color)
  # Elements Definition
  triangle(ctx.pElement, 0, 0,1,2)
  triangle(ctx.pElement, 3, 1,2,3)