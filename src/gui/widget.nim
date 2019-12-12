# GUI Objects
from event import GUIState, GUISignal
from context import GUIContext, GUIRect

const
  # Indicators
  wDraw* = 0x0001'u16
  wUpdate* = 0x0002'u16
  wLayout* = 0x0004'u16
  wDirty* = 0x0008'u16
  # Status
  wVisible* = 0x0010'u16
  wEnabled* = 0x0020'u16
  # Handlers
  wFocus* = 0x0040'u16
  wHover* = 0x0080'u16
  wGrab* = 0x0100'u16
  # Signal-Enabled
  wSignal* = 0x0200'u16

type
  GUIWidget* = ref object of RootObj
    next*, prev*: GUIWidget
    flags*, id*: uint16
    rect*: GUIRect

# WIDGET FLAGS
proc set*(self: GUIWidget, mask: uint16) {.inline.} =
  self.flags = self.flags or mask

proc clear*(self: GUIWidget, mask: uint16) {.inline.} =
  self.flags = self.flags and not mask

proc any*(self: GUIWidget, mask: uint16): bool {.inline.} =
  return (self.flags and mask) != 0

proc test*(self: GUIWidget, mask: uint16): bool {.inline.} =
  return (self.flags and mask) == mask

proc testClear*(self: GUIWidget, mask: uint16): bool {.inline.} =
  result = (self.flags and mask) == mask
  self.flags = self.flags and not mask

# WIDGET RECT
proc pointOnArea*(rect: var GUIRect, x, y: int): bool =
  result =
    x >= rect.x and x <= rect.x + rect.w and
    y >= rect.y and y <= rect.y + rect.h

# WIDGET ABSTRACT METHODS - Single-Threaded
{.pragma: guibase, base, locks: "unknown".}

method draw*(widget: GUIWidget, ctx: ptr GUIContext) {.guibase.} = 
  widget.clear(wDraw)
method update*(widget: GUIWidget) {.guibase.} = discard
method event*(widget: GUIWidget, state: ptr GUIState) {.guibase.} = discard
method layout*(widget: GUIWidget) {.guibase.} = discard
method trigger*(widget: GUIWidget, signal: GUISignal) {.guibase.} = discard
method step*(widget: GUIWidget, back: bool) {.guibase.} =
  widget.flags = (widget.flags xor wFocus) or wDraw

method hoverOut*(widget: GUIWidget) {.guibase.} =
  if widget.test(wVisible):
    widget.set(wDraw)

method focusOut*(widget: GUIWidget) {.guibase.} =
  if widget.test(wVisible):
    widget.set(wDraw)
