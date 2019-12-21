# GUI Objects
from builder import signal
from event import GUIState, GUISignal
from render import CTXRender, GUIRect, GUIPivot
from context import CTXFrame

const # set[T] doesn't has xor
  # Indicators
  wDraw* = uint16(1 shl 0)
  wUpdate* = uint16(1 shl 1)
  wLayout* = uint16(1 shl 2)
  wDirty* = uint16(1 shl 3)
  # Status
  wVisible* = uint16(1 shl 4)
  wEnabled* = uint16(1 shl 5)
  wSignal* = uint16(1 shl 6)
  # Handlers
  wFocus* = uint16(1 shl 7)
  wHover* = uint16(1 shl 8)
  wGrab* = uint16(1 shl 9)
  # Frame Flag, controlled by window
  wFramed* = uint16(1 shl 10)

type
  GUIFlags = uint16
  GUISignals = set[0'u8..63'u8]
  # A Widget can be assigned to a CTXFrame
  GUIWidget* = ref object of RootObj
    next*, prev*: GUIWidget
    signals*: GUISignals
    flags*: GUIFlags
    rect*: GUIRect
    # Frame Surface, Optionally
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

proc pointOnArea*(rect: var GUIRect, x, y: int32): bool =
  return
    x >= rect.x and x <= rect.x + rect.w and
    y >= rect.y and y <= rect.y + rect.h

proc relative*(rect: var GUIRect, state: ptr GUIState) =
  state.mx -= rect.x
  state.my -= rect.y

template absX*(widget: GUIWidget, x: int32): int32 =
  return widget.rect.x + x

template absY*(widget: GUIWidget, y: int32): int32 =
  return widget.rect.y + y

# -------------
# WIDGET FRAMED
# -------------

proc pointOnFrame*(widget: GUIWidget, x, y: int32): bool =
  return
    x >= widget.pivot.x and x <= widget.pivot.x + widget.rect.w and
    y >= widget.pivot.y and y <= widget.pivot.y + widget.rect.h

proc relative*(widget: GUIWidget, state: ptr GUIState) =
  state.mx -= widget.pivot.x
  state.my -= widget.pivot.y

proc region*(widget: GUIWidget): GUIRect {.inline.} =
  copyMem(addr result, addr widget.rect, sizeof(GUIRect))
  copyMem(addr widget.pivot, addr widget.rect, sizeof(int32)*2)
  zeroMem(addr widget.rect, sizeof(int32)*2)

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

# Out Handler Methods
method hoverOut*(widget: GUIWidget) {.base.} =
  if widget.test(wVisible): widget.set(wDraw)
method focusOut*(widget: GUIWidget) {.base.} =
  if widget.test(wVisible): widget.set(wDraw)
