from math import log2
# Render 256x256 Tiles, One Draw Call Per Tile
# If you know a better way for OGL3.3, tell me
import ../libs/gl
import ../assets
import ../omath
# Extend Canvas
import canvas

type
  # -- Primitives
  NVertex {.packed.} = object
    x, y: float32
    u, v: uint16
  NViewTile = object
    x, y: int32
  # -- Tiled Canvas View
  NDirtyKind = enum
    drNone, drPartial, drComplete
  NCanvasView* = object
    # Shader Objects
    program: GLuint
    uPro, uModel: GLint
    # OpenGL Objects
    vao, vbo, pbo: GLuint
    # Viewport Uniforms
    width, height: int32
    mPro: array[16, float32]
    # Canvas Target Addr
    canvas: ptr NCanvas
    # Stride Size
    stride: int32
    # LOD & Sizes
    level: int32
    cw, ch: int32
    rw, rh: int32
    # Virtual Length
    cursor: int32
    # Textures and Vertexs
    tiles: seq[NViewTile]
    verts: seq[NVertex]
    texts: seq[GLuint]
    # Current Status
    dirty*: NDirtyKind
const # Vertex Layout Stride
  STRIDE_SIZE = # Casting
    sizeof(NVertex).int32
  BUFFER_SIZE = # PBO
    sizeof(NPixel) * 65536

# -------------------------
# CANVAS VIEW CREATION PROC
# -------------------------

proc newCanvasView*(): NCanvasView =
  result.program = # Compile Canvas Program
    newShader("canvas.vert", "canvas.frag")
  # -- Use Program for Define Uniforms
  glUseProgram(result.program)
  # Define Projection and Texture Uniforms
  result.uPro = glGetUniformLocation(result.program, "uPro")
  result.uModel = glGetUniformLocation(result.program, "uModel")
  # Set Default Uniform Value: Tile Texture
  glUniform1i glGetUniformLocation(result.program, "uTile"), 0
  # Unuse Program
  glUseProgram(0)
  # -- Generate Pixel Transfer PBO
  glGenBuffers(1, addr result.pbo)
  # Alloc Pixel Buffer Object
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, result.pbo)
  glBufferData(GL_PIXEL_UNPACK_BUFFER, 
    65536 * sizeof(NPixel), nil, GL_STREAM_DRAW)
  # Unbind Pixel Buffer Object
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0)
  # -- Generate Vertex Buffer
  glGenVertexArrays(1, addr result.vao)
  glGenBuffers(1, addr result.vbo)
  # Bind VAO and VBO
  glBindVertexArray(result.vao)
  glBindBuffer(GL_ARRAY_BUFFER, result.vbo)
  # Vertex Attribs XYVUV 12bytes
  glVertexAttribPointer(0, 2, cGL_FLOAT, false, 
    STRIDE_SIZE, cast[pointer](0)) # VERTEX
  glVertexAttribPointer(1, 2, GL_UNSIGNED_SHORT, true, 
    STRIDE_SIZE, cast[pointer](sizeof(float32)*2)) # UV
  # Enable Verter Attribs
  glEnableVertexAttribArray(0)
  glEnableVertexAttribArray(1)
  # Unbind VBO and VAO
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  glBindVertexArray(0)

# ------------------------------------
# CANVAS VIEW BASIC MANIPULATION PROCS
# ------------------------------------

proc target*(view: var NCanvasView, canvas: ptr NCanvas) =
  # Set New Canvas Target
  view.canvas = canvas
  # Set Canvas Stride
  view.stride = canvas.cw
  # Invalidate View Tiles
  view.dirty = drComplete

proc unit*(view: var NCanvasView, scale: float32) =
  var level = # Calculate Level of Detail
    int32(if scale < 1: -log2(scale) else: 0)
  # Set Level Of Detail
  view.level = level
  # Calculate X Y Residuals
  view.rw = (view.canvas.w shr level) and 0xff
  view.rh = (view.canvas.h shr level) and 0xff
  # LOD Grid Unit
  level = 8 + level
  # Calculate View Grid Sizes
  view.cw = view.canvas.w shr level
  view.ch = view.canvas.h shr level

proc residual*(view: var NCanvasView): tuple[w, h: bool] =
  result.w = view.rw > 0 # Residual W
  result.h = view.rh > 0 # Residual H

# Same as GUI, but is for other shader program
proc viewport*(view: var NCanvasView, w, h: int32) =
  # Use Canvas Program
  glUseProgram(view.program)
  # Change View Projection Matrix
  guiProjection(addr view.mPro, 
    float32 w, float32 h)
  # Upload View Projection Matrix
  glUniformMatrix4fv(view.uPro, 1, false,
    cast[ptr float32](addr view.mPro))
  # Unuse Canvas Program
  glUseProgram(0)
  # Save New Viewport Size
  view.width = w; view.height = h
  # Invalidate View Tiles
  view.dirty = drComplete

proc transform*(view: var NCanvasView, matrix: ptr float32) =
  # Use Canvas Program
  glUseProgram(view.program)
  # Upload View Transform Matrix
  glUniformMatrix3fv(view.uModel, 1, true, matrix)
  # Unuse Canvas Program
  glUseProgram(0)
  # Invalidate View Tiles
  view.dirty = drComplete

# ----------------------------
# CANVAS TILE ADDITION HELPERS
# ----------------------------

# Alloc New Texture Tile
proc alloc(view: var NCanvasView) =
  block: # Alloc New Texture
    var tex: GLuint
    glGenTextures(1, addr tex)
    # Redundant Bind But Safer
    glBindTexture(GL_TEXTURE_2D, tex)
    glTexImage2D(GL_TEXTURE_2D, 0, cast[GLint](GL_RGBA8), 
      256, 256, 0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
    # Set Mig/Mag Filter
    glTexParameteri(GL_TEXTURE_2D, 
      GL_TEXTURE_MIN_FILTER, cast[GLint](GL_LINEAR))
    glTexParameteri(GL_TEXTURE_2D, 
      GL_TEXTURE_MAG_FILTER, cast[GLint](GL_NEAREST))
    # Set UV Mapping Clamping
    glTexParameteri(GL_TEXTURE_2D, 
      GL_TEXTURE_WRAP_S, cast[GLint](GL_CLAMP_TO_EDGE))
    glTexParameteri(GL_TEXTURE_2D, 
      GL_TEXTURE_WRAP_T, cast[GLint](GL_CLAMP_TO_EDGE))
    # Unbind Texture
    glBindTexture(GL_TEXTURE_2D, 0)
    # Add New Texture
    view.texts.add(tex)
  # Alloc New Empty Vertex and Tile
  view.verts.setLen(view.verts.len + 4)
  view.tiles.setLen(view.tiles.len + 1)

# Canvas View Vertex Definition
proc vertex*(vp: var NVertex, x, y: float32, u, v: uint16) =
  # Set Position
  vp.x = x; vp.y = y
  # Set Texture Coordinates
  vp.u = u; vp.v = v

# Residual Copy to Current PBO
proc copy(src: NMap, s, x, y, w, h: int32) =
  # Map Buffer Without Syncronization
  let dst = cast[NMap](glMapBufferRange(
    GL_PIXEL_UNPACK_BUFFER, 0, BUFFER_SIZE, 
    GL_MAP_WRITE_BIT or GL_MAP_INVALIDATE_BUFFER_BIT))
  var i, si, di: int32
  # Row Copy Iterator
  si = y * s + x
  while i < h:
    # Copy Pixel Stride
    copyMem(addr dst[di], 
      addr src[si], sizeof(NPixel) * w)
    # Next Buffer Row
    si += s; di += 256; inc(i)
  # UnMap Pixel Buffer
  discard glUnmapBuffer(GL_PIXEL_UNPACK_BUFFER)

# ------------------------------
# CANVAS VIEW TILES MANIPULATION
# ------------------------------

proc clear*(view: var NCanvasView) {.inline.} =
  view.cursor = 0 # Clear Tiles

proc add*(view: var NCanvasView, x, y: int32) =
  if view.cursor == len(view.tiles):
    view.alloc() # Alloc New Tile
  block: # Set Tile Position
    let tile = # Lookup From Cursor
      addr view.tiles[view.cursor]
    tile.x = x; tile.y = y
  block: # Set Vertex Position
    let # Define Vertex Attribs
      idx = view.cursor shl 2
      # -- X Y Coordinates
      x1 = float32(x shl 8)
      x2 = x1 + 256
      y1 = float32(y shl 8)
      y2 = y1 + 256
      # -- U V Coordinates
      u = # U Coordinate
        if x == view.cw:
          uint16(view.rw shl 8)
        else: high uint16
      v = # V Coordinate
        if y == view.ch:
          uint16(view.rh shl 8)
        else: high uint16
    # Define Tile Vertexs
    vertex(view.verts[idx], x1, y1, 0, 0)
    vertex(view.verts[idx + 1], x2, y1, u, 0)
    vertex(view.verts[idx + 2], x1, y2, 0, v)
    vertex(view.verts[idx + 3], x2, y2, u, v)
  # Next Tile Position
  inc(view.cursor)

# TODO: Level of Detail from Canvas
proc copy*(view: var NCanvasView) =
  # Bind Array Buffer First
  glBindBuffer(GL_ARRAY_BUFFER, view.vbo)
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, view.pbo)
  # TODO: Level of Detail
  let src = cast[NMap](
    addr view.canvas.buffer[0])
  var # Copy Each Tile Texture
    w, h, i: int32
    tile: ptr NViewTile
  while i < view.cursor:
    glBindBuffer( # Bind Current PBO
      GL_PIXEL_UNPACK_BUFFER, view.pbo)
    # Bind Current Tile
    tile = addr view.tiles[i]
    glBindTexture(GL_TEXTURE_2D, view.texts[i])
    # Check X Residual
    if tile.x == view.cw:
      w = view.rw
    else: w = 256
    # Check Y Residual
    if tile.y == view.ch:
      h = view.rh
    else: h = 256
    # Copy Canvas Tile to Texture
    copy(src, view.stride,
      tile.x shl 8, tile.y shl 8, w, h)
    glTexSubImage2D(
      GL_TEXTURE_2D, 0, 0, 0, 
      256, 256, GL_RGBA, 
      GL_UNSIGNED_BYTE, nil)
    inc(i) # Next Tile
  # Copy Tile Vertex Buffer
  glBufferData(GL_ARRAY_BUFFER, 
    sizeof(NVertex) * view.cursor * 4, 
    addr view.verts[0], GL_STREAM_DRAW)
  # Unbind Texture, PBO, and VBO
  glBindTexture(GL_TEXTURE_2D, 0)
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0)
  glBindBuffer(GL_ARRAY_BUFFER, 0)

# ---------------------
# CANVAS VIEW RENDERING
# ---------------------

proc render*(view: var NCanvasView) =
  glUseProgram(view.program)
  glBindVertexArray(view.vao)
  # Draw Each Tile
  var i, j: int32
  while i < view.cursor:
    # Bind Texture and Draw Tile Quad
    glBindTexture(GL_TEXTURE_2D, view.texts[i])
    glDrawArrays(GL_TRIANGLE_STRIP, j, 4)
    # Next Tile
    j += 4; inc(i)
  # Unbind Current State
  glBindTexture(GL_TEXTURE_2D, 0)
  glBindVertexArray(0)
  glUseProgram(0)
