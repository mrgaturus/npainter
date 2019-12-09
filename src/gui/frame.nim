from builder import signal
import context, widget, container

signal Frame:
  Move
  Resize
  Show
  Hide

type
  GUIFrame* = ref object of GUIContainer
    ctx: CTXFrame
  FrameRegion* = object
    frame: GUIFrame
    x, y, w, h: int32

proc render*(frame: GUIFrame, ctx: var GUIContext) =
  if testMask(frame.flags, wDraw):
    makeCurrent(ctx, frame.ctx)
    draw(frame, addr ctx)
    clearCurrent(ctx)
  # Render Frame Texture
  render(frame.ctx)

discard """
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

proc leave*(frame: var GUIFrame) =
  if testMask(frame.gui.flags, wFocus):
    focusOut(frame.gui)
    clearMask(frame.gui.flags, wFocus)

proc visible*(frame: var GUIFrame, status: bool) =
  frame.tex.visible = status
  if status:
    setMask(frame.gui.flags, wVisible)
  else:
    if testMask(frame.gui.flags, wFocus):
      focusOut(frame.gui)
    clearMask(frame.gui.flags, wVisible or wFocus)

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

proc receive*(frame: var GUIFrame, signal: GUISignal): bool =
  if signal.id != frame.id: 
    return false
  case FrameMsg(signal.msg)
  of msgMove, msgResize:
    let 
      data = convert(signal.data, FrameSData)
      rect = addr frame.gui.rect
    rect.x = data.x
    rect.y = data.y
    if FrameMsg(signal.msg) == msgResize:
      rect.w = data.w
      rect.h = data.h
      resize(frame.tex, rect.w, rect.h)
      setMask(frame.gui.flags, wDirty)
    region(frame.tex, rect)
  of msgShow:
    frame.tex.visible = true
    setMask(frame.gui.flags, wVisible)
  of msgHide:
    frame.tex.visible = false
    if testMask(frame.gui.flags, wFocus):
      focusOut(frame.gui)
    clearMask(frame.gui.flags, wVisible or wFocus)
  of msgEnter: discard

  return true

proc update_layout*(frame: var GUIFrame) =
  # Update -> Layout
  if anyMask(frame.gui.flags, wUpdate or 0x000C):
    if testMask(frame.gui.flags, wUpdate):
      update(frame.gui)
    if anyMask(frame.gui.flags, 0x000C):
      layout(frame.gui)

proc draw*(frame: var GUIFrame, ctx: var GUIContext) =
  if testMask(frame.gui.flags, wDraw):
    makeCurrent(ctx, frame.tex)
    draw(frame.gui, addr ctx)
"""