from builder import signal
import context, widget, container, event

signal Frame:
  Move
  Resize
  Show
  Hide

type
  GUIFrame* = ref object of GUIContainer
    fID*: uint16
    x, y: int32
    ctx: CTXFrame
  SFrame* = object
    fID*: uint16
    x, y, w, h: int32

proc newGUIFrame*(layout: GUILayout, color: GUIColor): GUIFrame =
  new result
  # GUILayout
  result.layout = layout
  result.color = color
  # GUIWidget Default Flags
  result.flags = wVisible or wSignal or wDirty
  # Render Frame
  result.ctx = createFrame()

# ---------
# FRAME RUNNING PROCS
# ---------

proc boundaries*(frame: GUIFrame) {.inline.} =
  # Put them in new region
  region(frame.ctx, addr frame.rect)
  # Ensure x,y rect be always in 0
  copyMem(addr frame.x, addr frame.rect, sizeof(int32)*2)
  zeroMem(addr frame.rect, sizeof(int32)*2)

proc boundaries*(frame: GUIFrame, bounds: ptr SFrame, resize: bool) =
  # Resize Texture
  if resize:
    copyMem(addr frame.rect.w, addr bounds.w, sizeof(int32)*2)
    setMask(frame.flags, wDirty)
  # Move
  copyMem(addr frame.x, addr bounds.x, sizeof(int32)*2)
  # Update Region
  region(frame.ctx, addr frame.rect)

proc handleEvent*(frame: GUIFrame, state: ptr GUIState, tab: bool): bool =
  # Make cursor relative
  let
    x = state.mx - frame.x
    y = state.my - frame.y
  case state.eventType:
  of evMouseClick, evMouseRelease, evMouseMove, evMouseAxis:
    result = pointOnArea(frame.rect, x, y)
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
    if anyMask(frame.flags, wUpdate or wDirty):
      layout(frame)

# ---------
# FRAME RENDERING PROCS
# ---------

proc render*(frame: GUIFrame, ctx: var GUIContext) =
  if testMask(frame.flags, wVisible):
    if testMask(frame.flags, wDraw):
      makeCurrent(ctx, frame.ctx)
      draw(frame, addr ctx)
      clearCurrent(ctx)
    # Render Frame Texture
    render(frame.ctx)
