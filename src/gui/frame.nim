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
# FRAME HELPER PROCS
# ---------

proc pointOnArea*(frame: GUIFrame, x, y: int32): bool {.inline.} =
  result =
    x >= frame.x and x <= frame.x + frame.rect.w and
    y >= frame.y and y <= frame.y + frame.rect.h

proc relative*(frame: GUIFrame, state: var GUIState) {.inline.} =
  state.mx -= frame.x
  state.my -= frame.y

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
