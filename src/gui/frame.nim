import context, widget, state

type
  GUIFrame* = object
    gui: GUIWidget
    tex: ptr CTXFrame

# -------------------
# GUIFRAME CREATION PROCS
# -------------------

proc newGUIFrame*(ctx: var GUIContext, widget: GUIWidget): GUIFrame =
  result.gui = widget
  result.tex = ctx.createFrame()

# -------------------
# GUIFRAME HELPER PROCS
# -------------------

proc region(tex: ptr CTXFrame, rect: ptr GUIRect) =
  let verts = [
    float32 rect.x, float32 rect.y,
    float32(rect.x + rect.w), float32 rect.y,
    float32 rect.x, float32(rect.y + rect.h),
    float32(rect.x + rect.w), float32(rect.y + rect.h)
  ]
  region(tex, unsafeAddr verts[0])

# -------------------
# GUIFRAME CONTROL PROCS
# -------------------

proc focus*(frame: var GUIFrame, f: bool) =
  if testMask(frame.gui.flags, wEnabled or wVisible):
    setMask(frame.gui.flags, wFocus or wDraw)

proc visible*(frame: var GUIFrame, v: bool) =
  frame.tex.visible = v
  if v:
    setMask(frame.gui.flags, wVisible)
    if testMask(frame.gui.flags, wEnabled):
      setMask(frame.gui.flags, wFocus or wDraw)
  else:
    if testMask(frame.gui.flags, wFocus):
      focusOut(frame.gui)
    clearMask(frame.gui.flags, wVisible or wFocus)

proc move*(frame: var GUIFrame) =
  region(frame.tex, addr frame.gui.rect)

proc resize*(frame: var GUIFrame) =
  let rect = addr frame.gui.rect
  resize(frame.tex, rect.w, rect.h)
  region(frame.tex, rect)
  # Mark as dirty
  setMask(frame.gui.flags, wDirty)

# -------------------
# GUIFRAME RUNNING PROCS
# -------------------

proc event*(frame: var GUIFrame, state: ptr GUIState): bool =
  case state.eventType:
  of evMouseMove, evMouseClick, evMouseUnclick, evMouseAxis:
    result = 
      testMask(frame.gui.flags, wVisible) and
      pointOnArea(frame.gui.rect, state.mx, state.my)
    if result:
      setMask(frame.gui.flags, wHover)
    elif testMask(frame.gui.flags, wHover):
      hoverOut(frame.gui)
  of evKeyDown, evKeyUp:
    result = testMask(frame.gui.flags, wFocusCheck)
  
  if result:
    event(frame.gui, state)

proc trigger*(frame: var GUIFrame, signal: GUISignal) =
  if signal.id == frame.gui.id:
    trigger(frame.gui, signal)

proc update_layout*(frame: var GUIFrame) =
  # Update -> Layout
  if testMask(frame.gui.flags, wUpdate):
    update(frame.gui)
  if anyMask(frame.gui.flags, 0x000C):
    layout(frame.gui)

proc draw*(frame: var GUIFrame, ctx: var GUIContext) =
  if testMask(frame.gui.flags, wDraw):
    makeCurrent(ctx, frame.tex)
    draw(frame.gui, addr ctx)