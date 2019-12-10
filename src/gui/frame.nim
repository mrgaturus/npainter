from builder import signal
import context, widget, container, event

signal Frame:
  Move
  Resize
  Show
  Hide

type
  GUIFrame* = ref object of GUIContainer
    ctx: CTXFrame
    fID*: uint16
  SFrame* = object
    fID*: uint16
    x, y, w, h: int32

proc newGUIFrame*(layout: GUILayout, color: GUIColor): GUIFrame =
  new result
  # GUILayout
  result.layout = layout
  result.color = color
  # GUIWidget Default Flags
  result.flags = 0x0638
  # Render Frame
  result.ctx = createFrame()

# ---------
# FRAME HELPER PROCS
# ---------

proc region(tex: var CTXFrame, rect: ptr GUIRect) =
  let verts = [
    float32 rect.x, float32 rect.y,
    float32(rect.x + rect.w), float32 rect.y,
    float32 rect.x, float32(rect.y + rect.h),
    float32(rect.x + rect.w), float32(rect.y + rect.h)
  ]
  region(tex, unsafeAddr verts[0])

# ---------
# FRAME RUNNING PROCS
# ---------

proc boundaries*(frame: GUIFrame, bounds: ptr SFrame, resize: bool) =
  # Resize Texture
  if resize:
    copyMem(addr frame.rect.w, addr bounds.w, sizeof(int32)*2)
    resize(frame.ctx, bounds.w, bounds.h)
    setMask(frame.flags, wDirty)
  # Move
  copyMem(addr frame.rect, addr bounds.x, sizeof(int32)*2)
  # Update Region
  region(frame.ctx, addr frame.rect)

proc handleEvent*(frame: GUIFrame, state: ptr GUIState, tab: bool): bool =
  case state.eventType:
  of evMouseClick, evMouseRelease, evMouseMove, evMouseAxis:
    result = pointOnArea(frame.rect, state.mx, state.my)
  of evKeyDown, evKeyUp:
    result = testMask(frame.flags, wFocusCheck)
  # if event can be done in that frame, procced
  if result:
    if tab: step(frame, state.key == LeftTab)
    else: event(frame, state)

proc handleTick*(frame: GUIFrame) =
  if anyMask(frame.flags, wUpdate or wLayout or wDirty):
    if testMask(frame.flags, wUpdate):
      update(frame)
    if anyMask(frame.flags, 0x000C):
      layout(frame)

proc render*(frame: GUIFrame, ctx: var GUIContext) =
  if testMask(frame.flags, wVisible):
    if testMask(frame.flags, wDraw):
      makeCurrent(ctx, frame.ctx)
      draw(frame, addr ctx)
      clearCurrent(ctx)
    # Render Frame Texture
    render(frame.ctx)
