from ../math import guiProjection
from ../shader import newProgram
# OpenGL 3.2+
import ../libs/gl

const # XYUVRGBA 20bytes
  STRIDE_SIZE = sizeof(float32)*4 + sizeof(uint32)
type
  # GUI RECT AND COLOR
  GUIRect* = object
    x*, y*, w*, h*: int32
  GUIColor* = uint32
  # Orientation
  CTXOrientation* = enum
    toUP, toLEFT,
    toDOWN, toRIGHT
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
  CTXRender* = object
    # Shader Program
    program: GLuint
    projection: GLint
    # Frame viewport cache
    vWidth, vHeight: int32
    vCache: array[16, float32]
    # Buffer Objects
    vao, ebo, vbo: GLuint
    white: GLuint
    # Color and Clips
    color*: uint32
    levels: seq[GUIRect]
    # Vertex index
    size, cursor: uint16
    # Write Pointers
    pCMD: ptr CTXCommand
    pVert: CTXVertexMap
    pElem: CTXElementMap
    # Allocated Buffer Data
    cmds: seq[CTXCommand]
    elements: seq[uint16]
    verts: seq[CTXVertex]

# -------------------------
# GUI CANVAS CREATION PROCS
# -------------------------

proc newCTXRender*(): CTXRender =
  # -- Create new Program
  result.program = newProgram("shaders/gui.vert", "shaders/gui.frag")
  # Use Program for Define Uniforms
  glUseProgram(result.program)
  # Define Projection and Texture Uniforms
  result.projection = glGetUniformLocation(result.program, "uPro")
  glUniform1i(glGetUniformLocation(result.program, "uTex"), 0)
  # Unuse Program
  glUseProgram(0)
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

proc begin*(ctx: var CTXRender) =
  # Use GUI program
  glUseProgram(ctx.program)
  # Disable 3D OpenGL Flags
  glDisable(GL_CULL_FACE)
  glDisable(GL_DEPTH_TEST)
  glDisable(GL_STENCIL_TEST)
  # Enable Scissor Test
  glEnable(GL_SCISSOR_TEST)
  # Enable Alpha Blending
  glEnable(GL_BLEND)
  glBlendEquation(GL_FUNC_ADD)
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  # Bind VAO and VBO
  glBindVertexArray(ctx.vao)
  glBindBuffer(GL_ARRAY_BUFFER, ctx.vbo)
  # Modify Only Texture 0
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, ctx.white)
  # Set Viewport to Window
  glViewport(0, 0, ctx.vWidth, ctx.vHeight)
  glUniformMatrix4fv(ctx.projection, 1, false,
    cast[ptr float32](addr ctx.vCache))

proc viewport*(ctx: var CTXRender, w, h: int32) =
  guiProjection(addr ctx.vCache, float32 w, float32 h)
  ctx.vWidth = w; ctx.vHeight = h

proc clear*(ctx: var CTXRender) =
  # Reset Current CMD
  ctx.pCMD = nil
  # Clear Buffers
  setLen(ctx.cmds, 0)
  setLen(ctx.elements, 0)
  setLen(ctx.verts, 0)
  # Clear Clipping Levels
  setLen(ctx.levels, 0)
  ctx.color = 0 # Nothing Color

proc render*(ctx: var CTXRender) =
  # Upload Elements
  glBufferData(GL_ELEMENT_ARRAY_BUFFER, 
    len(ctx.elements)*sizeof(uint16),
    addr ctx.elements[0], GL_STREAM_DRAW)
  # Upload Verts
  glBufferData(GL_ARRAY_BUFFER,
    len(ctx.verts)*sizeof(CTXVertex),
    addr ctx.verts[0], GL_STREAM_DRAW)
  # Draw Clipping Commands
  for cmd in mitems(ctx.cmds):
    glScissor( # Clip Region
      cmd.clip.x, ctx.vHeight - cmd.clip.y - cmd.clip.h, 
      cmd.clip.w, cmd.clip.h) # Clip With Correct Y
    glDrawElementsBaseVertex( # Draw Command
      GL_TRIANGLES, cmd.size, GL_UNSIGNED_SHORT,
      cast[pointer](cmd.offset * sizeof(uint16)),
      cmd.base) # Base Vertex Index

proc finish*() =
  # Unbind Texture and VAO
  glBindTexture(GL_TEXTURE_2D, 0)
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  glBindVertexArray(0)
  # Disable Scissor and Blend
  glDisable(GL_SCISSOR_TEST)
  glDisable(GL_BLEND)
  # Unbind Program
  glUseProgram(0)

# ------------------------
# GUI PAINTER HELPER PROCS
# ------------------------

proc addCommand(ctx: ptr CTXRender) =
  # Reset Cursor
  ctx.size = 0
  # Add New Command
  ctx.cmds.add(
    CTXCommand(
      offset: int32(
        len(ctx.elements)
      ), base: int32(
        len(ctx.verts)
      ), clip: if len(ctx.levels) > 0: ctx.levels[^1]
      else: GUIRect(w: ctx.vWidth, h: ctx.vHeight)
    ) # End New CTX Command
  ) # End Add Command
  ctx.pCMD = addr ctx.cmds[^1]

proc addVerts(ctx: ptr CTXRender, vSize, eSize: int32) =
  # Create new Command if is reseted
  if isNil(ctx.pCMD): addCommand(ctx)
  # Set New Vertex and Elements Lenght
  ctx.verts.setLen(len(ctx.verts) + vSize)
  ctx.elements.setLen(len(ctx.elements) + eSize)
  # Add Elements Count to CMD
  ctx.pCMD.size += eSize
  # Set Write Pointers
  ctx.pVert = cast[CTXVertexMap](addr ctx.verts[^vSize])
  ctx.pElem = cast[CTXElementMap](addr ctx.elements[^eSize])
  # Set Current Vertex Index
  ctx.cursor = ctx.size
  ctx.size += uint16(vSize)

# ----------------------
# GUI DRAWING TEMPLATES
# ----------------------

## X,Y,0,0,COLOR
template vertex(i: int32, a,b: float32, col: uint32) =
  ctx.pVert[i].x = a # Position X
  ctx.pVert[i].y = b # Position Y
  ctx.pVert[i].color = col # Color RGBA

# Last Vert Index + Offset
template triangle(o: int32, a,b,c: int32) =
  ctx.pElem[o] = ctx.cursor + a
  ctx.pElem[o+1] = ctx.cursor + b
  ctx.pElem[o+2] = ctx.cursor + c

# -----------------------
# GUI CLIP/COLOR LEVELS PROCS
# -----------------------

proc intersect(ctx: ptr CTXRender, rect: var GUIRect): GUIRect =
  let prev = addr ctx.levels[^1]
  result.x = max(prev.x, rect.x)
  result.y = max(prev.y, rect.y)
  result.w = min(prev.x + prev.w, rect.x + rect.w) - result.x
  result.h = min(prev.y + prev.h, rect.y + rect.h) - result.y

proc push*(ctx: ptr CTXRender, rect: var GUIRect) =
  # Reset Current CMD
  ctx.pCMD = nil
  # Calcule Intersect Clip
  var clip = if len(ctx.levels) > 0:
    ctx.intersect(rect) # Intersect Level
  else: rect # First Level
  # Add new Level to Stack
  ctx.levels.add(clip)

proc pop*(ctx: ptr CTXRender) {.inline.} =
  # Reset Current CMD
  ctx.pCMD = nil
  # Remove Last CMD from Stack
  ctx.levels.setLen(max(len(ctx.levels) - 1, 0))

# --------------
# GUI BASIC DRAW
# --------------

proc fill*(ctx: ptr CTXRender, rect: var GUIRect) =
  ctx.addVerts(4, 6)
  block: # Rect Triangles
    let
      x = float32 rect.x
      y = float32 rect.y
      xw = x + float32 rect.w
      yh = y + float32 rect.h
    vertex(0, x, y, ctx.color)
    vertex(1, xw, y, ctx.color)
    vertex(2, x, yh, ctx.color)
    vertex(3, xw, yh, ctx.color)
  # Elements Definition
  triangle(0, 0,1,2)
  triangle(3, 1,2,3)

proc rectangle*(ctx: ptr CTXRender, rect: var GUIRect, s: float32) =
  ctx.addVerts(12, 24)
  block: # Box Vertex
    let
      x = float32 rect.x
      y = float32 rect.y
      xw = x + float32 rect.w
      yh = y + float32 rect.h
    # Top Left Corner
    vertex(0, x, y+s, ctx.color)
    vertex(1, x, y, ctx.color)
    vertex(2, x+s, y, ctx.color)
    # Top Right Corner
    vertex(3, xw-s, y, ctx.color)
    vertex(4, xw, y, ctx.color)
    vertex(5, xw, y+s, ctx.color)
    # Bottom Right Corner
    vertex(6, xw, yh-s, ctx.color)
    vertex(7, xw, yh, ctx.color)
    vertex(8, xw-s, yh, ctx.color)
    # Bottom Left Corner
    vertex(9, x+s, yh, ctx.color)
    vertex(10, x, yh, ctx.color)
    vertex(11, x, yh-s, ctx.color)
  # Top Rect
  triangle(0, 0,1,5)
  triangle(3, 5,4,1)
  # Right Rect
  triangle(6, 3,4,7)
  triangle(9, 7,8,3)
  # Bottom Rect
  triangle(12, 7,6,11)
  triangle(15, 11,10,7)
  # Left Rect
  triangle(18, 10,9,1)
  triangle(21, 1,2,9)

proc triangle*(ctx: ptr CTXRender, rect: var GUIRect, o: CTXOrientation) =
  ctx.addVerts(3, 3)
  block:
    let
      x = float32 rect.x
      y = float32 rect.y
      xw = x + float32 rect.w
      yh = y + float32 rect.h
    case o: # Orientation of Triangle
    of toUp: # to Up
      vertex(0, x+rect.w/2, y, ctx.color)
      vertex(1, xw, yh, ctx.color)
      vertex(2, x, yh, ctx.color)
    of toRight: # to Right
      vertex(0, xw, y+rect.h/2, ctx.color)
      vertex(1, x, yh, ctx.color)
      vertex(2, x, y, ctx.color)
    of toDown: # to Down
      vertex(0, x+rect.w/2, yh, ctx.color)
      vertex(1, x, y, ctx.color)
      vertex(2, xw, y, ctx.color)
    of toLeft: # to Left
      vertex(0, x, y+rect.h/2, ctx.color)
      vertex(1, xw, y, ctx.color)
      vertex(2, xw, yh, ctx.color)
  # Elements Description
  triangle(0, 0,1,2)