from ../math import uvNormalize, guiProjection
from ../shader import newProgram

import ../libs/gl
import render

type
  # Root Frame Regions
  CTXRegion = ptr GUIRect
  # Floating Frames
  CTXFrame* = ref object
    vao, vbo, tex, fbo: GLuint
    # Frame viewport cache
    vWidth, vHeight: int32
    vCache: array[16, float32]
  # The Context
  GUIContext* = object
    # CTX GUI Renderer
    program: GLuint
    render: CTXRender
    # Root Frame
    vao, vbo0, vbo1: GLuint
    tex, fbo: GLuint
    # GUI viewport cache
    vWidth, vHeight: int32
    vCache: array[16, float32]
    # Root Regions
    regions: seq[CTXRegion]
    visible: int32
    # Unused Frames
    unused: seq[CTXFrame]

# -------------------
# CONTEXT CONST PROCS
# -------------------

const
  bufferSize = 16 * sizeof(float32)
  vertSize = 8 * sizeof(float32)
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
  result.render = newCTXRender(
    glGetUniformLocation(result.program, "uPro"),
    glGetUniformLocation(result.program, "uCol")
  )
  glUniform1i(
    glGetUniformLocation(result.program, "uTex"), 0
  )
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

proc allocRegions*(ctx: var GUIContext) =
  # Create New VAO
  glGenVertexArrays(1, addr ctx.vao)
  glGenBuffers(2, addr ctx.vbo0)
  # Bind VAO and VBO
  glBindVertexArray(ctx.vao)
  # Vertex Buffer (VVVV)
  glBindBuffer(GL_ARRAY_BUFFER, ctx.vbo0)
  glBufferData(GL_ARRAY_BUFFER, len(ctx.regions) * vertSize, nil, GL_DYNAMIC_DRAW)
  glVertexAttribPointer(0, 2, cGL_FLOAT, false, 0, cast[pointer](0))
  # Coords Buffer (CCCC)
  glBindBuffer(GL_ARRAY_BUFFER, ctx.vbo1)
  glBufferData(GL_ARRAY_BUFFER, len(ctx.regions) * vertSize, nil, GL_DYNAMIC_DRAW)
  glVertexAttribPointer(1, 2, cGL_FLOAT, false, 0, cast[pointer](0))
  # Enable Attribs
  glEnableVertexAttribArray(0)
  glEnableVertexAttribArray(1)
  # Unbind VBO and VAO
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  glBindVertexArray(0)

# -------------------
# CONTEXT WINDOW PROCS
# -------------------

proc createRegion*(ctx: var GUIContext, rect: CTXRegion) =
  ctx.regions.add(rect)

proc update*(ctx: var GUIContext) =
  # Visible Count
  var count = 0'i32
  # Update VBO With Regions
  for rect in ctx.regions:
    if rect.w > 0 and rect.h > 0:
      let offset = vertSize * count
      var rectArray = [
        float32 rect.x, float32 rect.y,
        float32(rect.x + rect.w), float32 rect.y,
        float32 rect.x, float32(rect.y + rect.h),
        float32(rect.x + rect.w), float32(rect.y + rect.h)
      ]
      # Vertex Update
      glBindBuffer(GL_ARRAY_BUFFER, ctx.vbo0)
      glBufferSubData(GL_ARRAY_BUFFER, offset, vertSize, addr rectArray[0])
      # Coord Update
      glBindBuffer(GL_ARRAY_BUFFER, ctx.vbo1)
      uvNormalize(addr rectArray[0], float32 ctx.vWidth, float32 ctx.vHeight)
      glBufferSubData(GL_ARRAY_BUFFER, offset, vertSize, addr rectArray[0])
      # Increment Visible Regions
      inc(count)
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  # Set Visible Count
  ctx.visible = count

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
# CONTEXT RENDER PROCS
# -------------------

template render*(ctx: var GUIContext): ptr CTXRender =
  addr ctx.render

proc start*(ctx: var GUIContext) =
  # Use GUI program
  glUseProgram(ctx.program)
  # Prepare OpenGL Flags
  glDisable(GL_DEPTH_TEST)
  glDisable(GL_STENCIL_TEST)
  # Modify Only Texture 0
  glActiveTexture(GL_TEXTURE0)

proc makeCurrent*(ctx: var GUIContext, frame: CTXFrame) =
  if isNil(frame): # Make Root current
    # Bind Root FBO & Use Viewport
    glBindFramebuffer(GL_FRAMEBUFFER, ctx.fbo)
    # Set Root Viewport
    viewport(ctx.render, ctx.vWidth, ctx.vHeight,
      cast[ptr float32](addr ctx.vCache)
    )
  else: # Make Frame Current
    # Bind Frame's FBO
    glBindFramebuffer(GL_FRAMEBUFFER, frame.fbo)
    # Set Frame Viewport
    viewport(ctx.render, frame.vWidth, frame.vHeight,
      cast[ptr float32](addr frame.vCache)
    )
  # Make Renderer ready for GUI Drawing
  makeCurrent(ctx.render)

proc clearCurrent*(ctx: var GUIContext) =
  # Bind to Framebuffer Screen
  glBindFramebuffer(GL_FRAMEBUFFER, 0)
  # Set Root Viewport
  viewport(ctx.render, ctx.vWidth, ctx.vHeight,
    cast[ptr float32](addr ctx.vCache)
  )
  # Set To White Pixel
  clearCurrent(ctx.render)

proc render*(ctx: var GUIContext, frame: CTXFrame) =
  if isNil(frame): # Draw Regions
    glBindVertexArray(ctx.vao)
    glBindTexture(GL_TEXTURE_2D, ctx.tex)
    for index in `..<`(0, ctx.visible):
      glDrawArrays(GL_TRIANGLE_STRIP, index*4, 4)
  else: # Draw Frames
    glBindVertexArray(frame.vao)
    glBindTexture(GL_TEXTURE_2D, frame.tex)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

proc finish*() =
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
  glBufferData(GL_ARRAY_BUFFER, bufferSize, nil, GL_DYNAMIC_DRAW)
  glBufferSubData(GL_ARRAY_BUFFER, vertSize, vertSize, texCORDS[0].unsafeAddr)
  # Configure Attribs
  glVertexAttribPointer(0, 2, cGL_FLOAT, false, 0, cast[
      pointer](0))
  glVertexAttribPointer(1, 2, cGL_FLOAT, false, 0, cast[
      pointer](vertSize))
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
  let verts = [
    float32 rect.x, float32 rect.y,
    float32(rect.x + rect.w), float32 rect.y,
    float32 rect.x, float32(rect.y + rect.h),
    float32(rect.x + rect.w), float32(rect.y + rect.h)
  ]
  # Bind VBO
  glBindBuffer(GL_ARRAY_BUFFER, frame.vbo)
  # Replace Vertex
  glBufferSubData(GL_ARRAY_BUFFER, 0, vertSize, unsafeAddr verts[0])
  # Unbind VBO
  glBindBuffer(GL_ARRAY_BUFFER, 0)
