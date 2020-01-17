import ../libs/gl

const
  BATCH_SIZE = 1024 * 1024 # 1MB/1024KB
  FILL_SIZE = 8 * sizeof(float32)
  RECT_SIZE = 26 * sizeof(float32)

type
  # GUI RECT AND COLOR
  GUIRect* = object
    x*, y*, w*, h*: int32
  GUIColor* = object
    r*, g*, b*, a*: float32
  # Buffer Mapping
  CTXBufferMap* = 
    ptr UncheckedArray[float32]
  # GUI Painter
  CTXLevel = object
    rect: GUIRect
    color: GUIColor
  CTXCanvas* = object
    # Color Uniform
    pro, color: GLint
    # Solid/Atlas VAOs
    vao0, vao1: GLuint
    # Buffer/White Pixel
    vbo, white: GLuint
    # Viewport Height
    height: int32
    # Clipping and Color levels
    levels: seq[CTXLevel]

# -------------------------
# GUI CANVAS CREATION PROCS
# -------------------------

proc newCTXCanvas*(uPro, uCol: GLint): CTXCanvas =
  # -- Projection and Color Uniform
  result.pro = uPro
  result.color = uCol
  # -- Gen VAOs and Batch VBO
  glGenVertexArrays(2, addr result.vao0)
  glGenBuffers(1, addr result.vbo)
  # Bind Batch VBO and alloc fixed size
  glBindBuffer(GL_ARRAY_BUFFER, result.vbo)
  glBufferData(GL_ARRAY_BUFFER, BATCH_SIZE, nil, GL_STREAM_DRAW)
  # 1- Solid VAO
  glBindVertexArray(result.vao0)
  glVertexAttribPointer(0, 2, cGL_FLOAT, false, 0, cast[
    pointer](0))
  glEnableVertexAttribArray(0)
  # 2- Atlas VAO
  glBindVertexArray(result.vao1)
  glVertexAttribPointer(0, 2, cGL_FLOAT, false, sizeof(float32)*4, cast[
    pointer](0))
  glVertexAttribPointer(0, 2, cGL_FLOAT, false, sizeof(float32)*4, cast[
    pointer](sizeof(float32)*2))
  glEnableVertexAttribArray(0)
  glEnableVertexAttribArray(1)
  # Unbind VAO and VBO
  glBindVertexArray(0)
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  # -- Gen White Pixel Texture
  glGenTextures(1, addr result.white)
  glBindTexture(GL_TEXTURE_2D, result.white)
  # Clamp white pixel to edge
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, cast[GLint](GL_CLAMP_TO_EDGE))
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, cast[GLint](GL_CLAMP_TO_EDGE))
  # Use Nearest Pixel
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, cast[GLint](GL_NEAREST))
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, cast[GLint](GL_NEAREST))
  # Alloc White Pixel
  block:
    var white = 0xFFFFFFFF'u32
    glTexImage2D(GL_TEXTURE_2D, 0, cast[int32](GL_RGBA8), 1, 1, 0, GL_RGBA,
        GL_UNSIGNED_BYTE, addr white)
  # Unbind White Pixel Texture
  glBindTexture(GL_TEXTURE_2D, 0)

# --------------------------
# GUI RENDER PREPARING PROCS
# --------------------------

proc viewport*(ctx: var CTXCanvas, w, h: int32, pro: ptr float32) =
  glViewport(0, 0, w, h)
  glUniformMatrix4fv(ctx.pro, 1, false, pro)
  # Set new height
  ctx.height = h

proc makeCurrent*(ctx: var CTXCanvas) =
  # Clear levels
  ctx.levels.setLen(0)
  # Disable Scissor Test
  glDisable(GL_SCISSOR_TEST)
  # Bind Batch VAO and White Pixel
  glBindVertexArray(ctx.vao0)
  glBindBuffer(GL_ARRAY_BUFFER, ctx.vbo)
  glBindTexture(GL_TEXTURE_2D, ctx.white)
  # Set Default Color (Black)
  glClearColor(0.0, 0.0, 0.0, 1.0)
  glUniform4f(cast[GLint](ctx.color), 0.0, 0.0, 0.0, 1.0)

proc clearCurrent*(ctx: var CTXCanvas) =
  # Disable Scissor Test
  glDisable(GL_SCISSOR_TEST)
  # Unbinf VAO and VBO
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  glBindVertexArray(0)
  # Set To White Pixel
  glUniform4f(cast[GLint](ctx.color), 1.0, 1.0, 1.0, 1.0)

# ------------------------
# GUI PAINTER HELPER PROCS
# ------------------------

proc intersect(ctx: ptr CTXCanvas, rect: var GUIRect): GUIRect =
  let
    prev = addr ctx.levels[^1].rect
    x1 = clamp(rect.x, prev.x, prev.x + prev.w)
    y1 = clamp(rect.y, prev.y, prev.y + prev.h)
    x2 = clamp(prev.x + prev.w, rect.x, rect.x + rect.w)
    y2 = clamp(prev.y + prev.h, rect.y, rect.y + rect.h)
  result.x = x1
  result.y = y1
  result.w = abs(x2 - x1)
  result.h = abs(y2 - y1)

# -----------------------
# GUI CLIP/COLOR PROCS
# -----------------------

proc clip*(ctx: ptr CTXCanvas, rect: var GUIRect) =
  if ctx.levels.len > 0:
    let nclip = ctx.intersect(rect)
    glScissor(nclip.x, ctx.height - nclip.y - nclip.h, nclip.w, nclip.h)
  else:
    glEnable(GL_SCISSOR_TEST)
    glScissor(rect.x, ctx.height - rect.y - rect.h, rect.w, rect.h)

proc color*(ctx: ptr CTXCanvas, color: var GUIColor) =
  glClearColor(color.r, color.g, color.b, color.a)
  glUniform4f(cast[GLint](ctx.color),
    color.r, color.g, color.b, color.a
  )

proc clear*(ctx: ptr CTXCanvas) {.inline.} =
  glClear(GL_COLOR_BUFFER_BIT)

proc reset*(ctx: ptr CTXCanvas) =
  if ctx.levels.len > 0:
    let level = addr ctx.levels[^1]
    block: # Reset Scissor
      let rect = addr level.rect
      glEnable(GL_SCISSOR_TEST)
      glScissor(rect.x, ctx.height - rect.y - rect.h, rect.w, rect.h)
    block: # Reset Color
      let color = addr level.color
      glClearColor(color.r, color.g, color.b, color.a)
      glUniform4fv(
        cast[GLint](ctx.color), 1,
        cast[ptr float32](color)
      )
  else:
    glDisable(GL_SCISSOR_TEST)
    glClearColor(0.0, 0.0, 0.0, 1.0)
    glUniform4f(cast[GLint](ctx.color), 0.0, 0.0, 0.0, 1.0)

# -----------------------
# GUI CLIP/COLOR LEVELS PROCS
# -----------------------

proc push*(ctx: ptr CTXCanvas, rect: var GUIRect, color: var GUIColor) =
  var level: CTXLevel
  # Copy Color
  level.color = color
  # Get Frame Intersection
  if ctx.levels.len > 0:
    level.rect = ctx.intersect(rect)
  else:
    level.rect = rect
  # Add Level and Reset
  ctx.levels.add(level)
  ctx.reset()

proc pop*(ctx: ptr CTXCanvas) =
  ctx.levels.setLen(ctx.levels.len - 1)
  ctx.reset()

# --------------
# GUI BASIC DRAW PROCS
# --------------

proc fill*(ctx: ptr CTXCanvas, rect: var GUIRect) =
  let
    x = float32 rect.x
    y = float32 rect.y
    xw = x + float32 rect.w
    yh = y + float32 rect.h
    map = cast[CTXBufferMap](glMapBufferRange(
      GL_ARRAY_BUFFER, 0, FILL_SIZE, GL_MAP_WRITE_BIT
    ))
  # Put Rect Coords
  map[0] = x; map[1] = y
  map[2] = xw; map[3] = y
  map[4] = x; map[5] = yh
  map[6] = xw; map[7] = yh
  # Unmap Coords
  discard glUnmapBuffer(GL_ARRAY_BUFFER)
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

proc rectangle*(ctx: ptr CTXCanvas, rect: var GUIRect, b: float32) =
  let
    x = float32 rect.x
    y = float32 rect.y
    xw = x + float32 rect.w
    yh = y + float32 rect.h
    map = cast[CTXBufferMap](glMapBufferRange(
      GL_ARRAY_BUFFER, 0, RECT_SIZE, GL_MAP_WRITE_BIT
    ))
  # UPPER Line
  map[0] = x; map[1] = y
  map[2] = x; map[3] = y + b
  map[4] = xw; map[5] = y
  map[6] = xw; map[7] = y + b
  # RIGHT Line
  map[8] = xw - b; map[9] = y + b
  map[10] = xw; map[11] = yh
  map[12] = xw - b; map[13] = yh
  # BOTTOM Line
  map[14] = xw - b; map[15] = yh - b
  map[16] = x; map[17] = yh
  map[18] = x; map[19] = yh - b
  # LEFT Line
  map[20] = x + b; map[21] = yh - b
  map[22] = x; map[23] = y + b
  map[24] = x + b; map[25] = y + b
  # Unmap Coords
  discard glUnmapBuffer(GL_ARRAY_BUFFER)
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 13)