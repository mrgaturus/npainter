# GUI Objects
from builder import signal
from event import GUIState, GUISignal, pushSignal
from render import CTXRender, GUIRect

const # For now is better use traditional flags
  # Rendering on Screen
  wFramed* = uint16(1 shl 0) # A
  # Indicators - Update -> Layout
  wUpdate* = uint16(1 shl 1)
  wLayout* = uint16(1 shl 2)
  wDirty* = uint16(1 shl 3)
  # Status - Visible, Enabled and Popup
  wVisible* = uint16(1 shl 4) # A
  wEnabled* = uint16(1 shl 5)
  wStacked* = uint16(1 shl 6)
  # Handlers - Focus, Hover and Grab
  wFocus* = uint16(1 shl 7)
  wHover* = uint16(1 shl 8) # A
  wGrab* = uint16(1 shl 9) # A
  wHold* = uint16(1 shl 10)
  # Rendering - Opaque and Forced Hidden
  wOpaque* = uint16(1 shl 12)
  wHidden* = uint16(1 shl 13)
  # ---------------------
  # Default Flags - Widget Constructor
  wStandard* = 0x30'u16 # Visible-Enabled
  wPopup* = 0x60'u16 # Enabled-Stacked
  # Multi-Checking Flags
  wFocusCheck* = 0xb0'u16
  wHoverGrab* = 0x300'u16

type
  GUIFlags* = uint16
  GUIHandle* = enum
    inFocus, inHover, inHold, inFrame
    outFocus, outHover, outHold, outFrame
  GUIWidget* {.inheritable.} = ref object
    # Widget Neighbords
    next*, prev*: GUIWidget
    # Widget Flags
    flags*: GUIFlags
    # Widget Rect&Hint
    rect*, hint*: GUIRect
    # Signal Groups
    signals*: set[0u8..63u8]

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

# ------------------------------------
# WIDGET RECT PROCS layout-mouse event
# ------------------------------------

proc geometry*(widget: GUIWidget, x,y,w,h: int32) =
  widget.hint.x = x; widget.hint.y = y
  widget.rect.w = w; widget.rect.h = h

proc minimum*(widget: GUIWidget, w,h: int32) =
  widget.hint.w = w; widget.hint.h = h

proc calcAbsolute*(widget: GUIWidget, pivot: var GUIRect) =
  # Calcule Absolute Position
  widget.rect.x = pivot.x + widget.hint.x
  widget.rect.y = pivot.y + widget.hint.y
  # Test Visibility Boundaries
  let test = (widget.flags and wHidden) == 0 and
    widget.rect.x <= pivot.x + pivot.w and
    widget.rect.y <= pivot.y + pivot.h and
    widget.rect.x + widget.rect.w >= pivot.x and
    widget.rect.y + widget.rect.h >= pivot.y
  # Mark Visible if Passed
  widget.flags = (widget.flags and not wVisible) or 
    (cast[uint16](test) shl 4)

proc pointOnArea*(widget: GUIWidget, x, y: int32): bool =
  return (widget.flags and wVisible) == wVisible and
    x >= widget.rect.x and x <= widget.rect.x + widget.rect.w and
    y >= widget.rect.y and y <= widget.rect.y + widget.rect.h

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

proc move*(widget: GUIWidget, x,y: int32) =
  if (widget.flags and not wVisible or wFramed) != 0:
    widget.rect.x = x; widget.rect.y = y
    # Mark as Dirty
    widget.set(wDirty)

proc resize*(widget: GUIWidget, w,h: int32) =
  if (widget.flags and not wVisible or wFramed) != 0:
    widget.rect.w = max(w, widget.hint.w)
    widget.rect.h = max(h, widget.hint.h)
    # Mark as Dirty
    widget.set(wDirty)

# -----------------------------------------
# WIDGET ABSTRACT METHODS - Single-Threaded
# -----------------------------------------

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