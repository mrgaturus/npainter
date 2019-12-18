# GUI Objects
from event import GUIState, GUISignal
from render import CTXRender, GUIRect

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

type
  GUIWidget* = ref object of RootObj
    next*, prev*: GUIWidget
    flags*, id*: uint16
    rect*: GUIRect

# ------------
# WIDGET FLAGS
# ------------

proc set*(self: GUIWidget, mask: uint16) {.inline.} =
  self.flags = self.flags or mask

proc clear*(self: GUIWidget, mask: uint16) {.inline.} =
  self.flags = self.flags and not mask

proc any*(self: GUIWidget, mask: uint16): bool {.inline.} =
  return (self.flags and mask) != 0

proc test*(self: GUIWidget, mask: uint16): bool {.inline.} =
  return (self.flags and mask) == mask

# -----------
# WIDGET RECT
# -----------

proc pointOnArea*(rect: var GUIRect, x, y: int): bool =
  result =
    x >= rect.x and x <= rect.x + rect.w and
    y >= rect.y and y <= rect.y + rect.h

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

# 1 -- 2 Out Handler Methods
method hoverOut*(widget: GUIWidget) {.base.} =
  if widget.test(wVisible): widget.set(wDraw)
method focusOut*(widget: GUIWidget) {.base.} =
  if widget.test(wVisible): widget.set(wDraw)
