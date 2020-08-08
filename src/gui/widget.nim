from event import 
  GUIState, GUISignal, GUITarget,
  WidgetSignal, pushSignal
from render import 
  CTXRender, GUIRect, push, pop

const # Widget Bit-Flags
  wChild* = uint16(1 shl 0) # C
  wFrame* = uint16(1 shl 1) # C
  wPopup* = uint16(1 shl 2) # C
  wWalker* = uint16(1 shl 3) # A
  wTooltip* = uint16(1 shl 4) # C
  # Layoutning Mark - Placeholder
  wDirty* = uint16(1 shl 5) # C
  # Status - Visible, Enabled and Popup
  wVisible* = uint16(1 shl 6) # A
  wEnabled* = uint16(1 shl 7) # C
  wKeyboard* = uint16(1 shl 8) # C
  wMouse* = uint16(1 shl 9) # C
  # Handlers - Focus, Hover and Grab
  wFocus* = uint16(1 shl 10) # C
  wHover* = uint16(1 shl 11) # A
  wGrab* = uint16(1 shl 12) # A
  # Rendering - Opaque and Forced Hidden
  wOpaque* = uint16(1 shl 13) # C
  wHidden* = uint16(1 shl 14) # C
  # ------ WIDGET FLAGS MASKS ------
  wFocusable* = wEnabled or wKeyboard
  wClickable* = wVisible or wMouse
  # -- Convenient Combinations Masks
  wHoverGrab* = wHover or wGrab
  wFraming* = wFrame or wPopup or wTooltip
  # -- Checking Flags Masks
  wWalkCheck* = wPopup or wWalker
  wFrameCheck* = wChild or wFraming
  wRenderCheck* = wVisible or wOpaque
  wFocusCheck* = wFocusable or wFocus
  wGrabCheck* = wPopup or wWalker or wGrab
  # -- Reactive Handling Mask Flags
  wHandleMask = wFraming or wDirty or wFocus
  wHandleClear = wFraming or wFocusCheck
  # -- Protect Automatic / Define Flags
  wProtected = # Avoid Changing Automatics
    not(wChild or wWalker or wVisible or wHoverGrab)
  # -- Default Flags - Widget Constructor
  wStandard* = wFocusable or wMouse

type
  GUIFlags* = uint16
  GUIHandle* = enum
    inFocus, inHover, inFrame
    outFocus, outHover, outFrame
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

# ------------------------------------
# WIDGET SIGNAL & FLAGS HANDLING PROCS
# ------------------------------------

# -- Widget Signal Target
proc target*(self: GUIWidget): GUITarget {.inline.} =
  cast[GUITarget](self) # Avoid Ref Count Loosing

# -- Unsafe Flags Handling
proc set*(flags: var GUIFlags, mask: GUIFlags) {.inline.} =
  flags = flags or mask

proc clear*(flags: var GUIFlags, mask: GUIFlags) {.inline.} =
  flags = flags and not mask

# -- Safe Flags Handling
proc set*(self: GUIWidget, mask: GUIFlags) =
  var delta = mask and not self.flags
  # Check if mask needs handling
  if (delta and wHandleMask) > 0:
    let target = self.target
    # Open Widget as Widget Frame
    if (delta and wFraming) > 0 and
    (self.flags and wFrameCheck) == 0:
      case delta and wFraming
      of wFrame: pushSignal(target, msgFrame)
      of wPopup: pushSignal(target, msgPopup)
      of wTooltip: pushSignal(target, msgTooltip)
      else: delta = delta and not wFraming
    # Relayout Widget and Childrens
    if (delta and wDirty) == wDirty:
      pushSignal(target, msgDirty)
    # Request Replace Window Focus
    if (delta and wFocus) == wFocus:
      pushSignal(target, msgFocus)
  self.flags = # Merge Flags Mask
    self.flags or (delta and wProtected)

proc clear*(self: GUIWidget, mask: GUIFlags) =
  let delta = mask and self.flags
  # Check if mask needs handling
  if (delta and wHandleClear) > 0:
    let target = self.target
    # Close Window Subwindow
    if (delta and wFraming) > 0:
      pushSignal(target, msgClose)
    # Check if focus status is altered
    if (delta and wFocusCheck) > 0:
      pushSignal(target, msgCheck)
  self.flags = # Clear Flags Mask
    self.flags and not (delta and wProtected)

# -- Flags Testing
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
  # Mark Widget as Children
  widget.flags.set(wChild)

# ------------------------------------
# WIDGET RECT PROCS layout-mouse event
# ------------------------------------

proc geometry*(widget: GUIWidget, x,y,w,h: int32) =
  widget.hint.x = x; widget.hint.y = y
  widget.rect.w = w; widget.rect.h = h

proc minimum*(widget: GUIWidget, w,h: int32) =
  widget.hint.w = w; widget.hint.h = h

# -- Used by Layout for Surface Visibility
proc calcAbsolute(widget: GUIWidget, pivot: var GUIRect) =
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
    (cast[uint16](test) shl 6)

proc pointOnArea*(widget: GUIWidget, x, y: int32): bool =
  return (widget.flags and wClickable) == wClickable and
    x >= widget.rect.x and x <= widget.rect.x + widget.rect.w and
    y >= widget.rect.y and y <= widget.rect.y + widget.rect.h

# -----------------------------
# WIDGET FRAMED Move and Resize
# -----------------------------

proc move*(widget: GUIWidget, x,y: int32) =
  if (widget.flags and wFraming) > 0:
    widget.rect.x = x; widget.rect.y = y
    # Mark Widget as Dirty
    widget.set(wDirty)

proc resize*(widget: GUIWidget, w,h: int32) =
  if (widget.flags and wFraming) > 0:
    widget.rect.w = max(w, widget.hint.w)
    widget.rect.h = max(h, widget.hint.h)
    # Mark Widget as Dirty
    widget.set(wDirty)

# -----------------------------------------
# WIDGET ABSTRACT METHODS - Single-Threaded
# -----------------------------------------

method handle*(widget: GUIWidget, kind: GUIHandle) {.base.} = discard
method event*(widget: GUIWidget, state: ptr GUIState) {.base.} = discard
method update*(widget: GUIWidget) {.base.} = discard
method layout*(widget: GUIWidget) {.base.} = discard
method draw*(widget: GUIWidget, ctx: ptr CTXRender) {.base.} = discard

# ----------------------------
# WIDGET FINDING - EVENT QUEUE
# ----------------------------

proc frame*(widget: GUIWidget): GUIWidget =
  result = widget
  # Walk to Outermost Parent
  while not isNil(result.parent):
    result = widget.parent

proc inside(widget: GUIWidget, x, y: int32): GUIWidget =
  result = widget.last
  while true: # Find Children
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

proc find*(widget: GUIWidget, x, y: int32): GUIWidget =
  # Initial Widget
  result = widget
  # Initial Cursor
  var cursor = widget
  # Point Inside All Parents?
  while cursor.parent != nil:
    if not pointOnArea(cursor, x, y):
      result = cursor.parent
    cursor = cursor.parent
  # Find Inside of Outside
  if not isNil(result.last):
    result = inside(result, x, y)

# -------------------------------
# WIDGET STEP FOCUS - EVENT QUEUE
# -------------------------------

proc step*(widget: GUIWidget, back: bool): GUIWidget =
  result = widget
  # Step Neightbords
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

# --------------------------------
# WIDGET LAYOUT TREE - EVENT QUEUE
# --------------------------------

proc visible*(widget: GUIWidget): bool =
  var cursor = widget
  # Walk to Outermost Parent
  while not isNil(cursor.parent):
    if not cursor.test(wVisible):
      return false # Invisible
    cursor = widget.parent
  true # Visible

proc dirty*(widget: GUIWidget) =
  widget.layout()
  # Check if Has Children
  if not isNil(widget.first):
    var cursor = widget.first
    while true: # Iterate Childrens
      calcAbsolute(cursor, cursor.parent.rect)
      # Do Layout and Check Inside
      if cursor.test(wVisible):
        cursor.layout()
        if not isNil(cursor.first):
          cursor = cursor.first
          continue # Next Level
      cursor = # Select Next Widget
        if isNil(cursor.next):
          if cursor.parent == widget: 
            break # Stop Loop
          cursor.parent.next
        else: cursor.next

# ------------------------------
# WIDGET RENDER CHILDRENS - MAIN LOOP
# ------------------------------

proc render*(widget: GUIWidget, ctx: ptr CTXRender) =
  # Push Clipping
  ctx.push(widget.rect)
  # Start at Children
  var cursor = widget.first
  while true: # Render Each Visible Tree Widget
    if (cursor.flags and wRenderCheck) == wVisible:
      cursor.draw(ctx)
      # Check if has Childrens
      if not isNil(cursor.first):
        # Push Clipping
        ctx.push(cursor.rect)
        # Set Cursor Next Level
        cursor = cursor.first
        continue # Next Level
    cursor = # Select Next Widget
      if isNil(cursor.next):
        # Check Tree Ending
        if cursor.parent == widget: 
          break # Stop Loop
        # Pop Clipping
        ctx.pop()
        # Pop Tree Level
        cursor.parent.next
      else: cursor.next
  # Pop Clipping
  ctx.pop()
