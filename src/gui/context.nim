from ../math import guiProjection
from ../shader import newProgram

import ../libs/gl
import render

type
  # Floating Frames
  CTXFrame* = ref object
    vao, vbo, tex, fbo: GLuint
    # Frame viewport cache
    vWidth, vHeight: int32
    vCache: array[16, float32]
    # Texture Dirty
    fixed, dirty: bool
  # Vertex Aux Object
  CTXVertex = object
    x, y, u, v: float32
  # CTX Root Regions Map
  CTXElementMap = ptr UncheckedArray[uint16]
  CTXVertexMap = ptr UncheckedArray[CTXVertex]
  CTXMap = object
    cursor: int32
    w, h: float32
    # Unchecked Pointers
    eMap: CTXElementMap
    vMap: CTXVertexMap
  GUIContext* = object
    # CTX GUI Renderer
    program: GLuint
    projection: GLint
    canvas: CTXCanvas
    # Root Regions
    elements: GLuint
    visible: int32
    # Frame Holding
    root: CTXFrame
    unused: seq[CTXFrame]
const # Stride Size XYUV
  STRIDE_SIZE = 4 * sizeof(float32)

# -------------------
# CONTEXT CREATION/DISPOSE PROCS
# -------------------

proc newGUIContext*(): GUIContext =
  # Create new Program
  result.program = newProgram("shaders/gui.vert", "shaders/gui.frag")
  # Define Program Uniforms
  glUseProgram(result.program)
  result.projection = glGetUniformLocation(result.program, "uPro")
  glUniform1i(glGetUniformLocation(result.program, "uTex"), 0)
  glUseProgram(0)
  # Create New Canvas
  result.canvas = newCTXCanvas()
  # Generate New Elements Buffer
  glGenBuffers(1, addr result.elements)

proc newCTXFrame(fixed: bool): CTXFrame =
  new result # Fixed VBO?
  result.fixed = fixed
  # -- Create VAO and VBO
  glGenVertexArrays(1, addr result.vao)
  glGenBuffers(1, addr result.vbo)
  # Bind VAO and VBO
  glBindVertexArray(result.vao)
  glBindBuffer(GL_ARRAY_BUFFER, result.vbo)
  # Alloc Four Vertex for a Floating Frame
  if fixed: glBufferData(GL_ARRAY_BUFFER, STRIDE_SIZE*4, nil, GL_DYNAMIC_DRAW)
  # Vertex Attribs XYVUV 16bytes
  glVertexAttribPointer(0, 2, cGL_FLOAT, false, STRIDE_SIZE, 
    cast[pointer](0)) # VERTEX
  glVertexAttribPointer(1, 2, cGL_FLOAT, false, STRIDE_SIZE, 
    cast[pointer](sizeof(float32)*2)) # UV COORDS
  # Enable Vertex Attribs
  glEnableVertexAttribArray(0)
  glEnableVertexAttribArray(1)
  # Unbind VBO and VAO
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  glBindVertexArray(0)
  # -- Create New Framebuffer
  glGenTextures(1, addr result.tex)
  glGenFramebuffers(1, addr result.fbo)
  # Bind Texture and Framebuffer
  glBindFramebuffer(GL_FRAMEBUFFER, result.fbo)
  glBindTexture(GL_TEXTURE_2D, result.tex)
  # Set Texture Parameters
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, cast[GLint](GL_LINEAR))
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, cast[GLint](GL_LINEAR))
  # Attach Texture
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
      result.tex, 0)
  # Unbind Texture and Framebuffer
  glBindTexture(GL_TEXTURE_2D, 0)
  glBindFramebuffer(GL_FRAMEBUFFER, 0)

proc newCTXRoot*(ctx: var GUIContext, max: int32): CTXFrame =
  result = newCTXFrame(false)
  # Bind VBO and EBO
  glBindVertexArray(result.vao)
  glBindBuffer(GL_ARRAY_BUFFER, result.vbo)
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ctx.elements)
  # Alloc VBO and EBO Max Size
  glBufferData(GL_ARRAY_BUFFER, sizeof(CTXVertex)*4*max, nil, GL_DYNAMIC_DRAW)
  glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(uint16)*6*max, nil, GL_DYNAMIC_DRAW)
  # Unbind VBO and EBO
  glBindVertexArray(0)
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0)
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  # Set Root Frame
  ctx.root = result

# -------------------------
# CONTEXT TEMPLATES HELPERS
# -------------------------

# Expose Canvas for Widgets
template canvas*(ctx: var GUIContext): ptr CTXCanvas =
  addr ctx.canvas

# LAYOUT: XYUV
template vertex(a,b,c,d: float32): CTXVertex =
  CTXVertex(x:a,y:b,u:c,v:d)

# LAYOUT: XYUV Normalized
template vertexUV(a,b: float32): CTXVertex =
  CTXVertex(x:a,y:b,u:a/map.w,v:(map.h-b)/map.h)

# ------------------
# CONTEXT ROOT PROCS
# ------------------

proc mapRegions*(ctx: var GUIContext): CTXMap =
  # Bind VBO and EBO
  glBindBuffer(GL_ARRAY_BUFFER, ctx.root.vbo)
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ctx.elements)
  ctx.visible = 0 # Reset Visible Regions Count
  # Map VBO and EBO
  result.vMap = cast[CTXVertexMap]( # Map Vertexs
    glMapBuffer(GL_ARRAY_BUFFER, GL_WRITE_ONLY)) 
  result.eMap = cast[CTXElementMap]( # Map Elements
    glMapBuffer(GL_ELEMENT_ARRAY_BUFFER, GL_WRITE_ONLY))
  # Viewport Size for UV
  result.w = float32 ctx.root.vWidth
  result.h = float32 ctx.root.vHeight

proc addRegion*(map: var CTXMap, rect: var GUIRect) =
  if rect.w > 0 and rect.h > 0:
    let offset = uint16(map.cursor*4)
    block: # Define Verts Array
      let
        x = float32 rect.x
        y = float32 rect.y
        xw = x + float32 rect.w
        yh = y + float32 rect.h
      map.vMap[0] = vertexUV(x, y)
      map.vMap[1] = vertexUV(xw, y)
      map.vMap[2] = vertexUV(x, yh)
      map.vMap[3] = vertexUV(xw, yh)
    # Define Elements Quad
    map.eMap[0] = offset; map.eMap[1] = offset+1
    map.eMap[2] = offset+2; map.eMap[3] = offset+3
    map.eMap[4] = offset+2; map.eMap[5] = offset+1
    # Change Pointer Position to Next
    map.vMap = cast[CTXVertexMap](addr map.vMap[4])
    map.eMap = cast[CTXElementMap](addr map.eMap[6])
    # Increment Visible Region Count
    inc(map.cursor)

proc unmapRegions*(ctx: var GUIContext, map: var CTXMap) {.inline.} =
  # Unmap EBO and VBO Buffers
  discard glUnmapBuffer(GL_ELEMENT_ARRAY_BUFFER)
  discard glUnmapBuffer(GL_ARRAY_BUFFER)
  # Unbind EBO and VBO
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0)
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  # Set Number of Regions
  ctx.visible = map.cursor

# -------------------
# CONTEXT RENDERING PROCS
# -------------------

proc ctxBegin*(ctx: var GUIContext) =
  # Use GUI program
  glUseProgram(ctx.program)
  # Disable 3D OpenGL Flags
  glDisable(GL_CULL_FACE)
  glDisable(GL_DEPTH_TEST)
  glDisable(GL_STENCIL_TEST)
  # Set Clear Color to Nothing
  glClearColor(0,0,0,0)
  # Set White Pixel Uniform
  glVertexAttrib4f(2, 1,1,1,1)
  # Enable Alpha Blending
  glEnable(GL_BLEND)
  glBlendEquation(GL_FUNC_ADD)
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  # Modify Only Texture 0
  glActiveTexture(GL_TEXTURE0)

proc viewport(ctx: var GUIContext, frame: CTXFrame) =
  glViewport(0, 0, frame.vWidth, frame.vHeight)
  glUniformMatrix4fv(ctx.projection, 1, false, 
    cast[ptr float32](addr frame.vCache))
  # Set new width and Height for Canvas
  viewport(ctx.canvas, frame.vWidth, frame.vHeight)

proc canvasBegin*(ctx: var GUIContext, frame: CTXFrame) =
  # Bind Frame's FBO
  glBindFramebuffer(GL_FRAMEBUFFER, frame.fbo)
  # Set Viewport to Frame
  viewport(ctx, frame)
  # Clear FBO if Dirty
  if frame.dirty: 
    glClear(GL_COLOR_BUFFER_BIT)
    frame.dirty = false
  # Make Canvas ready for drawing
  makeCurrent(ctx.canvas)

proc canvasEnd*(ctx: var GUIContext) =
  # Draw Commands
  clearCurrent(ctx.canvas)
  # Bind to Framebuffer Screen
  glBindFramebuffer(GL_FRAMEBUFFER, 0)
  # Set Viewport to Root
  viewport(ctx, ctx.root)
  # Set White Pixel Uniform
  glVertexAttrib4f(2, 1,1,1,1)

proc render*(ctx: var GUIContext, frame: CTXFrame) =
  glBindVertexArray(frame.vao) # Bind VAO
  glBindTexture(GL_TEXTURE_2D, frame.tex) # Bind Tex
  if frame == ctx.root: # Draw Regions or Rect
    glDrawElements(GL_TRIANGLES, ctx.visible*6, 
    GL_UNSIGNED_SHORT, cast[pointer](0))
  else: glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

proc ctxEnd*() =
  # Back Default Color to Black
  glVertexAttrib4f(2, 0,0,0,1)
  glClearColor(0,0,0,1)
  # Unbind Texture and VAO
  glBindTexture(GL_TEXTURE_2D, 0)
  glBindVertexArray(0)
  # Disable Alpha Blend
  glDisable(GL_BLEND)
  # Unbind Program
  glUseProgram(0)

# -------------------
# CONTEXT FRAME PROCS
# -------------------

proc useFrame*(ctx: var GUIContext, frame: var CTXFrame) {.inline.} =
  if len(ctx.unused) > 0: frame = pop(ctx.unused)
  else: frame = newCTXFrame(true)

proc unuseFrame*(ctx: var GUIContext, frame: var CTXFrame) {.inline.} =
  # Mark Frame as Nil and save for reuse
  add(ctx.unused, frame); frame = nil

proc region*(frame: CTXFrame, rect: GUIRect): bool {.discardable.} =
  result = rect.w != frame.vWidth or rect.h != frame.vHeight
  if result: # Check if resize is needed
    # Bind Texture
    glBindTexture(GL_TEXTURE_2D, frame.tex)
    # Resize Texture
    glTexImage2D(GL_TEXTURE_2D, 0, cast[int32](GL_RGBA8), rect.w, rect.h, 0,
        GL_RGBA, GL_UNSIGNED_BYTE, nil)
    # Unbind Texture
    glBindTexture(GL_TEXTURE_2D, 0)
    # Recalculate GUI Projection
    guiProjection(addr frame.vCache, float32 rect.w, float32 rect.h)
    frame.vWidth = rect.w; frame.vHeight = rect.h
    # Invalidate Texture
    frame.dirty = true
  if frame.fixed: # Replace VBO with new rect
    glBindBuffer(GL_ARRAY_BUFFER, frame.vbo) # Bind VBO
    let
      x = float32 rect.x
      y = float32 rect.y
      xw = x + float32 rect.w
      yh = y + float32 rect.h
      map = cast[CTXVertexMap]( # Map VBO
        glMapBuffer(GL_ARRAY_BUFFER, GL_WRITE_ONLY))
    # Update Rect
    map[0] = vertex(x, y, 0, 1)
    map[1] = vertex(xw, y, 1, 1)
    map[2] = vertex(x, yh, 0, 0)
    map[3] = vertex(xw, yh, 1, 0)
    # Unmap and Unbind VBO
    discard glUnmapBuffer(GL_ARRAY_BUFFER)
    glBindBuffer(GL_ARRAY_BUFFER, 0)