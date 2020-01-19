from ../math import uvNormalize, guiProjection
from ../shader import newProgram

import ../libs/gl
import render

type
  # Floating Frames
  CTXBufferMap = # For glMap
    ptr UncheckedArray[float32]
  CTXFrame* = ref object
    vao, vbo, tex, fbo: GLuint
    # Frame viewport cache
    vWidth, vHeight: int32
    vCache: array[16, float32]
  # The Context
  GUIContext* = object
    # CTX GUI Renderer
    program: GLuint
    canvas: CTXCanvas
    # Root Regions
    vao, vbo: GLuint
    tex, fbo: GLuint
    visible, max: int32
    # GUI viewport cache
    vWidth, vHeight: int32
    vCache: array[16, float32]
    # Unused Frames
    unused: seq[CTXFrame]

# -------------------
# CONTEXT CONST PROCS
# -------------------

const # Buffer Sizes
  SIZE_REGION = 12 * sizeof(float32)
  SIZE_FRAME = 8 * sizeof(float32)
let texCORDS = [
  0'f32, 1'f32,
  1'f32, 1'f32,
  0'f32, 0'f32,
  1'f32, 0'f32
]

# -------------------
# CONTEXT CREATION/DISPOSE PROCS
# -------------------

proc newGUIContext*(): GUIContext =
  # Create new Program
  result.program = newProgram("shaders/gui.vert", "shaders/gui.frag")
  # Initialize Uniforms
  glUseProgram(result.program)
  result.canvas = newCTXCanvas(glGetUniformLocation(result.program, "uPro"))
  glUniform1i(glGetUniformLocation(result.program, "uTex"), 0)
  glUseProgram(0)
  # Initialize Root Frame
  glGenTextures(1, addr result.tex)
  glGenFramebuffers(1, addr result.fbo)
  # Bind FrameBuffer and Texture
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

# ------------------
# CONTEXT ROOT PROCS
# ------------------

proc allocRegions*(ctx: var GUIContext, count: int32) =
  # Create New VAO
  glGenVertexArrays(1, addr ctx.vao)
  glGenBuffers(1, addr ctx.vbo)
  # Bind VAO and VBO
  glBindVertexArray(ctx.vao)
  # Alloc New VBO with max size
  glBindBuffer(GL_ARRAY_BUFFER, ctx.vbo)
  glBufferData(GL_ARRAY_BUFFER, count * SIZE_REGION * 2, nil, GL_DYNAMIC_DRAW)
  # Define Attrib Layout (VVVVCCCC)
  glVertexAttribPointer(0, 2, cGL_FLOAT, false, 0,
    cast[pointer](0)
  ) # Vertex (VVVVCCCC)
  glVertexAttribPointer(1, 2, cGL_FLOAT, false, 0,
    cast[pointer](count * SIZE_REGION)
  ) # Coords (VVVVCCCC)
  # Enable Attribs
  glEnableVertexAttribArray(0)
  glEnableVertexAttribArray(1)
  # Unbind VBO and VAO
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  glBindVertexArray(0)
  # Define Maximun Regions
  ctx.max = count

proc mapRegions*(ctx: var GUIContext): CTXBufferMap =
  ctx.visible = 0 # Move Cursor to 0
  glBindBuffer(GL_ARRAY_BUFFER, ctx.vbo) # Modify Root Vertex Array
  return cast[CTXBufferMap](
    glMapBuffer(GL_ARRAY_BUFFER, GL_WRITE_ONLY)
  )

proc addRegion*(ctx: var GUIContext, map: CTXBufferMap, rect: var GUIRect) =
  if rect.w > 0 and rect.h > 0:
    let offset = ctx.visible*12
    var verts: array[12, float32]
    block: # Define Verts Array
      let
        x = float32 rect.x
        y = float32 rect.y
        xw = x + float32 rect.w
        yh = y + float32 rect.h
      verts = [
        # Triangle 1
        x, y, # 0
        xw, y, # 1
        x, yh, # 2
        # Triangle 2
        xw, yh, # 3
        x, yh, # 2
        xw, y # 1
      ]
    # Vertex
    copyMem(addr map[offset], addr verts, SIZE_REGION)
    # Tex Coords - Normalized
    uvNormalize(addr verts, float32 ctx.vWidth, float32 ctx.vHeight)
    copyMem(addr map[offset + ctx.max*12], addr verts, SIZE_REGION)
    # Increment Visible Region Count
    inc(ctx.visible)

proc unmapRegions*(ctx: var GUIContext) {.inline.} =
  discard glUnmapBuffer(GL_ARRAY_BUFFER) # Guaranted
  glBindBuffer(GL_ARRAY_BUFFER, 0)

# Resize FBO Texture
proc resize*(ctx: var GUIContext, rect: ptr GUIRect) =
  # Bind Texture
  glBindTexture(GL_TEXTURE_2D, ctx.tex)
  # Resize Texture
  glTexImage2D(GL_TEXTURE_2D, 0, cast[int32](GL_RGBA8), rect.w, rect.h, 0,
      GL_RGBA, GL_UNSIGNED_BYTE, nil)
  # Unbind Texture
  glBindTexture(GL_TEXTURE_2D, 0)
  # Change viewport
  guiProjection(addr ctx.vCache, 0, float32 rect.w, float32 rect.h, 0)
  ctx.vWidth = rect.w
  ctx.vHeight = rect.h

# -------------------
# CONTEXT RENDERING PROCS
# -------------------

template canvas*(ctx: var GUIContext): ptr CTXCanvas =
  addr ctx.canvas

proc start*(ctx: var GUIContext) =
  # Use GUI program
  glUseProgram(ctx.program)
  # Disable 3D OpenGL Flags
  glDisable(GL_CULL_FACE)
  glDisable(GL_DEPTH_TEST)
  glDisable(GL_STENCIL_TEST)
  # Enable Alpha Blending
  glEnable(GL_BLEND)
  glBlendEquation(GL_FUNC_ADD)
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  # Modify Only Texture 0
  glActiveTexture(GL_TEXTURE0)

proc makeCurrent*(ctx: var GUIContext, frame: CTXFrame) =
  if isNil(frame): # Make Root current
    # Bind Root FBO & Use Viewport
    glBindFramebuffer(GL_FRAMEBUFFER, ctx.fbo)
    # Set Root Viewport
    viewport(ctx.canvas, ctx.vWidth, ctx.vHeight,
      cast[ptr float32](addr ctx.vCache)
    )
  else: # Make Frame Current
    # Bind Frame's FBO
    glBindFramebuffer(GL_FRAMEBUFFER, frame.fbo)
    # Set Frame Viewport
    viewport(ctx.canvas, frame.vWidth, frame.vHeight,
      cast[ptr float32](addr frame.vCache)
    )
  # Make Renderer ready for GUI Drawing
  makeCurrent(ctx.canvas)

proc clearCurrent*(ctx: var GUIContext) =
  # Draw Commands
  clearCurrent(ctx.canvas)
  # Bind to Framebuffer Screen
  glBindFramebuffer(GL_FRAMEBUFFER, 0)
  # Set Root Viewport
  viewport(ctx.canvas, ctx.vWidth, ctx.vHeight,
    cast[ptr float32](addr ctx.vCache)
  )

proc render*(ctx: var GUIContext, frame: CTXFrame) =
  glVertexAttrib4f(2, 1,1,1,1) # White Pixel
  if isNil(frame): # Draw Root Regions
    glBindVertexArray(ctx.vao)
    glBindTexture(GL_TEXTURE_2D, ctx.tex)
    glDrawArrays(GL_TRIANGLES, 0, ctx.visible*12)
  else: # Draw Frame
    glBindVertexArray(frame.vao)
    glBindTexture(GL_TEXTURE_2D, frame.tex)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

proc finish*() =
  # Back Default Color to Black
  glVertexAttrib4f(2, 0,0,0,1)
  glClearColor(0,0,0,1)
  # Set program to None program
  glBindTexture(GL_TEXTURE_2D, 0)
  glBindVertexArray(0)
  glUseProgram(0)

# ---------------------------
# CONTEXT FRAME CREATION PROC
# ---------------------------

proc createFrame(): CTXFrame =
  new result
  # -- Create New VAO
  glGenVertexArrays(1, addr result.vao)
  glGenBuffers(1, addr result.vbo)
  # Bind VAO and VBO
  glBindVertexArray(result.vao)
  glBindBuffer(GL_ARRAY_BUFFER, result.vbo)
  # Alloc new Buffer (VVVVCCCC) with fixed texture coods
  glBufferData(GL_ARRAY_BUFFER, SIZE_FRAME * 2, nil, GL_DYNAMIC_DRAW)
  glBufferSubData(GL_ARRAY_BUFFER, SIZE_FRAME, SIZE_FRAME, texCORDS[0].unsafeAddr)
  # Configure Attribs
  glVertexAttribPointer(0, 2, cGL_FLOAT, false, 0, cast[
      pointer](0))
  glVertexAttribPointer(1, 2, cGL_FLOAT, false, 0, cast[
      pointer](SIZE_FRAME))
  # Enable Attribs
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

# -------------------
# CONTEXT FRAME PROCS
# -------------------

proc useFrame*(ctx: var GUIContext, frame: var CTXFrame) {.inline.} =
  if len(ctx.unused) > 0: frame = pop(ctx.unused)
  else: frame = createFrame()

proc unuseFrame*(ctx: var GUIContext, frame: var CTXFrame) {.inline.} =
  add(ctx.unused, frame)
  # Mark Frame Ref as Nil
  frame = nil

proc region*(frame: CTXFrame, rect: GUIRect): bool {.discardable.} =
  # Check if resize is needed
  result = rect.w != frame.vWidth or rect.h != frame.vHeight
  if result:
    # Bind Texture
    glBindTexture(GL_TEXTURE_2D, frame.tex)
    # Resize Texture
    glTexImage2D(GL_TEXTURE_2D, 0, cast[int32](GL_RGBA8), rect.w, rect.h, 0,
        GL_RGBA, GL_UNSIGNED_BYTE, nil)
    # Unbind Texture
    glBindTexture(GL_TEXTURE_2D, 0)
    # Resize Viewport
    guiProjection(addr frame.vCache, 0, float32 rect.w, float32 rect.h, 0)
    frame.vWidth = rect.w
    frame.vHeight = rect.h
  # Replace VBO with new rect
  var verts = [
    float32 rect.x, float32 rect.y,
    float32(rect.x + rect.w), float32 rect.y,
    float32 rect.x, float32(rect.y + rect.h),
    float32(rect.x + rect.w), float32(rect.y + rect.h)
  ]
  # Bind VBO
  glBindBuffer(GL_ARRAY_BUFFER, frame.vbo)
  # Replace Vertex
  glBufferSubData(GL_ARRAY_BUFFER, 0, SIZE_FRAME, addr verts)
  # Unbind VBO
  glBindBuffer(GL_ARRAY_BUFFER, 0)
