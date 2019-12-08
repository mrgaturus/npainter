# Bitflags Procs
from bitops import clearMask, setMask
from ../extras import testMask, anyMask
# GUI Objects
from event import GUIState, GUISignal
from context import GUIContext, GUIRect
# Export bitflags Procs
export testMask, anyMask, clearMask, setMask

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
  # Combinations
  wFocusCheck* = 0x0070'u16

type
  GUIWidget* = ref object of RootObj
    next*, prev*: GUIWidget
    flags*, id*: uint16
    rect*: GUIRect

# WIDGET ABSTRACT METHODS - Single-Threaded
{.pragma: guibase, base, locks: "unknown".}

method draw*(widget: GUIWidget, ctx: ptr GUIContext) {.guibase.} = 
  widget.flags.clearMask(wDraw)
method update*(widget: GUIWidget) {.guibase.} = discard
method event*(widget: GUIWidget, state: ptr GUIState) {.guibase.} = discard
method layout*(widget: GUIWidget) {.guibase.} = discard
method trigger*(widget: GUIWidget, signal: GUISignal) {.guibase.} = discard
method step*(widget: GUIWidget, back: bool) {.guibase.} =
  widget.flags = (widget.flags xor wFocus) or wDraw

method hoverOut*(widget: GUIWidget) {.guibase.} =
  if widget.flags.testMask(wVisible):
    widget.flags.setMask(wDraw)

method focusOut*(widget: GUIWidget) {.guibase.} =
  if widget.flags.testMask(wVisible):
    widget.flags.setMask(wDraw)

# WIDGET RECT
proc pointOnArea*(rect: var GUIRect, x, y: int): bool =
  result =
    x >= rect.x and
    x <= rect.x + rect.w and
    y >= rect.y and
    y <= rect.y + rect.h