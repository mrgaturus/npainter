from ../shader import newProgram
import ../libs/gl

const
  maxSize = 4096 * sizeof(float32)*2 #32KB
  rectSize = 8 * sizeof(float32)

type
  # GUI PIVOT, RECT AND COLOR
  GUIPivot* = object
    x*, y*: int32
  GUIRect* = object
    x*, y*, w*, h*: int32
  GUIColor* = object
    r*, g*, b*, a*: float32
  # GUI Painter
  CTXLevel = object
    rect: GUIRect
    color: GUIColor
  CTXRender* = object
    # GUI Program
    program: GLuint
    # Color Uniform
    pro, color: GLint
    # White Pixel and Stream Size
    white, vao, vbo: GLuint
    # Viewport Height
    height: int32
    # Clipping and Color levels
    levels: seq[CTXLevel]

# --------
# GUI CREATION PROCS
# --------

proc newCTXRender*(): CTXRender =
  # -- Create new program
  result.program = newProgram("shaders/gui.vert", "shaders/gui.frag")
  # Use Program
  glUseProgram(result.program)
  # Load uniforms
  result.pro = glGetUniformLocation(result.program, "uPro")
  result.color = glGetUniformLocation(result.program, "uCol")
  glUniform1i(glGetUniformLocation(result.program, "uTex"), 0)
  # Unuse Program
  glUseProgram(0)
  # -- Gen Batch VAO and VBO
  glGenVertexArrays(1, addr result.vao)
  glGenBuffers(1, addr result.vbo)
  # Bind VAO and VBO
  glBindVertexArray(result.vao)
  glBindBuffer(GL_ARRAY_BUFFER, result.vbo)
  # Alloc a Fixed VBO size
  glBufferData(GL_ARRAY_BUFFER, maxSize, nil, GL_STREAM_DRAW)
  # Configure Attribs 0-> Verts, 1-> Textured Rect
  glVertexAttribPointer(0, 2, cGL_FLOAT, false, 0, cast[
      pointer](0))
  glVertexAttribPointer(1, 2, cGL_FLOAT, false, 0, cast[
      pointer](rectSize))
  # Enable only attrib 0
  glEnableVertexAttribArray(0)
  # Unbind VBO and VAO
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  glBindVertexArray(0)
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

# --------
# GUI PREPARING PROCS
# --------

proc start*(ctx: var CTXRender) =
  # Use GUI program
  glUseProgram(ctx.program)
  # Prepare OpenGL Flags
  glDisable(GL_DEPTH_TEST)
  glDisable(GL_STENCIL_TEST)
  # Modify Only Texture 0
  glActiveTexture(GL_TEXTURE0)

proc viewport*(ctx: var CTXRender, w, h: int32, pro: ptr float32) =
  glViewport(0, 0, w, h)
  glUniformMatrix4fv(ctx.pro, 1, false, pro)
  # Set new height
  ctx.height = h

proc makeCurrent*(ctx: var CTXRender) =
  # Clear levels
  ctx.levels.setLen(0)
  # Disable Scissor Test
  glDisable(GL_SCISSOR_TEST)
  # Bind Batch VAO and White Pixel
  glBindVertexArray(ctx.vao)
  glBindBuffer(GL_ARRAY_BUFFER, ctx.vbo)
  glBindTexture(GL_TEXTURE_2D, ctx.white)
  # Set Default Color (Black)
  glClearColor(0.0, 0.0, 0.0, 1.0)
  glUniform4f(cast[GLint](ctx.color), 0.0, 0.0, 0.0, 1.0)

proc clearCurrent*(ctx: var CTXRender) =
  # Disable Scissor Test
  glDisable(GL_SCISSOR_TEST)
  # Unbinf VAO and VBO
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  glBindVertexArray(0)
  # Set To White Pixel
  glUniform4f(cast[GLint](ctx.color), 1.0, 1.0, 1.0, 1.0)

proc finish*(ctx: var CTXRender) =
  # Set program to None program
  glBindTexture(GL_TEXTURE_2D, 0)
  glBindVertexArray(0)
  glUseProgram(0)

# --------
# GUI PAINTER HELPER PROCS
# --------

proc intersect(ctx: ptr CTXRender, rect: var GUIRect): GUIRect =
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

proc clip*(ctx: ptr CTXRender, rect: var GUIRect) =
  if ctx.levels.len > 0:
    let nclip = ctx.intersect(rect)
    glScissor(nclip.x, ctx.height - nclip.y - nclip.h, nclip.w, nclip.h)
  else:
    glEnable(GL_SCISSOR_TEST)
    glScissor(rect.x, ctx.height - rect.y - rect.h, rect.w, rect.h)

proc color*(ctx: ptr CTXRender, color: var GUIColor) =
  glClearColor(color.r, color.g, color.b, color.a)
  glUniform4f(cast[GLint](ctx.color),
    color.r, color.g, color.b, color.a
  )

proc clear*(ctx: ptr CTXRender) {.inline.} =
  glClear(GL_COLOR_BUFFER_BIT)

proc reset*(ctx: ptr CTXRender) =
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

proc push*(ctx: ptr CTXRender, rect: var GUIRect, color: var GUIColor) =
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

proc pop*(ctx: ptr CTXRender) =
  ctx.levels.setLen(ctx.levels.len - 1)
  ctx.reset()

# --------------
# GUI BASIC DRAW PROCS
# --------------

proc fill*(ctx: ptr CTXRender, rect: var GUIRect) =
  let rectArray = [
    float32 rect.x, float32 rect.y,
    float32(rect.x + rect.w), float32 rect.y,
    float32 rect.x, float32(rect.y + rect.h),
    float32(rect.x + rect.w), float32(rect.y + rect.h)
  ]
  glBufferSubData(GL_ARRAY_BUFFER, 0, rectSize, rectArray[0].unsafeAddr)
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)