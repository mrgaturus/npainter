# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
import ../../libs/gl
import ../../assets
import matrix

type
  NCanvasVertex {.pure.} = object
    x, y, u, v: cushort
  NCanvasTile = object
    dPos0, dPos1: cushort
    texture: GLuint
  NCanvasRenderer* = object
    # OpenGL Objects
    program: GLuint
    uPro, uModel: GLint
    # Canvas Tiles
    pbo: GLuint
    usables: seq[GLuint]
  # Canvas Viewport Objects
  NCanvasBuffer = ref UncheckedArray[byte]
  NCanvasGrid = ptr UncheckedArray[NCanvasTile]
  # Canvas Viewport
  NCanvasViewport* = object
    renderer: ptr NCanvasRenderer
    affine*: NCanvasAffine
    # Grid Parameters
    w, h, lod: cint
    # Tile Geometry
    count: cint
    vao, vbo: GLuint
    # Grid Buffers
    buffer: NCanvasBuffer
    grid, cache: NCanvasGrid

# ------------------------
# Canvas Renderer Creation
# ------------------------

proc createCanvasRenderer*(): NCanvasRenderer =
  block: # -- Use Program for Define Uniforms
    result.program = newShader("canvas.vert", "canvas.frag")
    glUseProgram(result.program)
    # Define Projection and Texture Uniforms
    result.uPro = glGetUniformLocation(result.program, "uPro")
    result.uModel = glGetUniformLocation(result.program, "uModel")
    # Set Default Uniform Value: Tile Texture
    glUniform1i glGetUniformLocation(result.program, "uTile"), 0
    # Unuse Program
    glUseProgram(0)
    # Generate Pixel Buffer Object
    glGenBuffers(1, addr result.pbo)

proc createViewport*(ctx: var NCanvasRenderer; w, h: cint): NCanvasViewport =
  result.w = w
  result.h = h
  block: # Configure Grid
    let chunk = w * h * sizeof(NCanvasTile)
    # Allocate Viewport Locations
    unsafeNew(result.buffer, chunk shl 1)
    zeroMem(addr result.buffer[0], chunk shl 1)
    # Configure Grid Pointers
    result.grid = cast[NCanvasGrid](addr result.buffer[0])
    result.cache = cast[NCanvasGrid](addr result.buffer[chunk])
    # Canvas Affine Center
    result.affine.cw = w
    result.affine.ch = h
  block: # Configure OpenGL Objects
    glGenVertexArrays(1, addr result.vao)
    glGenBuffers(1, addr result.vbo)
    # Bind VAO and VBO
    glBindVertexArray(result.vao)
    glBindBuffer(GL_ARRAY_BUFFER, result.vbo)
    # Vertex Attribs XYVUV 8bytes
    glVertexAttribPointer(0, 2, GL_UNSIGNED_SHORT, false, 
      sizeof(NCanvasVertex).cint, cast[pointer](0)) # VERTEX
    glVertexAttribPointer(1, 2, GL_UNSIGNED_SHORT, true, 
      sizeof(NCanvasVertex).cint, cast[pointer](sizeof(cushort) * 2)) # UV
    # Enable Verter Attribs
    glEnableVertexAttribArray(0)
    glEnableVertexAttribArray(1)
    # Unbind VBO and VAO
    glBindBuffer(GL_ARRAY_BUFFER, 0)
    glBindVertexArray(0)
  # Canvas Renderer
  result.renderer = addr ctx

# --------------------------
# Canvas Render Tile Manager
# --------------------------

proc createTile(ctx: ptr NCanvasRenderer): cint =
  var texture: GLuint
  glGenTextures(1, addr texture)
  # Redundant Bind But Safer
  glBindTexture(GL_TEXTURE_2D, texture)
  glTexImage2D(GL_TEXTURE_2D, 0, cast[GLint](GL_RGBA8), 
    256, 256, 0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
  # Set Mig/Mag Filter
  glTexParameteri(GL_TEXTURE_2D, 
    GL_TEXTURE_MIN_FILTER, cast[GLint](GL_LINEAR))
  glTexParameteri(GL_TEXTURE_2D, 
    GL_TEXTURE_MAG_FILTER, cast[GLint](GL_LINEAR))
  # Set UV Mapping Clamping
  glTexParameteri(GL_TEXTURE_2D, 
    GL_TEXTURE_WRAP_S, cast[GLint](GL_CLAMP_TO_EDGE))
  glTexParameteri(GL_TEXTURE_2D, 
    GL_TEXTURE_WRAP_T, cast[GLint](GL_CLAMP_TO_EDGE))
  # Unbind Texture
  glBindTexture(GL_TEXTURE_2D, 0)
  # Add New Texture
  ctx.usables.add(texture)
  result = cint high(ctx.usables)

proc swapTiles*(view: var NCanvasViewport) =
  let l = view.w * view.h
  swap(view.cache, view.grid)
  zeroMem(view.grid, l * NCanvasTile.sizeof)
  # Reset Cache Counter
  view.count = 0

proc cacheTiles*(view: var NCanvasViewport) =
  # XXX: Remove Not Used Tiles
  discard

# --------------------------
# Canvas Render Tile Mapping
# --------------------------



# ----------------------
# Canvas Render Commands
# ----------------------

proc render*(view: var NCanvasViewport) =
  let ctx = view.renderer
  glUseProgram(ctx.program)
  # Upload View Projection Matrix
  glUniformMatrix4fv(ctx.uPro, 1, false,
    cast[ptr cfloat](addr view.affine.projection))
  # Upload View Transform Matrix
  glUniformMatrix3fv(ctx.uModel, 1, true,
    cast[ptr cfloat](addr view.affine.model0))
  # Render Each View Texture
  glBindVertexArray(view.vao)
  # Draw Each Tile
  var cursor: cint 
  while cursor < view.count:
    # Bind Texture and Draw Tile Quad
    glBindTexture(GL_TEXTURE_2D, view.cache[cursor].texture)
    glDrawArrays(GL_TRIANGLE_STRIP, cursor shl 2, 4)
    # Next Tile
    inc(cursor)
  # Unbind Current State
  glBindTexture(GL_TEXTURE_2D, 0)
  glBindVertexArray(0)
  glUseProgram(0)
