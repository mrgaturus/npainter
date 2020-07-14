from event import 
  GUIState, GUISignal, GUITarget,
  WidgetSignal, pushSignal
from render import 
  CTXRender, GUIRect, push, pop

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
  wStandard* = wVisible or wEnabled # Visible-Enabled
  wPopup* = wEnabled or wStacked # Enabled-Stacked
  # Multi-Checking Flags
  wFocusHold = wFocus or wHold
  wComplex = wFocus or wHold or wDirty
  # Public Multi-Checking Flags
  wHoverGrab* = wHover or wGrab
  wFocusCheck* = wFocus or wVisible or wEnabled

type
  GUIFlags* = uint16
  GUIHandle* = enum
    inFocus, inHover, inHold, inFrame
    outFocus, outHover, outHold, outFrame
  GUIWidget* {.inheritable.} = ref object
    # Widget Parent
    parent*: GUIWidget
    # Widget Node Tree
    next*, prev*: GUIWidget
    first*, last*: GUIWidget
    # Widget Flags
    flags*: GUIFlags
    # Widget Rect&Hint
    rect*, hint*: GUIRect

# ----------------------------
# WIDGET NEIGHTBORDS ITERATORS
# ----------------------------

# First -> Last
iterator forward*(first: GUIWidget): GUIWidget =
  var frame = first
  while not isNil(frame):
    yield frame
    frame = frame.next

# Last -> First
iterator reverse*(last: GUIWidget): GUIWidget =
  var frame = last
  while not isNil(frame):
    yield frame
    frame = frame.prev

# ---------------------------
# WIDGET FLAGS & TARGET PROCS
# ---------------------------

proc target*(self: GUIWidget): GUITarget {.inline.} =
  return cast[GUITarget](self)

proc set*(self: GUIWidget, mask: GUIFlags) =
  if (mask and wComplex) > 0:
    let # Compare Flags
      delta = self.flags xor mask
      target = self.target
    if (delta and wFocusHold) == wFocus:
      pushSignal(target, msgFocus)
    if (delta and wHold) == wHold:
      pushSignal(target, msgHold)
    if (delta and wDirty) == wDirty:
      pushSignal(target, msgDirty)
  # Replace Current Flags
  self.flags = self.flags or 
    (mask and not wFocusHold)

proc clear*(self: GUIWidget, mask: GUIFlags) {.inline.} =
  self.flags = self.flags and not mask

proc any*(self: GUIWidget, mask: GUIFlags): bool {.inline.} =
  return (self.flags and mask) > 0

proc test*(self: GUIWidget, mask: GUIFlags): bool {.inline.} =
  return (self.flags and mask) == mask

# ----------------------------
# WIDGET ADD CHILD NODES PROCS
# ----------------------------

proc add*(parent, widget: GUIWidget) =
  widget.parent = parent
  # Add Widget to List
  if parent.first.isNil:
    parent.first = widget
  else: # Add to Last
    widget.prev = parent.last
    parent.last.next = widget
  # Set Widget To Last
  parent.last = widget

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

# ------------------------------
# WIDGET FINDING BY CURSOR PROCS
# ------------------------------

proc find*(widget: GUIWidget, x, y: int32): GUIWidget =
  result = widget.last
  if isNil(result):
    return widget
  # Find Children
  while true:
    if pointOnArea(result, x, y):
      if isNil(result.last):
        return result
      else: # Find Inside
        result = result.last
    # Check Prev Widget
    if isNil(result.prev):
      return result.parent
    else: # Prev Widget
      result = result.prev

proc find*(widget, root: GUIWidget, x, y: int32): GUIWidget =
  # Initial Widget
  result = widget
  # Initial Cursor
  var cursor = widget
  # Point Inside All Parents?
  while cursor != root:
    if not pointOnArea(cursor, x, y):
      result = cursor.parent
    cursor = cursor.parent
  # Find Inside of Outside
  if not isNil(result.last):
    result = find(result, x, y)

# -----------------------
# WIDGET STEP FOCUS PROCS
# -----------------------

proc step*(widget: GUIWidget, back: bool): GUIWidget =
  result = widget
  # Step Neightbords until is focusable of is the same again
  while true:
    result = # Step Widget
      if back: result.prev
      else: result.next
    # Reroll Widget
    if isNil(result):
      result = # Restart Widget
        if back: widget.parent.last
        else: widget.parent.first
    # Check if is Focusable or is the same again
    if result.test(wEnabled or wVisible) or 
      result == widget: break

# ---------------------------------------
# WIDGET FRAMED open/close or move/resize
# ---------------------------------------

proc open*(widget: GUIWidget) =
  if (widget.flags and (wFramed or wVisible)) == 0:
    pushSignal(cast[GUITarget](widget), msgOpen)

proc close*(widget: GUIWidget) =
  if (widget.flags and wFramed) != 0:
    pushSignal(cast[GUITarget](widget), msgClose)

proc move*(widget: GUIWidget, x,y: int32) =
  if (widget.flags and wFramed) != 0:
    widget.rect.x = x; widget.rect.y = y
    # Mark Widget as Layout Dirty
    pushSignal(cast[GUITarget](widget), msgDirty)

proc resize*(widget: GUIWidget, w,h: int32) =
  if (widget.flags and wFramed) != 0:
    widget.rect.w = max(w, widget.hint.w)
    widget.rect.h = max(h, widget.hint.h)
    # Mark as Widget as Layout Dirty
    pushSignal(cast[GUITarget](widget), msgDirty)

# -----------------------------------------
# WIDGET ABSTRACT METHODS - Single-Threaded
# -----------------------------------------

method handle*(widget: GUIWidget, kind: GUIHandle) {.base.} = discard
method event*(widget: GUIWidget, state: ptr GUIState) {.base.} = discard
method notify*(widget: GUIWidget, sig: GUISignal) {.base.} = discard
method update*(widget: GUIWidget) {.base.} = discard
method layout*(widget: GUIWidget) {.base.} = discard
method draw*(widget: GUIWidget, ctx: ptr CTXRender) {.base.} = discard

# ------------------------------
# WIDGET TREE DIRTY/RENDER PROCS
# ------------------------------

proc dirty*(widget: GUIWidget) =
  var cursor = widget
  # Relayout Widget Tree
  while true:
    if cursor != widget: # Calculate Absolute
      calcAbsolute(cursor, cursor.parent.rect)
    if cursor.test(wVisible):
      cursor.layout()
    cursor = # Select Next Widget
      if not isNil(cursor.first):
        cursor.first
      elif isNil(cursor.next):
        if cursor.parent == widget: 
          break # Stop Loop
        cursor.parent.next
      else: cursor.next
  widget.flags = # Remove Widget Dirty
    widget.flags and not wDirty

proc render*(widget: GUIWidget, ctx: ptr CTXRender) =
  var cursor = widget
  # Relayout Widget Tree
  while true:
    if cursor.test(wVisible):
      cursor.draw(ctx)
    cursor = # Select Next Widget
      if not isNil(cursor.first):
        # Push Clipping
        ctx.push(cursor.rect)
        # Push Tree Level
        cursor.first
      elif isNil(cursor.next):
        # Pop Clipping
        ctx.pop()
        # Check Tree Ending
        if cursor.parent == widget: 
          break # Stop Loop
        # Pop Tree Level
        cursor.parent.next
      else: cursor.next
