import ../libs/gl

type
  # GUI RECT AND COLOR
  GUIRect* = object
    x*, y*, w*, h*: int32
  GUIColor* = object
    r*, g*, b*, a*: float32
  # GUI Painter
  CTXLevel = object
    x, y, w, h: int32
    r, g, b, a: float32
  GUIRender* = object
    # White Pixel and Batch
    white, vao, vbo: GLuint
    # Color Uniform
    color: GLint
    # Viewport Height
    height: int32
    # Clipping and Color levels
    levels: seq[CTXLevel]

# --------
# GUI CREATION PROCS
# --------

proc newGUIRender*(uCol: GLint): GUIRender =
  result.color = uCol

# --------
# GUI RESET PROCS
# --------

proc reset*(ctx: var GUIRender, height: int32) =
  # Clear levels
  ctx.levels.setLen(0)
  # Disable Scissor Test
  glDisable(GL_SCISSOR_TEST)
  # Set Default Color (Black)
  glClearColor(0.0, 0.0, 0.0, 1.0)
  glUniform4f(cast[GLint](ctx.color), 0.0, 0.0, 0.0, 1.0)
  # Set new height
  ctx.height = height

proc reset*(ctx: var GUIRender) =
  # Set To White Pixel
  glDisable(GL_SCISSOR_TEST)
  glUniform4f(cast[GLint](ctx.color), 1.0, 1.0, 1.0, 1.0)

# --------
# GUI PAINTER HELPER PROCS
# --------

proc intersect(ctx: ptr GUIRender, rect: var GUIRect): tuple[x, y, w, h: int32] =
  let
    prev = addr ctx.levels[^1]
    x1 = clamp(rect.x, prev.x, prev.x + prev.w)
    y1 = clamp(rect.y, prev.y, prev.y + prev.h)
    x2 = clamp(prev.x + prev.w, rect.x, rect.x + rect.w)
    y2 = clamp(prev.y + prev.h, rect.y, rect.y + rect.h)
  result.x = x1
  result.y = y1
  result.w = abs(x2 - x1)
  result.h = abs(y2 - y1)

# -----------------------
# GUI PAINTER BASIC PROCS
# -----------------------

proc clip*(ctx: ptr GUIRender, rect: var GUIRect) =
  if ctx.levels.len > 0:
    let nclip = ctx.intersect(rect)
    glScissor(nclip.x, ctx.height - nclip.y - nclip.h, nclip.w, nclip.h)
  else:
    glEnable(GL_SCISSOR_TEST)
    glScissor(rect.x, ctx.height - rect.y - rect.h, rect.w, rect.h)

proc color*(ctx: ptr GUIRender, color: var GUIColor) =
  glClearColor(color.r, color.g, color.b, color.a)
  glUniform4f(cast[GLint](ctx.color), 
    color.r, color.g, color.b, color.a
  )

proc clear*(ctx: ptr GUIRender) {.inline.} =
  glClear(GL_COLOR_BUFFER_BIT)

proc reset*(ctx: ptr GUIRender) =
  if ctx.levels.len > 0:
    let level = addr ctx.levels[^1]
    # Reset Scissor
    glEnable(GL_SCISSOR_TEST)
    glScissor(level.x, ctx.height - level.y - level.h, level.w, level.h)
    # Reset Color
    glClearColor(level.r, level.g, level.b, level.a)
    glUniform4fv(cast[GLint](ctx.color), 1, addr level.r)
  else:
    glDisable(GL_SCISSOR_TEST)
    glClearColor(0.0, 0.0, 0.0, 1.0)
    glUniform4f(cast[GLint](ctx.color), 0.0, 0.0, 0.0, 1.0)

proc push*(ctx: ptr GUIRender, rect: var GUIRect, color: var GUIColor) =
  var level: CTXLevel
  # Copy Color
  copyMem(addr level.r, addr color, sizeof(GUIColor))
  # Get Frame Intersection
  if ctx.levels.len > 0:
    var nclip = ctx.intersect(rect)
    copyMem(addr level, addr nclip, 4 * sizeof(int32))
  else:
    copyMem(addr level, addr rect, 4 * sizeof(int32))
  # Add Level and Reset
  ctx.levels.add(level)
  ctx.reset()

proc pop*(ctx: ptr GUIRender) =
  ctx.levels.setLen(ctx.levels.len - 1)
  ctx.reset()