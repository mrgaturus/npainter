# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
import ../../libs/gl
import ../../assets
import matrix, culling, grid
export NCanvasDirty

type
  NCanvasVertex = tuple[x, y, u, v: cushort]
  NCanvasPBOBuffer = ptr UncheckedArray[byte]
  NCanvasPBOMap* = ref object
    tile: ptr NCanvasTile
    x256*, y256*: cint
    # Chunk Mapping
    offset, bytes*: GLint
    chunk*: pointer
  NCanvasRenderer* = object
    # OpenGL Objects
    program: array[2, GLuint]
    dummy, pbo: GLuint
    # OpenGL Textures
    usables: seq[GLuint]
    # OpenGL Mappers
    bytes: GLint
    mappers: seq[NCanvasPBOMap]
  # Canvas Viewport
  NCanvasViewport* = object
    renderer*: ptr NCanvasRenderer
    affine*: NCanvasAffine
    cull: NCanvasCulling
    # Canvas Image Size
    w, h: cint
    # Tile Geometry
    vao, vbo, ubo: GLuint
    grid: NCanvasGrid

# ------------------------
# Canvas Renderer Creation
# ------------------------

proc createCanvasShader(frag: string): GLuint =
  result = newShader("canvas.vert", frag)
  glUseProgram(result)
  # Configure UBO Block
  let 
    index0 = glGetUniformBlockIndex(result, "AffineBlock")
    index1 = glGetUniformBlockIndex(result, "ScaleBlock")
  glUniformBlockBinding(result, index0, 0)
  glUniformBlockBinding(result, index1, 0)
  # Configure Each Texture Blocks
  glUniform1i glGetUniformLocation(result, "uTile0"), 0
  glUniform1i glGetUniformLocation(result, "uTile1"), 1
  glUniform1i glGetUniformLocation(result, "uTile2"), 2
  glUniform1i glGetUniformLocation(result, "uTile3"), 3
  # Unuse Program
  glUseProgram(0)

proc createCanvasRenderer*(): NCanvasRenderer =
  block: # Create Downscaling and Upscaling Programs
    result.program[0] = createCanvasShader("canvas0.frag")
    result.program[1] = createCanvasShader("canvas1.frag")
  block: # Create Dummy Texture
    glGenBuffers(1, addr result.pbo)
    glGenTextures(1, addr result.dummy)
    glBindTexture(GL_TEXTURE_2D, result.dummy)
    # Upload Just One Pixel
    var pixel: cuint = 0
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8.int32, 
      1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, 
      cast[pointer](addr pixel))
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
    glGenerateMipmap(GL_TEXTURE_2D)
    glBindTexture(GL_TEXTURE_2D, 0)

proc createCanvasViewport*(ctx: var NCanvasRenderer; w, h: cint): NCanvasViewport =
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
  block: # Configure UBO
    glGenBuffers(1, addr result.ubo)
    glBindBuffer(GL_UNIFORM_BUFFER, result.ubo)
    glBufferData(GL_UNIFORM_BUFFER, 128, nil, GL_DYNAMIC_DRAW)
    glBindBuffer(GL_UNIFORM_BUFFER, 0)
  block: # Create Canvas Grid
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
    x256 = cast[cushort](batch.tile.x0) shl 8
    y256 = cast[cushort](batch.tile.y0) shl 8
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

# --------------------------
# Canvas Render Tile Mapping
# --------------------------

proc map*(view: var NCanvasViewport; invalid: ptr NCanvasTile): NCanvasPBOMap =
  let 
    ctx = view.renderer
    offset = ctx.bytes
  const bytes = 256 * 256 * 4
  # Allocate Tile Map
  new result
  # Define Dirty Region
  result.tile = invalid
  result.offset = offset
  result.bytes = bytes
  # Check Really Invalid
  assert invalid.invalid, "tile not invalid"
  result.x256 = cast[cint](invalid.x0)
  result.y256 = cast[cint](invalid.y0)
  # Dirty All Tile
  invalid.whole()
  # Add Dirty Region to Mappers
  ctx.mappers.add(result)
  ctx.bytes += bytes

proc map*(view: var NCanvasViewport; x256, y256: cint): NCanvasPBOMap =
  # Define Tile Map
  let
    ctx = view.renderer
    tile = view.grid.lookup(x256, y256)
    # Tile Regions
    region = tile.region()
    offset = ctx.bytes
    # Tile Buffer Copy Size
    bytes = region.w * region.h * 4
  # Allocate Tile Map
  new result
  # Define Dirty Position
  result.x256 = x256
  result.y256 = y256
  # Define Dirty Chunk
  result.tile = tile
  result.offset = offset
  result.bytes = bytes
  # Add Dirty Region to Mappers
  ctx.mappers.add(result)
  ctx.bytes += bytes

proc map*(ctx: var NCanvasRenderer) =
  let bytes = ctx.bytes
  # Create New PBO, And Map Each Segment
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, ctx.pbo)
  glBufferData(GL_PIXEL_UNPACK_BUFFER, bytes, nil, GL_STREAM_COPY)
  var chunk = cast[NCanvasPBOBuffer](
    glMapBufferRange(GL_PIXEL_UNPACK_BUFFER, 0, bytes,
    GL_MAP_WRITE_BIT or GL_MAP_UNSYNCHRONIZED_BIT))
  for m in ctx.mappers:
    m.chunk = addr chunk[m.offset]

proc unmap*(ctx: var NCanvasRenderer) =
  # Close Buffer Map
  discard glUnmapBuffer(GL_PIXEL_UNPACK_BUFFER)
  # Upload Each Texture
  for m in ctx.mappers:
    let
      tile = m.tile
      r = tile.region()
      offset = cast[pointer](m.offset)
    # Upload Texture
    glBindTexture(GL_TEXTURE_2D, tile.texture)
    glTexSubImage2D(GL_TEXTURE_2D, 0, 
      r.x, r.y, r.w, r.h, GL_RGBA, GL_UNSIGNED_BYTE, offset)
    # Remove Dirty Region
    tile.clean()
  # UnBind Buffers
  glBindTexture(GL_TEXTURE_2D, 0)
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0)
  # Clear Mappers
  newSeq(ctx.mappers, 0)
  ctx.bytes = 0

# -----------------------
# Canvas Viewport Helpers
# -----------------------

iterator tiles*(view: var NCanvasViewport): ptr NCanvasTile =
  for tile in view.grid.tiles: yield tile

template mark32*(view: var NCanvasViewport; x32, y32: cint) =
  view.grid.mark32(x32, y32)

template mark*(view: var NCanvasViewport; dirty: NCanvasDirty) =
  view.grid.mark(dirty)

template region*(pbo: NCanvasPBOMap): NCanvasDirty =
  pbo.tile.region()

# ----------------------
# Canvas Render Commands
# ----------------------

proc transform(view: var NCanvasViewport) =
  let affine = addr view.affine
  # Calculate Matrices
  affine[].calculate()
  # Copy Matrices as std140 said
  glBindBuffer(GL_UNIFORM_BUFFER, view.ubo)
  let ubo = cast[ptr UncheckedArray[byte]](
    glMapBuffer(GL_UNIFORM_BUFFER, GL_WRITE_ONLY))
  copyMem(addr ubo[0], addr affine.zoom, 4)
  copyMem(addr ubo[16], addr affine.model1[0], 12)
  copyMem(addr ubo[32], addr affine.model1[3], 12)
  copyMem(addr ubo[48], addr affine.model1[6], 12)
  copyMem(addr ubo[64], addr affine.projection[0], 64)
  discard glUnmapBuffer(GL_UNIFORM_BUFFER)
  glBindBuffer(GL_UNIFORM_BUFFER, 0)

proc update*(view: var NCanvasViewport) =
  let ctx = view.renderer
  # Update Affine and Grid
  view.transform()
  view.grid.clear()
  # Apply Grid Culling
  prepare(view.cull, view.affine)
  assemble(view.grid, view.cull)
  # Recycle and Prepare Tiles
  view.grid.recycle()
  for tex in view.grid.garbage():
    ctx.recycle(tex)
  view.grid.prepare()
  # Locate Tiles Cache
  view.locatePositions()
  view.locateSamples()

proc active(idx, tex: GLuint) =
  glActiveTexture(GL_TEXTURE0 + idx)
  glBindTexture(GL_TEXTURE_2D, tex)

proc render*(view: var NCanvasViewport) =
  var cursor: cint
  let ctx = view.renderer
  # Bind Program and VAO
  glUseProgram(ctx.program[1])
  glBindVertexArray(view.vao)
  glBindBufferBase(GL_UNIFORM_BUFFER, 0, view.ubo)
  # Render Each Tile
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
  # Unbind Texture
  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, 0)
  # Unbind Uniform Buffers
  glBindVertexArray(0)
  glUseProgram(0)
