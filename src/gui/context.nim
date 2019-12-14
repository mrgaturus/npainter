from ../math import orthoProjection, uvNormalize
from ../shader import newSimpleProgram

import ../libs/gl
import render

type
  # Root Frame Regions
  CTXRegion = object
    vaoID, vboID: GLuint
    rect: ptr GUIRect
    # Visible
    visible: bool
  # Floating Frames
  CTXFrame* = object
    texID, fboID: GLuint
    vaoID, vboID: GLuint
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
    texID, fboID: GLuint
    regions: seq[CTXRegion]
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
  glGenTextures(1, addr result.texID)
  glGenFramebuffers(1, addr result.fboID)
  # Bind FrameBuffer and Texture
  glUseProgram(result.program)
  glBindFramebuffer(GL_FRAMEBUFFER, result.fboID)
  glBindTexture(GL_TEXTURE_2D, result.texID)
  # Set Texture Parameters
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, cast[GLint](GL_LINEAR))
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, cast[GLint](GL_LINEAR))
  # Attach Texture
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
      result.texID, 0)
  # Set shader sampler2D uniform
  glUniform1i(glGetUniformLocation(result.program, "uTex"), 0)
  # Unbind Texture and Framebuffer
  glBindTexture(GL_TEXTURE_2D, 0)
  glBindFramebuffer(GL_FRAMEBUFFER, 0)
  glUseProgram(0)

# -------------------
# CONTEXT HELPER PROCS
# -------------------

proc update(region: var CTXRegion, w, h: int32) =
  let rect = addr region.rect
  region.visible = rect.w > 0 and rect.h > 0
  # if visible, update vbo
  if region.visible:
    glBindBuffer(GL_ARRAY_BUFFER, region.vboID)
    block:
      let rectArray = [
        float32 rect.x, float32 rect.y,
        float32(rect.x + rect.w), float32 rect.y,
        float32 rect.x, float32(rect.y + rect.h),
        float32(rect.x + rect.w), float32(rect.y + rect.h)
      ]
      glBufferSubData(GL_ARRAY_BUFFER, 0, vertSize, rectArray[0].unsafeAddr)
      uvNormalize(rectArray[0].unsafeAddr, float32 w, float32 h)
      glBufferSubData(GL_ARRAY_BUFFER, vertSize, vertSize, rectArray[0].unsafeAddr)
    glBindBuffer(GL_ARRAY_BUFFER, 0)

# -------------------
# CONTEXT WINDOW PROCS
# -------------------

proc createRegion*(ctx: var GUIContext, rect: ptr GUIRect) =
  var region: CTXRegion
  # Create New VAO
  glGenVertexArrays(1, addr region.vaoID)
  glBindVertexArray(region.vaoID)
  # Alloc new Buffer (VVVVCCCC)
  glGenBuffers(1, addr region.vboID)
  glBindBuffer(GL_ARRAY_BUFFER, region.vboID)
  glBufferData(GL_ARRAY_BUFFER, bufferSize, nil, GL_DYNAMIC_DRAW)
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
  # Associate Rect
  region.rect = rect
  region.visible = true
  # Add new region to root frame
  ctx.regions.add(region)

proc createFrame*(): CTXFrame =
  # -- Gen VAO
  glGenVertexArrays(1, addr result.vaoID)
  glBindVertexArray(result.vaoID)
  # Alloc new Buffer (VVVVCCCC) with fixed texture coods
  glGenBuffers(1, addr result.vboID)
  glBindBuffer(GL_ARRAY_BUFFER, result.vboID)
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
  # -- Gen Framebuffer
  glGenTextures(1, addr result.texID)
  glGenFramebuffers(1, addr result.fboID)
  # Bind Texture and Framebuffer
  glBindFramebuffer(GL_FRAMEBUFFER, result.fboID)
  glBindTexture(GL_TEXTURE_2D, result.texID)
  # Set Texture Parameters
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, cast[GLint](GL_LINEAR))
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, cast[GLint](GL_LINEAR))
  # Attach Texture
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
      result.texID, 0)
  # Unbind Texture and Framebuffer
  glBindTexture(GL_TEXTURE_2D, 0)
  glBindFramebuffer(GL_FRAMEBUFFER, 0)

proc resize*(ctx: var GUIContext, rect: ptr GUIRect) =
  # Bind Texture
  glBindTexture(GL_TEXTURE_2D, ctx.texID)
  # Resize Texture
  glTexImage2D(GL_TEXTURE_2D, 0, cast[int32](GL_RGBA8), rect.w, rect.h, 0,
      GL_RGBA, GL_UNSIGNED_BYTE, nil)
  # Unbind Texture
  glBindTexture(GL_TEXTURE_2D, 0)
  # Change viewport
  orthoProjection(addr ctx.vCache, 0, float32 rect.w, float32 rect.h, 0)
  ctx.vWidth = rect.w
  ctx.vHeight = rect.h

proc update*(ctx: var GUIContext) =
  for region in mitems(ctx.regions):
    update(region, ctx.vWidth, ctx.vHeight)

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
  # Clear Levels
  reset(ctx.render, frame.vHeight)
  # Bind Frame's FBO
  glBindFramebuffer(GL_FRAMEBUFFER, frame.fboID)
  glViewport(0, 0, frame.vWidth, frame.vHeight)
  glUniformMatrix4fv(ctx.uPro, 1, false,
    cast[ptr float32](addr frame.vCache)
  )

proc makeCurrent*(ctx: var GUIContext) =
  # Clear Levels
  reset(ctx.render, ctx.vHeight)
  # Bind Root FBO & Use Viewport
  glBindFramebuffer(GL_FRAMEBUFFER, ctx.fboID)
  glViewport(0, 0, ctx.vWidth, ctx.vHeight)
  glUniformMatrix4fv(ctx.uPro, 1, false,
    cast[ptr float32](addr ctx.vCache)
  )

proc clearCurrent*(ctx: var GUIContext) =
  # Bind to Framebuffer Screen
  glBindFramebuffer(GL_FRAMEBUFFER, 0)
  # Set To White Pixel
  reset(ctx.render)
  # Set Viewport to root
  glViewport(0, 0, ctx.vWidth, ctx.vHeight)
  glUniformMatrix4fv(ctx.uPro, 1, false,
    cast[ptr float32](addr ctx.vCache)
  )

proc render*(ctx: var GUIContext) =
  # Draw Regions
  glBindTexture(GL_TEXTURE_2D, ctx.texID)
  for region in mitems(ctx.regions):
    # Draw Region if is visible
    if region.visible:
      glBindVertexArray(region.vaoID)
      glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

proc render*(frame: var CTXFrame) =
  glBindVertexArray(frame.vaoID)
  glBindTexture(GL_TEXTURE_2D, frame.texID)
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
    glBindTexture(GL_TEXTURE_2D, frame.texID)
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
  glBindBuffer(GL_ARRAY_BUFFER, frame.vboID)
  # Replace Vertex
  glBufferSubData(GL_ARRAY_BUFFER, 0, vertSize, unsafeAddr verts[0])
  # Unbind VBO
  glBindBuffer(GL_ARRAY_BUFFER, 0)
