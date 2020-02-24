from ../cmath import guiProjection
from ../shader import newProgram
# Texture Atlas
import atlas
# OpenGL 3.2+
import ../libs/gl

const 
  STRIDE_SIZE = # XYUVRGBA 16bytes
    sizeof(float32)*2 + sizeof(int16)*2 + sizeof(uint32)
type
  # GUI RECT AND COLOR
  GUIRect* = object
    x*, y*, w*, h*: int32
  GUIPoint* = object
    x*, y*: int32
  GUIColor* = uint32
  # Clip Levels
  CTXCommand = object
    offset, size, base: int32
    texID: GLuint
    clip: GUIRect
  # Vertex Format XYUVRGBA 16-byte
  CTXVertex {.packed.} = object
    x, y: float32 # Position
    u, v: int16 # Not Normalized UV
    color: uint32 # Color
  CTXVertexMap = # Vertexs
    ptr UncheckedArray[CTXVertex]
  CTXElementMap = # Elements
    ptr UncheckedArray[uint16]
  # Allocated Buffers
  CTXRender* = object
    # Shader Program
    program: GLuint
    uPro, uDim: GLint
    # Frame viewport cache
    vWidth, vHeight: int32
    vCache: array[16, float32]
    # Atlas & Buffer Objects
    atlas: CTXAtlas
    vao, ebo, vbo: GLuint
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

proc newCTXRender*(atlas: CTXAtlas): CTXRender =
  # -- Set Texture Atlas
  result.atlas = atlas
  # -- Create new Program
  result.program = newProgram("shaders/gui.vert", "shaders/gui.frag")
  # Use Program for Define Uniforms
  glUseProgram(result.program)
  # Define Projection and Texture Uniforms
  result.uPro = glGetUniformLocation(result.program, "uPro")
  result.uDim = glGetUniformLocation(result.program, "uDim")
  # Set Default Uniforms Values: Texture Slot, Atlas Dimension
  glUniform1i glGetUniformLocation(result.program, "uTex"), 0
  glUniform2f(result.uDim, result.atlas.nW, result.atlas.nH)
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
  glVertexAttribPointer(1, 2, cGL_SHORT, false, STRIDE_SIZE, 
    cast[pointer](sizeof(float32)*2)) # UV COORDS
  glVertexAttribPointer(2, 4, GL_UNSIGNED_BYTE, true, STRIDE_SIZE, 
    cast[pointer](sizeof(float32)*2 + sizeof(int16)*2)) # COLOR
  # Enable Vertex Attribs
  glEnableVertexAttribArray(0)
  glEnableVertexAttribArray(1)
  glEnableVertexAttribArray(2)
  # Unbind VAO and VBO
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  glBindVertexArray(0)

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
  glBindTexture(GL_TEXTURE_2D, ctx.atlas.texID)
  # Set Viewport to Window
  glViewport(0, 0, ctx.vWidth, ctx.vHeight)
  glUniformMatrix4fv(ctx.uPro, 1, false,
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
    if cmd.texID == 0: # Use Atlas Texture
      glDrawElementsBaseVertex( # Draw Command
        GL_TRIANGLES, cmd.size, GL_UNSIGNED_SHORT,
        cast[pointer](cmd.offset * sizeof(uint16)),
        cmd.base) # Base Vertex Index
    else: # Use CMD Texture This Time
      # Change Texture and Use Normalized UV
      glBindTexture(GL_TEXTURE_2D, cmd.texID)
      glUniform2f(ctx.uDim, 1, 1) # UV * 1
      # Draw Texture Quad using Triangle Strip
      glDrawArrays(GL_TRIANGLE_STRIP, cmd.base, 4)
      # Back to Atlas Texture with Unnormalized UV
      glBindTexture(GL_TEXTURE_2D, ctx.atlas.texID)
      glUniform2f(ctx.uDim, ctx.atlas.nW, ctx.atlas.nH)

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
  ctx.verts.setLen(ctx.verts.len + vSize)
  ctx.elements.setLen(ctx.elements.len + eSize)
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

## X,Y,WHITEU,WHITEV,COLOR
template vertex(i: int32, a,b: float32) =
  ctx.pVert[i].x = a # Position X
  ctx.pVert[i].y = b # Position Y
  ctx.pVert[i].u = ctx.atlas.whiteU # White U
  ctx.pVert[i].v = ctx.atlas.whiteV # White V
  ctx.pVert[i].color = ctx.color # Color RGBA

# X,Y,U,V,COLOR
template vertexUV(i: int32, a,b: float32, c,d: int16) =
  ctx.pVert[i].x = a # Position X
  ctx.pVert[i].y = b # Position Y
  ctx.pVert[i].u = c # Tex U
  ctx.pVert[i].v = d # Tex V
  ctx.pVert[i].color = ctx.color # Color RGBA

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
  ctx.levels.setLen(max(ctx.levels.len - 1, 0))

# ---------------------------
# GUI BASIC SHAPES DRAW PROCS
# ---------------------------

proc fill*(ctx: ptr CTXRender, rect: var GUIRect) =
  ctx.addVerts(4, 6)
  block: # Rect Triangles
    let
      x = float32 rect.x
      y = float32 rect.y
      xw = x + float32 rect.w
      yh = y + float32 rect.h
    vertex(0, x, y)
    vertex(1, xw, y)
    vertex(2, x, yh)
    vertex(3, xw, yh)
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
    vertex(0, x, y+s)
    vertex(1, x, y)
    vertex(2, x+s, y)
    # Top Right Corner
    vertex(3, xw-s, y)
    vertex(4, xw, y)
    vertex(5, xw, y+s)
    # Bottom Right Corner
    vertex(6, xw, yh-s)
    vertex(7, xw, yh)
    vertex(8, xw-s, yh)
    # Bottom Left Corner
    vertex(9, x+s, yh)
    vertex(10, x, yh)
    vertex(11, x, yh-s)
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

proc triangle*(ctx: ptr CTXRender, x1,y1, x2,y2, x3,y3: int32) =
  ctx.addVerts(3, 3)
  # Triangle Description
  vertex(0, float32 x1, float32 y1)
  vertex(1, float32 x2, float32 y2)
  vertex(2, float32 x3, float32 y3)
  # Elements Description
  triangle(0, 0,1,2)

proc texture*(ctx: ptr CTXRender, rect: var GUIRect, texID: GLuint) =
  ctx.addCommand() # Create New Command
  ctx.pCMD.texID = ctx.atlas.texID # Set Texture
  # Add 4 Vertexes for a Quad
  ctx.verts.setLen(ctx.verts.len + 4)
  ctx.pVert = cast[CTXVertexMap](addr ctx.verts[^4])
  let # Define The Quad
    x = float32 rect.x
    y = float32 rect.y
    xw = x + float32 rect.w
    yh = y + float32 rect.h
  vertexUV(0, x, y, 0, 0)
  vertexUV(1, xw, y, 1, 0)
  vertexUV(2, x, yh, 0, 1)
  vertexUV(3, xw, yh, 1, 1)
  # Invalidate CMD
  ctx.pCMD = nil

proc text*(ctx: ptr CTXRender, x,y: int32, str: string) =
  block: # Find Max Bearing
    var yo: int16 # Max Bearing
    for rune in runes16(str):
      yo = # Check if this charcode is max
        max(yo, ctx.atlas.lookup(rune).yo)
    # Offset Y to MaxBearing
    (unsafeAddr y)[] += yo
  # Render Text Top to Bottom
  for rune in runes16(str):
    let glyph = # Load Glyph
      ctx.atlas.lookup(rune)
    # Reserve Quad Vertex and Elements
    ctx.addVerts(4, 6); block:
      let # Quad Coordinates
        x = float32 x + glyph.xo
        xw = x + float32 glyph.w
        y = float32 y - glyph.yo
        yh = y + float32 glyph.h
      # Quad Vertex
      vertexUV(0, x, y, glyph.x1, glyph.y1)
      vertexUV(1, xw, y, glyph.x2, glyph.y1)
      vertexUV(2, x, yh, glyph.x1, glyph.y2)
      vertexUV(3, xw, yh, glyph.x2, glyph.y2)
    # Quad Elements
    triangle(0, 0,1,2)
    triangle(3, 1,2,3)
    # To Next Glyph X Position
    (unsafeAddr x)[] += glyph.advance
