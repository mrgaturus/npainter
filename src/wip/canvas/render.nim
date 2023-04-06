# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
import ../../libs/gl
import ../../assets
import matrix, grid

type
  NCanvasVertex = tuple[x, y, u, v: cushort]
  NCanvasPBOMap = ref object
    tile: ptr NCanvasTile
    # Chunk Mapping
    offset, bytes: GLint
    chunk: pointer
  NCanvasRenderer* = object
    # OpenGL Objects
    program: GLuint
    uPro, uModel: GLint
    # OpenGL Textures
    usables: seq[GLuint]
    # OpenGL Mappers
    dummy, pbo: GLuint
    bytes: GLint
    mappers: seq[NCanvasPBOMap]
  # Canvas Viewport
  NCanvasViewport* = object
    renderer: ptr NCanvasRenderer
    affine*: NCanvasAffine
    # Canvas Image Size
    w, h: cint
    # Tile Geometry
    vao, vbo: GLuint
    grid: NCanvasGrid

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
  result.renderer = addr ctx
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
  block: # Canvas Grid
    let
      w256 = (w + 255) shr 8
      h256 = (h + 255) shr 8
    result.grid = createCanvasGrid(w256, h256)
  # Viewport Size
  result.w = w
  result.h = h

# --------------------------
# Canvas Render Tile Usables
# --------------------------

proc recycle(ctx: ptr NCanvasRenderer): GLuint =
  if ctx.usables.len > 0:
    return ctx.usables.pop()
  else: # Create New Tile Texture
    glGenTextures(1, addr result)
    # Redundant Bind But Safer
    glBindTexture(GL_TEXTURE_2D, result)
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
    ctx.usables.add(result)

proc recycle(ctx: ptr NCanvasRenderer, tile: GLuint) {.inline.} =
  # Add New Tile to Usables
  ctx.usables.add(tile)

# -----------------------------
# Canvas Viewport Tile Location
# -----------------------------

proc locateSamples(view: var NCanvasViewport) =
  let dummy = view.renderer.dummy
  # Locate Four Samples
  for batch in batches(view.grid):
    let
      x0 = cast[cint](batch.tile.x0)
      y0 = cast[cint](batch.tile.y0)
    # Locate Four Samples
    batch.sample[] = view.grid.sample(dummy, x0, y0)

proc locatePositions(view: var NCanvasViewport) =
  let 
    count = view.grid.count
    ctx = view.renderer
  glBindBuffer(GL_ARRAY_BUFFER, view.vbo)
  # Change Buffer VBO Size
  const 
    p0 = low(cushort)
    p1 = high(cushort)
    chunk = GLint(NCanvasVertex.sizeof)
  glBufferData(GL_ARRAY_BUFFER,
    count * chunk * 4, nil, GL_STATIC_DRAW)
  # Map Chunk Buffer
  let map = cast[ptr UncheckedArray[NCanvasVertex]](
    glMapBuffer(GL_ARRAY_BUFFER, GL_WRITE_ONLY))
  var
    x256, y256: cushort
    x512, y512: cushort
    cursor: cint
  # Locate Each Batch
  for batch in batches(view.grid):
    # Calculate Tile Positions
    x256 = (batch.tile.x0) shl 8
    y256 = (batch.tile.y0) shl 8
    x512 = x256 + 256
    y512 = y256 + 256
    # Upload Position
    map[cursor + 0] = (x256, y256, p0, p0)
    map[cursor + 1] = (x512, y256, p1, p0)
    map[cursor + 2] = (x256, y512, p0, p1)
    map[cursor + 3] = (x512, y512, p1, p1)
    # Guarante Tile Texture
    if batch.tile.texture == 0:
      batch.tile.texture = ctx.recycle()
    # Next Position
    cursor += 4
  # Unmap Buffers
  discard glUnmapBuffer(GL_ARRAY_BUFFER)
  glBindBuffer(GL_ARRAY_BUFFER, 0)

# ----------------------
# Canvas Render Commands
# ----------------------

proc update*(view: var NCanvasViewport) =
  # Cull Tiles
  view.grid.clear()
  # Recycle and Prepare Tiles
  view.grid.recycle()
  for tex in view.grid.garbage():
    view.renderer.recycle(tex)
  view.grid.prepare()
  # Locate Tiles Cache
  view.locatePositions()
  view.locateSamples()

proc active(idx, tex: GLuint) =
  glActiveTexture(GL_TEXTURE0 + idx)
  glBindTexture(GL_TEXTURE_2D, tex)

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
  for sample in samples(view.grid):
    # Bind Textures
    active(0, sample[0])
    active(1, sample[1])
    active(2, sample[2])
    active(3, sample[3])
    # Draw Texture Tile
    glDrawArrays(GL_TRIANGLE_STRIP, cursor, 4)
    # Next Vertex
    cursor += 4
  # Unbind Current State
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, 0)
  glBindVertexArray(0)
  glUseProgram(0)
