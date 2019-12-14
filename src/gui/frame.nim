from builder import signal
import context, render, widget, container, event

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
# FRAME INIT PROCS
# ---------

proc boundaries*(frame: GUIFrame) {.inline.} =
  # Put them in new region
  region(frame.ctx, addr frame.rect)
  # Ensure x,y rect be always in 0
  copyMem(addr frame.x, addr frame.rect, sizeof(int32)*2)
  zeroMem(addr frame.rect, sizeof(int32)*2)

# ---------
# FRAME HELPER PROCS
# ---------

proc pointOnArea*(frame: GUIFrame, x, y: int32): bool {.inline.} =
  result = 
    frame.test(wVisible) and
    x >= frame.x and x <= frame.x + frame.rect.w and
    y >= frame.y and y <= frame.y + frame.rect.h

proc relative*(frame: GUIFrame, state: var GUIState) {.inline.} =
  state.mx -= frame.x
  state.my -= frame.y

# ---------
# FRAME RUNNING PROCS
# ---------

proc boundaries*(frame: GUIFrame, bounds: ptr SFrame, resize: bool) =
  # Resize Texture
  if resize:
    copyMem(addr frame.rect.w, addr bounds.w, sizeof(int32)*2)
    frame.set(wDirty)
  # Move
  copyMem(addr frame.x, addr bounds.x, sizeof(int32)*2)
  # Update Region
  region(frame.ctx, addr frame.rect)

proc handleTick*(frame: GUIFrame) =
  if frame.any(wUpdate or wLayout or wDirty):
    if frame.test(wUpdate):
      update(frame)
    if frame.any(wUpdate or wDirty):
      layout(frame)

# ---------
# FRAME RENDERING PROCS
# ---------

proc render*(frame: GUIFrame, ctx: var GUIContext) =
  if frame.test(wVisible):
    if frame.test(wDraw):
      makeCurrent(ctx, frame.ctx)
      draw(frame, ctx[])
      clearCurrent(ctx)
    # Render Frame Texture
    render(frame.ctx)
