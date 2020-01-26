# GUI Objects
from builder import signal
from event import GUIState, GUISignal, pushSignal
from render import CTXRender, GUIRect

const # For now is better use traditional flags
  # Rendering on Screen
  wFramed* = uint16(1 shl 0)
  # Indicators - Update -> Layout
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
  wHold* = uint16(1 shl 10)
  # Opaque - Misc Rendering
  wOpaque* = uint16(1 shl 12)
  # ---------------------
  # Default Flags - Widget Constructor
  wStandard* = 0x30'u16 # Visible-Enabled
  wPopup* = 0x60'u16 # Enabled-Stacked
  # Semi-Automatic Checks
  wFocusCheck* = 0xb0'u16
  wHoverGrab* = 0x300'u16

type
  GUIHandle* = enum
    inFocus, inHover, inHold, inFrame
    outFocus, outHover, outHold, outFrame
  GUIFlags* = uint16
  GUISignals = set[0'u8..63'u8]
  GUIWidget* = ref object of RootObj
    # Widget Neighbords
    next*, prev*: GUIWidget
    # Widget Basic Info
    signals*: GUISignals
    flags*: GUIFlags
    # Widget Rects
    rect*, hint*: GUIRect

signal Frame:
  Open # Open Floating
  Close # Close Floating

# ----------------
# WIDGET ITERATORS
# ----------------

# First -> Last
iterator forward*(first: GUIWidget): GUIWidget =
  var frame = first
  while frame != nil:
    yield frame
    frame = frame.next

# Last -> First
iterator reverse*(last: GUIWidget): GUIWidget =
  var frame = last
  while frame != nil:
    yield frame
    frame = frame.prev

# ------------------
# WIDGET FLAGS PROCS
# ------------------

proc set*(self: GUIWidget, mask: GUIFlags) {.inline.} =
  self.flags = self.flags or mask

proc clear*(self: GUIWidget, mask: GUIFlags) {.inline.} =
  self.flags = self.flags and not mask

proc any*(self: GUIWidget, mask: GUIFlags): bool {.inline.} =
  return (self.flags and mask) != 0

proc test*(self: GUIWidget, mask: GUIFlags): bool {.inline.} =
  return (self.flags and mask) == mask

# ----------------------
# WIDGET SIGNAL CHECKING
# ----------------------

proc `in`*(signal: uint8, self: GUIWidget): bool {.inline.} =
  return signal in self.signals

# ------------------------
# WIDGET MOUSE EVENT PROCS
# ------------------------

proc pointOnArea*(widget: GUIWidget, x, y: int32): bool =
  return widget.test(wVisible) and # For Container
    x >= widget.rect.x and x <= widget.rect.x + widget.rect.w and
    y >= widget.rect.y and y <= widget.rect.y + widget.rect.h

proc pointOnFrame*(widget: GUIWidget, x, y: int32): bool =
  return # For Sub-Windows
    x >= widget.hint.x and x <= widget.hint.x + widget.rect.w and
    y >= widget.hint.y and y <= widget.hint.y + widget.rect.h

proc relative*(widget: GUIWidget, state: ptr GUIState) =
  state.rx = state.mx - widget.hint.x
  state.ry = state.my - widget.hint.y

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
  widget.hint.x = x
  widget.hint.y = y

proc resize*(widget: GUIWidget, w, h: int32) =
  widget.rect.w = w
  widget.rect.h = h
  # Mark as Dirty
  widget.set(wDirty)

# ------------
# WIDGET ABSTRACT METHODS - Single-Threaded
# ------------

# X -- In/Out Handle Method
method handle*(widget: GUIWidget, kind: GUIHandle) {.base.} = discard
# 1 -- Event Methods
method event*(widget: GUIWidget, state: ptr GUIState) {.base.} = discard
method step*(widget: GUIWidget, back: bool) {.base.} =
  widget.flags = widget.flags xor wFocus
# 2 -- Tick Methods
method trigger*(widget: GUIWidget, signal: GUISignal) {.base.} = discard
method update*(widget: GUIWidget) {.base.} = discard
method layout*(widget: GUIWidget) {.base.} = discard
# 3 -- Draw Method
method draw*(widget: GUIWidget, ctx: ptr CTXRender) {.base.} = discard