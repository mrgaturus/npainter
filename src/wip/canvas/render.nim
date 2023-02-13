# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
import ../../libs/gl
import ../../assets
import ../../omath

type
  NCanvasMatrix* = array[9, cfloat]
  NCanvasProjection = array[16, cfloat]
  NCanvasVertex {.pure.} = object
    x, y, u, v: cushort
  # Canvas Renderer
  NCanvasTile = object
    x, y: cushort
    texture: GLuint
  NCanvasRenderer* = object
    # OpenGL Objects
    program: GLuint
    uPro, uModel: GLint
    vao, vbo, pbo: GLuint
    # Canvas Tiles
    tiles: seq[NCanvasTile]
    uses: seq[ptr cint]
  # Canvas Viewport
  NCanvasGrid = UncheckedArray[cint]
  NCanvasViewport* = object
    renderer: ptr NCanvasRenderer
    # Canvas Projection & Transform
    projection: NCanvasProjection
    model*: NCanvasMatrix
    # Grid Parameters
    w, h, lod, count: cint
    # Grid Buffers
    buffer: ref NCanvasGrid
    tiles: ptr NCanvasGrid
    grid: ptr NCanvasGrid

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
  block: # -- Generate Vertex Buffers
    glGenBuffers(1, addr result.pbo)
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

# -------------------------------
# Canvas Render Viewport Creation
# -------------------------------

proc createViewport*(ctx: var NCanvasRenderer; w, h: cint): NCanvasViewport =
  result.w = w
  result.h = h
  let l = w * h
  # Allocate Viewport Locations
  unsafeNew(result.buffer, l * 2)
  zeroMem(addr result.buffer[0], l * 2)
  # Configure Grid Pointers
  result.tiles = cast[ptr NCanvasGrid](addr result.buffer[0])
  result.grid = cast[ptr NCanvasGrid](addr result.buffer[l])
  # Canvas Renderer
  result.renderer = addr ctx

proc projection*(view: var NCanvasViewport, w, h: cint) =
  # Change View Projection Matrix
  guiProjection(addr view.projection, 
    cfloat w, cfloat h)

# -------------------------
# Canvas Render Grid Lookup
# -------------------------

template `[]`(grid: ptr NCanvasGrid, x, y: cint): cint =
  grid[view.w * y + x] - 1

template `[]=`(grid: ptr NCanvasGrid, x, y, value: cint) =
  grid[view.w * y + x] = value + 1

template clear(grid: ptr NCanvasGrid, x, y: cint) =
  grid[view.w * y + x] = 0

# --------------------------
# Canvas Render Tile Manager
# --------------------------

proc createTile(ctx: ptr NCanvasRenderer): cint =
  var tile: NCanvasTile
  glGenTextures(1, addr tile.texture)
  # Redundant Bind But Safer
  glBindTexture(GL_TEXTURE_2D, tile.texture)
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
  ctx.tiles.add(tile)
  result = cint high(ctx.tiles)

proc createTile(view: var NCanvasViewport, x, y: cint) =
  let ctx = view.renderer
  var index: cint
  # Check if New Tile is Needed
  if ctx.uses.len == ctx.tiles.len:
    index = ctx.createTile()
  else: index = len(ctx.uses).cint
  # Locate Current Tile
  view.grid[x, y] = index

proc removeTile(view: var NCanvasViewport, x, y: cint) =
  let ctx = view.renderer
  var index = view.grid[x, y]
  # Check if There is Tile
  if index > 0:
    swap(ctx.tiles[^1], ctx.tiles[index])
    swap(ctx.uses[^1], ctx.uses[index])
    ctx.tiles.setLen(ctx.tiles.len - 1)
    ctx.uses.setLen(ctx.uses.len - 1)
    # Change Use Index Pointer
    ctx.uses[index][] = index
    view.grid.clear(x, y)

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
    cast[ptr cfloat](addr view.projection))
  # Upload View Transform Matrix
  glUniformMatrix3fv(ctx.uModel, 1, true,
    cast[ptr cfloat](addr view.model))
  # Render Each View Texture
  glBindVertexArray(ctx.vao)
  # Draw Each Tile
  var cursor: cint; while cursor < view.count:
    # Bind Texture and Draw Tile Quad
    glBindTexture(GL_TEXTURE_2D, ctx.tiles[cursor].texture)
    glDrawArrays(GL_TRIANGLE_STRIP, cursor shl 2, 4)
    # Next Tile
    inc(cursor)
  # Unbind Current State
  glBindTexture(GL_TEXTURE_2D, 0)
  glBindVertexArray(0)
  glUseProgram(0)
