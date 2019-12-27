# GUI Objects
from builder import signal
from event import GUIState, GUISignal, pushSignal
from render import CTXRender, GUIRect, GUIPivot
from context import CTXFrame

const # For now is better use traditional flags
  # Indicators - Update -> Layout -> Draw
  wDraw* = uint16(1 shl 0)
  wUpdate* = uint16(1 shl 1)
  wLayout* = uint16(1 shl 2)
  wDirty* = uint16(1 shl 3)
  # Status - Visible, Enabled or Popup
  wVisible* = uint16(1 shl 4)
  wEnabled* = uint16(1 shl 5)
  wStacked* = uint16(1 shl 6)
  # Handlers - Focus, Hover and Grab
  wFocus* = uint16(1 shl 7)
  wHover* = uint16(1 shl 8)
  wGrab* = uint16(1 shl 9)
  # Default Flags - Widget Constructor
  wStandard* = 0x30'u16
  wPopup* = 0x60'u16
  # ---------------------
  # Semi-Automatic Checks
  wFocusCheck* = 0xb0'u16

type
  GUIFlags = uint16
  GUISignals = set[0'u8..63'u8]
  # A Widget can be assigned to a CTXFrame
  GUIWidget* = ref object of RootObj
    # Widget Tree
    next*, prev*: GUIWidget
    # Widget Basic Info
    signals*: GUISignals
    flags*: GUIFlags
    rect*: GUIRect
    # Widget floating
    pivot: GUIPivot
    surf*: CTXFrame

signal Frame:
  Region
  Close
  Open

# ------------
# WIDGET FLAGS
# ------------

proc set*(self: GUIWidget, mask: GUIFlags) {.inline.} =
  self.flags = self.flags or mask

proc clear*(self: GUIWidget, mask: GUIFlags) {.inline.} =
  self.flags = self.flags and not mask

proc any*(self: GUIWidget, mask: GUIFlags): bool {.inline.} =
  return (self.flags and mask) != 0

proc test*(self: GUIWidget, mask: GUIFlags): bool {.inline.} =
  return (self.flags and mask) == mask

# -------------
# WIDGET SIGNAL
# -------------

proc `in`*(signal: uint8, self: GUIWidget): bool {.inline.} =
  return signal in self.signals

# -----------
# WIDGET RECT
# -----------

proc pointOnArea*(widget: GUIWidget, x, y: int32): bool =
  result = widget.test(wVisible)
  if result:
    let rect = addr widget.rect
    result =
      x >= rect.x and x <= rect.x + rect.w and
      y >= rect.y and y <= rect.y + rect.h

proc relative*(rect: var GUIRect, state: ptr GUIState) =
  state.mx -= rect.x
  state.my -= rect.y

template absX*(widget: GUIWidget, x: int32): int32 =
  return widget.rect.x + x

template absY*(widget: GUIWidget, y: int32): int32 =
  return widget.rect.y + y

# ------------------------
# WIDGET FRAMED open/close
# ------------------------

proc open*(widget: GUIWidget) =
  # Send Widget to Window for open
  pushSignal(
    FrameID, msgOpen,
    unsafeAddr widget,
    sizeof(GUIWidget)
  )

proc close*(widget: GUIWidget) =
  # Send Widget to window for close
  pushSignal(
    FrameID, msgClose,
    unsafeAddr widget,
    sizeof(GUIWidget)
  )

proc move*(widget: GUIWidget, x, y: int32) =
  widget.pivot.x = x
  widget.pivot.y = y
  # Send Widget to Window for move
  pushSignal(
    FrameID, msgRegion,
    unsafeAddr widget,
    sizeof(GUIWidget)
  )

proc resize*(widget: GUIWidget, w, h: int32) =
  widget.rect.w = w
  widget.rect.h = h
  # Send Widget to Window for resize
  pushSignal(
    FrameID, msgRegion,
    unsafeAddr widget,
    sizeof(GUIWidget)
  )

# ------------------------
# WIDGET FRAMED CONTROLLED
# ------------------------

proc pointOnFrame*(widget: GUIWidget, x, y: int32): bool =
  return
    x >= widget.pivot.x and x <= widget.pivot.x + widget.rect.w and
    y >= widget.pivot.y and y <= widget.pivot.y + widget.rect.h

proc relative*(widget: GUIWidget, state: ptr GUIState) =
  state.mx -= widget.pivot.x
  state.my -= widget.pivot.y

proc region*(widget: GUIWidget): GUIRect {.inline.} =
  # Make sure rect x, y is always 0
  zeroMem(addr widget.rect, sizeof(int32)*2)
  # x, y -> pivot, w, h -> rect
  copyMem(addr result, addr widget.pivot, sizeof(GUIPivot))
  copyMem(addr result.w, addr widget.rect.w, sizeof(int32)*2)

# ------------
# WIDGET ABSTRACT METHODS - Single-Threaded
# ------------

# 1 -- Event Methods
method event*(widget: GUIWidget, state: ptr GUIState) {.base.} = discard
method step*(widget: GUIWidget, back: bool) {.base.} =
  widget.flags = (widget.flags xor wFocus) or wDraw
# 2 -- Tick Methods
method trigger*(widget: GUIWidget, signal: GUISignal) {.base.} = discard
method update*(widget: GUIWidget) {.base.} = discard
method layout*(widget: GUIWidget) {.base.} = discard
# 3 -- Draw Method
method draw*(widget: GUIWidget, ctx: ptr CTXRender) {.base.} =
  widget.clear(wDraw)

# -- Out Handler Methods
method frameOut*(widget: GUIWidget) {.base.} = discard
method hoverOut*(widget: GUIWidget) {.base.} =
  if widget.test(wVisible): widget.set(wDraw)
method focusOut*(widget: GUIWidget) {.base.} =
  if widget.test(wVisible): widget.set(wDraw)
