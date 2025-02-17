# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2025 Cristian Camilo Ruiz <mrgaturus>
import nogui/data
import nogui/libs/gl
import nogui/native/ffi
import ffi

type
  NCanvasOutline* = object
    lines*: NMaskOutline
    ubo, vao, vbo: GLuint
    # Outline Shader
    utime, uthick: GLint
    shader: GLuint
    wide, frame: GLfloat

# -----------------------
# Canvas Outline Creation
# -----------------------

proc configureShader(outline: var NCanvasOutline) =
  let shader = newShader("outline.vert", "outline.frag")
  outline.shader = shader
  outline.wide = 1.0
  # Configure Shader Uniforms
  glUseProgram(shader)
  outline.utime = glGetUniformLocation(shader, "uTime")
  outline.uthick = glGetUniformLocation(shader, "uThick")
  let index0 = glGetUniformBlockIndex(shader, "AffineBlock")
  let index1 = glGetUniformBlockIndex(shader, "BasicBlock")
  glUniformBlockBinding(shader, index0, 0)
  glUniformBlockBinding(shader, index1, 0)
  glUseProgram(0)

proc createCanvasOutline*(canvasUBO: GLuint): NCanvasOutline =
  result.configureShader()
  result.ubo = canvasUBO
  # Create Vertex Buffer
  glGenVertexArrays(1, addr result.vao)
  glGenBuffers(1, addr result.vbo)
  # Configure Vertex Array Object
  const stride = sizeof(int16) * 2
  glBindVertexArray(result.vao)
  glBindBuffer(GL_ARRAY_BUFFER, result.vbo)
  glVertexAttribIPointer(0, 2, GL_UNSIGNED_SHORT,
    stride, cast[pointer](0))
  glEnableVertexAttribArray(0)
  # Remove VAO and VBO Binding
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  glBindVertexArray(0)

# ------------------------
# Canvas Outline Rendering
# ------------------------

proc width*(outline: var NCanvasOutline, thick: GLfloat) =
  var limit {.noinit.}: array[2, GLfloat]
  glGetFloatv(GL_ALIASED_LINE_WIDTH_RANGE, addr limit[0])
  outline.wide = clamp(thick, limit[0], limit[1])

proc copy*(outline: var NCanvasOutline) =
  const bpp = sizeof(uint16)
  let lines = addr outline.lines
  # Copy Outline Geometry to GPU
  glBindBuffer(GL_ARRAY_BUFFER, outline.vbo)
  glBufferData(GL_ARRAY_BUFFER, lines.count * bpp,
    lines.buffer, GL_STATIC_DRAW)
  glBindBuffer(GL_ARRAY_BUFFER, 0)

proc render*(outline: var NCanvasOutline) =
  glUseProgram(outline.shader)
  glBindVertexArray(outline.vao)
  glBindBufferBase(GL_UNIFORM_BUFFER, 0, outline.ubo)
  glLineWidth(outline.wide)
  block rendering:
    glUniform1f(outline.utime, outline.frame)
    glUniform1f(outline.uthick, 0.5 / outline.wide)
    glDrawArrays(GL_LINES, 0,
      outline.lines.count shr 1)
    outline.frame += 0.125
  glBindVertexArray(0)
  glUseProgram(0)
