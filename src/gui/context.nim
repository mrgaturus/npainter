from ../math import orthoProjection, uvNormalize
from ../shader import newSimpleProgram

import ../libs/gl
import render

type
  # Root Frame Regions
  CTXRegion = ptr GUIRect
  # Floating Frames
  CTXFrame* = object
    vao, vbo, tex, fbo: GLuint
    # Frame viewport cache
    vWidth, vHeight: int32
    vCache: array[16, float32]
  # The Context
  GUIContext* = object
    # GUI Program and Projection
    program: GLuint
    uPro: GLint
    # GUI viewport cache
    vWidth, vHeight: int32
    vCache: array[16, float32]
    # Root Frame
    vao, vbo0, vbo1: GLuint
    tex, fbo: GLuint
    regions: seq[CTXRegion]
    visible: int32
    # GUI render
    render*: GUIRender

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
  # Initialize GUI Program
  result.program = newSimpleProgram("shaders/gui.vert", "shaders/gui.frag")
  result.uPro = glGetUniformLocation(result.program, "uPro")
  # Initialize GUI Render
  result.render = newGUIRender(
    glGetUniformLocation(result.program, "uCol")
  )
  # Initialize Root Frame
  glGenTextures(1, addr result.tex)
  glGenFramebuffers(1, addr result.fbo)
  # Bind FrameBuffer and Texture
  glUseProgram(result.program)
  glBindFramebuffer(GL_FRAMEBUFFER, result.fbo)
  glBindTexture(GL_TEXTURE_2D, result.tex)
  # Set Texture Parameters
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, cast[GLint](GL_LINEAR))
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, cast[GLint](GL_LINEAR))
  # Attach Texture
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
      result.tex, 0)
  # Set shader sampler2D uniform
  glUniform1i(glGetUniformLocation(result.program, "uTex"), 0)
  # Unbind Texture and Framebuffer
  glBindTexture(GL_TEXTURE_2D, 0)
  glBindFramebuffer(GL_FRAMEBUFFER, 0)
  glUseProgram(0)

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

proc createRegion*(ctx: var GUIContext, rect: ptr GUIRect) =
  ctx.regions.add(rect)

proc update*(ctx: var GUIContext) =
  # Clear Visible Count
  ctx.visible = 0
  # Update VBO With Regions
  for index, rect in pairs(ctx.regions):
    if rect.w > 0 and rect.h > 0:
      let offset = vertSize * index
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
      inc(ctx.visible)
  glBindBuffer(GL_ARRAY_BUFFER, 0)

proc resize*(ctx: var GUIContext, rect: ptr GUIRect) =
  # Bind Texture
  glBindTexture(GL_TEXTURE_2D, ctx.tex)
  # Resize Texture
  glTexImage2D(GL_TEXTURE_2D, 0, cast[int32](GL_RGBA8), rect.w, rect.h, 0,
      GL_RGBA, GL_UNSIGNED_BYTE, nil)
  # Unbind Texture
  glBindTexture(GL_TEXTURE_2D, 0)
  # Change viewport
  orthoProjection(addr ctx.vCache, 0, float32 rect.w, float32 rect.h, 0)
  ctx.vWidth = rect.w
  ctx.vHeight = rect.h

proc createFrame*(): CTXFrame =
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
# CONTEXT RENDER PROC
# -------------------

proc `[]`*(ctx: var GUIContext): ptr GUIRender {.inline.} =
  return addr(ctx.render)

# -------------------
# CONTEXT RENDER PROCS
# -------------------

proc start*(ctx: var GUIContext) =
  # Use GUI program
  glUseProgram(ctx.program)
  # Prepare OpenGL Flags
  glDisable(GL_DEPTH_TEST)
  glDisable(GL_STENCIL_TEST)
  # Modify Only Texture 0
  glActiveTexture(GL_TEXTURE0)

proc makeCurrent*(ctx: var GUIContext, frame: var CTXFrame) =
  # Bind Frame's FBO
  glBindFramebuffer(GL_FRAMEBUFFER, frame.fbo)
  # Clear Render Levels
  makeCurrent(ctx.render, frame.vHeight)
  # Set Frame Viewport
  glViewport(0, 0, frame.vWidth, frame.vHeight)
  glUniformMatrix4fv(ctx.uPro, 1, false,
    cast[ptr float32](addr frame.vCache)
  )

proc makeCurrent*(ctx: var GUIContext) =
  # Bind Root FBO & Use Viewport
  glBindFramebuffer(GL_FRAMEBUFFER, ctx.fbo)
  # Clear Render Levels
  makeCurrent(ctx.render, ctx.vHeight)
  # Set Root Viewport
  glViewport(0, 0, ctx.vWidth, ctx.vHeight)
  glUniformMatrix4fv(ctx.uPro, 1, false,
    cast[ptr float32](addr ctx.vCache)
  )

proc clearCurrent*(ctx: var GUIContext) =
  # Bind to Framebuffer Screen
  glBindFramebuffer(GL_FRAMEBUFFER, 0)
  # Set To White Pixel
  clearCurrent(ctx.render)
  # Set Root Viewport
  glViewport(0, 0, ctx.vWidth, ctx.vHeight)
  glUniformMatrix4fv(ctx.uPro, 1, false,
    cast[ptr float32](addr ctx.vCache)
  )

proc render*(ctx: var GUIContext) =
  # Draw Regions
  glBindVertexArray(ctx.vao)
  glBindTexture(GL_TEXTURE_2D, ctx.tex)
  for index in `..<`(0, ctx.visible):
    glDrawArrays(GL_TRIANGLE_STRIP, index*4, 4)

proc render*(frame: var CTXFrame) =
  glBindVertexArray(frame.vao)
  glBindTexture(GL_TEXTURE_2D, frame.tex)
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

proc finish*(ctx: var GUIContext) =
  # Set program to None program
  glBindTexture(GL_TEXTURE_2D, 0)
  glBindVertexArray(0)
  glUseProgram(0)

# -------------------
# CONTEXT FRAME PROCS
# -------------------

proc region*(frame: var CTXFrame, rect: ptr GUIRect) =
  let
    w = rect.w
    h = rect.h
  if w != frame.vWidth and h != frame.vHeight:
    # Bind Texture
    glBindTexture(GL_TEXTURE_2D, frame.tex)
    # Resize Texture
    glTexImage2D(GL_TEXTURE_2D, 0, cast[int32](GL_RGBA8), w, h, 0,
        GL_RGBA, GL_UNSIGNED_BYTE, nil)
    # Unbind Texture
    glBindTexture(GL_TEXTURE_2D, 0)
    # Resize Viewport
    orthoProjection(addr frame.vCache, 0, float32 w, float32 h, 0)
    frame.vWidth = w
    frame.vHeight = h
  # Replace VBO with new rect
  let verts = [
    float32 rect.x, float32 rect.y,
    float32(rect.x + w), float32 rect.y,
    float32 rect.x, float32(rect.y + h),
    float32(rect.x + w), float32(rect.y + h)
  ]
  # Bind VBO
  glBindBuffer(GL_ARRAY_BUFFER, frame.vbo)
  # Replace Vertex
  glBufferSubData(GL_ARRAY_BUFFER, 0, vertSize, unsafeAddr verts[0])
  # Unbind VBO
  glBindBuffer(GL_ARRAY_BUFFER, 0)
