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
  NCanvasDirty* = tuple[x, y, w, h: cint]
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

# Calculate Dirty Boundaries
func bounds*(tile: ptr NCanvasTile): NCanvasDirty =
  let
    dirty = tile.dirty
    d0 = unpack(dirty)
    d1 = unpack(dirty shr 16)
  # Calculate Position
  result.x = d0.x shl 1
  result.y = d0.y shl 1
  # Calculate Dimensions
  result.w = (d1.x shl 1) - result.x
  result.h = (d1.y shl 1) - result.y

func invalid*(tile: ptr NCanvasTile): bool =
  let
    dirty = tile.dirty
    d0 = dirty and 0xFFFF
    d1 = dirty shr 16
  # Check Same Positions
  d0 != d1

# Define Dirty Boundaries
func dirty0(tile: ptr NCanvasTile, x, y: cint) =
  let
    dirty = tile.dirty
    prev = unpack(dirty)
  var 
    mx = x shr 1
    my = y shr 1
  if prev.x < 128 and prev.y < 128:
    mx = min(mx, prev.x)
    my = min(my, prev.y)
  # Change Dirty Positions
  let pos = pack(mx, my)
  const mask = 0xFFFF0000'u32
  tile.dirty = (dirty and mask) or pos

func dirty1(tile: ptr NCanvasTile, x, y: cint) =
  let
    dirty = tile.dirty
    prev = unpack(dirty shr 16)
  var
    mx = (x + 1) shr 1
    my = (y + 1) shr 1
  if prev.x < 128 and prev.y < 128:
    mx = max(mx, prev.x)
    my = max(my, prev.y)
  # Change Dirty Positions
  let pos = pack(mx, my)
  const mask = 0xFFFF'u32
  tile.dirty = (dirty and mask) or pos

# -------------------------
# Canvas Viewport Tile Uses
# -------------------------

proc clear*(view: var NCanvasViewport) =
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

proc lookup(view: var NCanvasViewport; x, y: cint): ptr NCanvasTile =
  let 
    grid = view.grid
    # Tiled Position
    tx = x shr 8
    ty = y shr 8
    tw = view.w
  # Return Located Tile
  addr grid[ty * tw + tx]

proc activate*(view: var NCanvasViewport; x, y: cint) =
  # Find Tile Position
  let tile = view.lookup(x, y)
  const mask = 0x80800000u32
  # Mark it as Dirty
  if tile.texture == 0:
    tile.dirty = mask

proc prepare*(view: var NCanvasViewport) =
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
        else: ctx.recycle(tex)
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
        tex = ctx.recycle()
      if tex > 0:
        cache[count] = tex
        inc(count)
      # Next Tile
      inc(idx)
    # Set New Count
    view.count = count

# ------------------------
# Canvas Render Tile Dirty
# ------------------------

proc mark*(view: var NCanvasViewport; region: NCanvasDirty; x, y: cint) =
  let tile = view.lookup(x, y)
  # Check if Tile is added
  if tile.texture > 0:
    let
      ox0 = x and not 0xFF
      oy0 = y and not 0xFF
      ox1 = ox0 + 256
      oy1 = oy0 + 256
      # Clamp Region Area
      cx0 = clamp(region.x, ox0, ox1)
      cy0 = clamp(region.y, oy0, oy1)
      cx1 = clamp(region.x + region.w, ox0, ox1)
      cy1 = clamp(region.y + region.h, oy0, oy1)
    # Mark as Dirty
    tile.dirty0(cx0, cy0)
    tile.dirty1(cx1, cy1)

proc mark32*(view: var NCanvasViewport, x, y: cint) =
  let tile = view.lookup(x, y)
  # Check if Tile is added
  if tile.texture > 0:
    let
      tx = x and not 0xFF
      ty = y and not 0xFF
      # Dirty Positions
      x0 = (x and not 0x1F) - tx
      y0 = (y and not 0x1F) - ty
      x1 = x0 + 32
      y1 = y0 + 32
    # Mark as Dirty
    tile.dirty0(x0, y0)
    tile.dirty1(x1, y1)

# --------------------------
# Canvas Render Tile Mapping
# --------------------------

proc map*(view: var NCanvasViewport; x, y: cint): NCanvasTileMap =
  # Define Tile Map
  let
    ctx = view.renderer
    tile = view.lookup(x, y)
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
    tile.dirty = high(GLuint)
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
