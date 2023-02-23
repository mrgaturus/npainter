# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
import ../../libs/gl
import ../../assets
import matrix

type
  NCanvasVertex {.pure.} = object
    x, y, u, v: cushort
  NCanvasTile = object
    texture, dirty: GLuint
  NCanvasTileMap = ref object
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
    pbo: GLuint
    bytes: GLint
    mappers: seq[NCanvasTileMap]
  # Canvas Viewport Objects
  NCanvasBuffer = ref UncheckedArray[byte]
  NCanvasGrid = ptr UncheckedArray[NCanvasTile]
  NCanvasCache = ptr UncheckedArray[GLuint]
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
    grid: NCanvasGrid
    cache: NCanvasCache

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
    result.cache = cast[NCanvasCache](addr result.buffer[chunk])
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
# Canvas Render Tile Usables
# --------------------------

proc useTile(ctx: ptr NCanvasRenderer): GLuint =
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

proc recycleTile(ctx: ptr NCanvasRenderer, tile: GLuint) {.inline.} =
  # Add New Tile to Usables
  ctx.usables.add(tile)

# ------------------------
# Canvas Render Dirty Tile
# ------------------------

func unpack(dirty: GLuint): tuple[x, y: cint] {.inline.} =
  result.x = cast[cint](dirty and 0xFF)
  result.y = cast[cint](dirty shr 8 and 0xFF)

func pack(x, y: cint): GLuint {.inline.} =
  let 
    xx = cast[GLuint](x and 0xFF)
    yy = cast[GLuint](y and 0xFF) shl 8
  result = xx or yy

func invalid(tile: ptr NCanvasTile): bool {.inline.} =
  tile.dirty == high(GLuint)

# Define Dirty Positions
func dirty0(tile: ptr NCanvasTile, x, y: cint) =
  let 
    dirty = tile.dirty
    pos = pack(x, y)
  tile.dirty = (dirty shl 16) or pos

func dirty1(tile: ptr NCanvasTile, x, y: cint) =
  let 
    dirty = tile.dirty
    pos = pack(x, y) shl 16
  tile.dirty = (dirty shr 16) or pos

# Define Dirty Boundaries
func bounds(tile: ptr NCanvasTile): tuple[x, y, w, h: cint] =
  if tile.invalid:
    # Type infer is very bad
    return (0'i32, 0'i32, 256'i32, 256'i32)
  let
    d0 = unpack(tile.dirty)
    d1 = unpack(tile.dirty shr 16)
    # Calculate Minimun Positions
    x0 = min(d0.x, d1.x)
    y0 = min(d0.y, d1.y)
    x1 = max(d0.x, d1.x)
    y1 = max(d0.y, d1.y)
  result = (x0, y0, x1 - x0, y1 - y0)

# -------------------------
# Canvas Viewport Tile Uses
# -------------------------

proc swapTiles*(view: var NCanvasViewport) =
  let 
    l = view.w * view.h
    cache = cast[NCanvasCache](view.grid)
    grid = cast[NCanvasGrid](view.cache)
  # Swap Grid and Cache
  view.grid = grid
  view.cache = cache
  # Clear Grid
  zeroMem(grid, l * NCanvasTile.sizeof)
  # Reset Cache Counter
  view.count = 0

proc locateTile(view: var NCanvasViewport; x, y: cint): ptr NCanvasTile =
  let 
    grid = view.grid
    w = view.w
  addr grid[y * w + x]

proc cacheTiles*(view: var NCanvasViewport) =
  let
    cache = view.cache
    grid = view.grid
    l = view.w * view.h
    # Previous Tile Grid
    ctx = view.renderer
    prev = cast[NCanvasGrid](cache)
  var 
    tex: GLuint
    tile: ptr NCanvasTile
  # Check if is already cached
  if view.count > 0: return
  # Reuse/Unuse Tiles
  block: 
    var idx: cint
    # Iterate Each Tile
    while idx < l:
      tile = addr grid[idx]
      tex = prev[idx].texture
      if tex > 0:
        if tile.invalid:
          tile.texture = tex
        else: ctx.recycleTile(tex)
      # Next Tile
      inc(idx)
  # Create Cache List
  block: 
    var idx, count: cint
    # Iterate Each Tile
    while idx < l:
      tile = addr grid[idx]
      tex = tile.texture
      if tex == 0 and tile.invalid:
        tex = ctx.useTile()
      if tex > 0:
        cache[count] = tex
        inc(count)
      # Next Tile
      inc(idx)
    # Set New Count
    view.count = count

# --------------------------
# Canvas Render Tile Mapping
# --------------------------

proc map*(view: var NCanvasViewport; x, y: cint): NCanvasTileMap =
  # Define Tile Map
  let
    ctx = view.renderer
    tile = view.locateTile(x, y)
    # Tile Regions
    region = tile.bounds()
    offset = ctx.bytes
    # Tile Buffer Copy Size
    bytes = region.w * region.h * 4
  # Allocate Tile Map
  new result
  # Define Dirty Region
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
  for m in ctx.mappers:
    m.chunk = glMapBufferRange(
      GL_PIXEL_UNPACK_BUFFER, m.offset, m.bytes, 
      GL_MAP_WRITE_BIT or GL_MAP_UNSYNCHRONIZED_BIT)

proc unmap*(ctx: var NCanvasRenderer) =
  # Close Buffer Map
  discard glUnmapBuffer(GL_PIXEL_UNPACK_BUFFER)
  # Upload Each Texture
  for m in ctx.mappers:
    let
      tile = m.tile
      r = tile.bounds()
      offset = cast[pointer](m.offset)
    # Upload Texture
    glBindTexture(GL_TEXTURE_2D, tile.texture)
    glTexSubImage2D(GL_TEXTURE_2D, 0, 
      r.x, r.y, r.w, r.h, GL_RGBA, GL_UNSIGNED_BYTE, offset)
    # Remove Dirty Region
    tile.dirty = 0
  # UnBind Buffers
  glBindTexture(GL_TEXTURE_2D, 0)
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0)
  # Clear Mappers
  newSeq(ctx.mappers, 0)
  ctx.bytes = 0

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
    glBindTexture(GL_TEXTURE_2D, view.cache[cursor])
    glDrawArrays(GL_TRIANGLE_STRIP, cursor shl 2, 4)
    # Next Tile
    inc(cursor)
  # Unbind Current State
  glBindTexture(GL_TEXTURE_2D, 0)
  glBindVertexArray(0)
  glUseProgram(0)
