# Math and Fast Math Modules
from math import sin, cos, PI
from ../c_math import
  fastSqrt,
  invertedSqrt,
  guiProjection
# Assets and Metrics
from config import metrics
from ../assets import newShader
from ../utf8 import runes16
# Texture Atlas
import atlas
# OpenGL 3.2+
import ../libs/gl

const 
  STRIDE_SIZE = # 16bytes
    sizeof(float32)*2 + # XY
    sizeof(int16)*2 + # UV
    sizeof(uint32) # RGBA
type
  # RENDER PRIMITIVES
  GUIColor* = uint32
  GUIRect* = object
    x*, y*, w*, h*: int32
  CTXPoint* = object
    x*, y*: float32
  CTXRect* = object
    x*, y*, xw*, yh*: float32
  # Clip Levels
  CTXCommand = object
    offset, base, size: int32
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
    color, colorAA: uint32
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

# ----------------------------
# GUI PRIMITIVE CREATION PROCS
# ----------------------------

proc rgba*(r, g, b, a: uint8): GUIColor {.inline.} =
  result = r or (g shl 8) or (b shl 16) or (a shl 24)

proc rect*(x, y, w, h: int32): CTXRect {.inline.} =
  result.x = float32(x) 
  result.y = float32(y)
  result.xw = float32(x + w) 
  result.yh = float32(y + h)

proc rect*(r: GUIRect): CTXRect =
  result.x = float32(r.x)
  result.y = float32(r.y)
  result.xw = float32(r.x + r.w)
  result.yh = float32(r.y + r.h)

proc point*(x, y: float32): CTXPoint {.inline.} =
  result.x = x; result.y = y

proc point*(x, y: int32): CTXPoint {.inline.} =
  result.x = float32(x)
  result.y = float32(y)

proc normal*(a, b: CTXPoint): CTXPoint =
  result.x = a.y - b.y
  result.y = b.x - a.x
  let norm = invertedSqrt(
    result.x*result.x + 
    result.y*result.y)
  # Normalize Point
  result.x *= norm
  result.y *= norm

# -------------------------
# GUI CANVAS CREATION PROCS
# -------------------------

proc newCTXRender*(): CTXRender =
  # -- Set Texture Atlas
  result.atlas = newCTXAtlas()
  # -- Create new Program
  result.program = newShader("gui.vert", "gui.frag")
  # Use Program for Define Uniforms
  glUseProgram(result.program)
  # Define Projection and Texture Uniforms
  result.uPro = glGetUniformLocation(result.program, "uPro")
  result.uDim = glGetUniformLocation(result.program, "uDim")
  # Set Default Uniforms Values: Texture Slot, Atlas Dimension
  glUniform1i glGetUniformLocation(result.program, "uTex"), 0
  glUniform2f(result.uDim, result.atlas.rw, result.atlas.rh)
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

proc clear(ctx: var CTXRender) =
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
  if checkTexture(ctx.atlas): # Check if was Resized
    glUniform2f(ctx.uDim, ctx.atlas.rw, ctx.atlas.rh)
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
      glUniform2f(ctx.uDim, 1.0'f32, 1.0'f32)
      # Draw Texture Quad using Triangle Strip
      glDrawArrays(GL_TRIANGLE_STRIP, cmd.base, 4)
      # Back to Atlas Texture with Unnormalized UV
      glBindTexture(GL_TEXTURE_2D, ctx.atlas.texID)
      glUniform2f(ctx.uDim, ctx.atlas.rw, ctx.atlas.rh)
  ctx.clear() # Clear Render State

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

proc addVerts*(ctx: ptr CTXRender, vSize, eSize: int32) =
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

## X,Y,WHITEU,WHITEV,COLORAA
template vertexAA(i: int32, a,b: float32) =
  ctx.pVert[i].x = a # Position X
  ctx.pVert[i].y = b # Position Y
  ctx.pVert[i].u = ctx.atlas.whiteU # White U
  ctx.pVert[i].v = ctx.atlas.whiteV # White V
  ctx.pVert[i].color = ctx.colorAA # Color Antialias

# X,Y,U,V,COLOR
template vertexUV(i: int32, a,b: float32, c,d: int16) =
  ctx.pVert[i].x = a # Position X
  ctx.pVert[i].y = b # Position Y
  ctx.pVert[i].u = c # Tex U
  ctx.pVert[i].v = d # Tex V
  ctx.pVert[i].color = ctx.color # Color RGBA

# X,Y,COLOR | PUBLIC
template vertexCOL*(i: int32, a,b: float32, c: GUIColor) =
  ctx.pVert[i].x = a # Position X
  ctx.pVert[i].y = b # Position Y
  ctx.pVert[i].u = ctx.atlas.whiteU # White U
  ctx.pVert[i].v = ctx.atlas.whiteV # White V
  ctx.pVert[i].color = c # Color RGBA

# Last Vert Index + Offset | PUBLIC
template triangle*(o: int32, a,b,c: int32) =
  ctx.pElem[o] = ctx.cursor + cast[uint16](a)
  ctx.pElem[o+1] = ctx.cursor + cast[uint16](b)
  ctx.pElem[o+2] = ctx.cursor + cast[uint16](c)

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

proc color*(ctx: ptr CTXRender, color: uint32) {.inline.} =
  ctx.color = color # Normal Solid Color
  ctx.colorAA = color and 0xFFFFFF # Antialiased

# ---------------------------
# GUI BASIC SHAPES DRAW PROCS
# ---------------------------

proc fill*(ctx: ptr CTXRender, r: CTXRect) =
  ctx.addVerts(4, 6)
  vertex(0, r.x, r.y)
  vertex(1, r.xw, r.y)
  vertex(2, r.x, r.yh)
  vertex(3, r.xw, r.yh)
  # Elements Definition
  triangle(0, 0,1,2)
  triangle(3, 1,2,3)

proc line*(ctx: ptr CTXRender, r: CTXRect, s: float32) =
  ctx.addVerts(12, 24)
  # Top Rectangle Vertexs
  vertex(0, r.x,  r.y)
  vertex(1, r.xw, r.y)
  vertex(2, r.x,  r.y + s)
  vertex(3, r.xw, r.y + s)
  # Bottom Rectangle Vertexs
  vertex(4, r.x, r.yh)
  vertex(5, r.xw, r.yh)
  vertex(6, r.x,  r.yh - s)
  vertex(7, r.xw, r.yh - s)
  # Left Side Rectangle Vertexs
  vertex(8, r.x + s,  r.y + s)
  vertex(9, r.xw - s, r.y + s)
  # Right Side Rectangle Vertexs
  vertex(10, r.x + s,  r.yh - s)
  vertex(11, r.xw - s, r.yh - s)
  # Top Rectangle
  triangle(0, 0,1,2)
  triangle(3, 1,2,3)
  # Bottom Rectangle
  triangle(6, 4,5,6)
  triangle(9, 5,6,7)
  # Left Side Rectangle
  triangle(12, 2,8,10)
  triangle(15, 2,6,10)
  # Right Side Rectangle
  triangle(18, 3, 7,9)
  triangle(21, 11,7,9)

proc texture*(ctx: ptr CTXRender, rect: var GUIRect, texID: GLuint) =
  ctx.addCommand() # Create New Command
  ctx.pCMD.texID = texID # Set Texture
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

# ------------------------
# ANTIALIASED SHAPES PROCS
# ------------------------

proc triangle*(ctx: ptr CTXRender, a,b,c: CTXPoint) =
  ctx.addVerts(9, 21)
  # Triangle Description
  vertex(0, a.x, a.y)
  vertex(1, b.x, b.y)
  vertex(2, c.x, c.y)
  # Elements Description
  triangle(0, 0,1,2)
  var # Antialiased
    i, j: int32 # Sides
    k, l: int32 = 3 # AA
    x, y, norm: float32
  while i < 3:
    j = (i + 1) mod 3 # Truncate Side
    x = ctx.pVert[i].y - ctx.pVert[j].y
    y = ctx.pVert[j].x - ctx.pVert[i].x
    # Normalize Position Vector
    norm = invertedSqrt(x*x + y*y)
    x *= norm; y *= norm
    # Add Antialiased Vertexs to Triangle Sides
    vertexAA(k, ctx.pVert[i].x + x, ctx.pVert[i].y + y)
    vertexAA(k+1, ctx.pVert[j].x + x, ctx.pVert[j].y + y)
    # Add Antialiased Elements
    triangle(l, i, j, k)
    triangle(l+3, j, k, k+1)
    # Next Triangle Size
    i += 1; k += 2; l += 6

proc circle*(ctx: ptr CTXRender, p: CTXPoint, r: float32) =
  # Move X & Y to Center
  unsafeAddr(p.x)[] += r
  unsafeAddr(p.y)[] += r
  let # Angle Constants
    n = int32 5 * fastSqrt(r)
    theta = 2 * PI / float32(n)
  # Circle Triangles and Elements
  ctx.addVerts(n shl 1, n * 9)
  var # Iterator
    o, ox, oy: float32
    i, j, k: int32
  while i < n:
    # Direction Normals
    ox = cos(o); oy = sin(o)
    # Vertex Information
    vertex(j, # Solid
      p.x + ox * r, 
      p.y + oy * r)
    vertexAA(j + 1, # AA
      ctx.pVert[j].x + ox,
      ctx.pVert[j].y + oy)
    if i + 1 < n:
      triangle(k, 0, j, j + 2)
      triangle(k + 3, j, j + 1, j + 2)
      triangle(k + 6, j + 1, j + 2, j + 3)
    else: # Connect Last With First
      triangle(k, 0, j, 0)
      triangle(k + 3, j, 1, 0)
      triangle(k + 6, j, j + 1, 1)
    # Next Circle Triangle
    i += 1; j += 2; k += 9
    o += theta; # Next Angle

# ----------------------------
# TEXT & ICONS RENDERING PROCS
# ----------------------------

proc text*(ctx: ptr CTXRender, x,y: int32, str: string) =
  # Offset Y to Atlas Font Y Offset Metric
  unsafeAddr(y)[] += metrics.baseline
  # Render Text Top to Bottom
  for rune in runes16(str):
    let glyph = # Load Glyph
      ctx.atlas.getGlyph(rune)
    # Reserve Vertex and Elements
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
    unsafeAddr(x)[] += glyph.advance

proc text*(ctx: ptr CTXRender, x,y: int32, clip: CTXRect, str: string) =
  # Offset Y to Atlas Font Y Offset Metric
  unsafeAddr(y)[] += metrics.baseline
  # Render Text Top to Bottom
  for rune in runes16(str):
    let glyph = # Load Glyph
      ctx.atlas.getGlyph(rune)
    var # Vertex Information
      xo = float32 x + glyph.xo
      xw = xo + float32 glyph.w
      yo = float32 y - glyph.yo
      yh = yo + float32 glyph.h
      # UV Coordinates
      uo = glyph.x1 # U Coord
      uw = glyph.x2 # U + W
      vo = glyph.y1 # V Coord
      vh = glyph.y2 # V + H
    # Is Visible on X?
    if xo > clip.xw: break
    elif xw > clip.x:
      # Clip Current Glyph
      if xo < clip.x:
        uo += int16(clip.x - xo)
        xo = clip.x # Left Point
      if xw > clip.xw:
        uw -= int16(xw - clip.xw)
        xw = clip.xw # Right Point
      # Is Clipped Vertically?
      if yo < clip.y:
        vo += int16(clip.y - yo)
        yo = clip.y # Upper Point
      if yh > clip.yh:
        vh -= int16(yh - clip.yh)
        yh = clip.yh # Botton Point
      # Reserve Vertex and Elements
      ctx.addVerts(4, 6)
      # Quad Vertex
      vertexUV(0, xo, yo, uo, vo)
      vertexUV(1, xw, yo, uw, vo)
      vertexUV(2, xo, yh, uo, vh)
      vertexUV(3, xw, yh, uw, vh)
      # Quad Elements
      triangle(0, 0,1,2)
      triangle(3, 1,2,3)
    # To Next Glyph X Position
    unsafeAddr(x)[] += glyph.advance

proc icon*(ctx: ptr CTXRender, x,y: int32, icon: uint16) =
  ctx.addVerts(4, 6)
  let icon = ctx.atlas.getIcon(icon)
  block: # Rect Triangles
    let
      x = float32 x
      y = float32 y
      xw = x + float32 metrics.iconSize
      yh = y + float32 metrics.iconSize
    vertexUV(0, x, y, icon.x1, icon.y1)
    vertexUV(1, xw, y, icon.x2, icon.y1)
    vertexUV(2, x, yh, icon.x1, icon.y2)
    vertexUV(3, xw, yh, icon.x2, icon.y2)
  # Elements Definition
  triangle(0, 0,1,2)
  triangle(3, 1,2,3)
