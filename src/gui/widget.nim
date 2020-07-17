from event import 
  GUIState, GUISignal, GUITarget,
  WidgetSignal, pushSignal
from render import 
  CTXRender, GUIRect, push, pop

const # I need XOR
  # Widget Windowing
  wFramed* = uint16(1 shl 0) # C
  wStacked* = uint16(1 shl 1) # I
  wWalker* = uint16(1 shl 2) # A
  # Layoutning Placeholder
  wDirty* = uint16(1 shl 3) # C
  # Status - Visible, Enabled and Popup
  wVisible* = uint16(1 shl 4) # A
  wEnabled* = uint16(1 shl 5) # C
  wKeyboard* = uint16(1 shl 6) # C
  wMouse* = uint16(1 shl 7) # C
  # Handlers - Focus, Hover and Grab
  wFocus* = uint16(1 shl 8) # C
  wHover* = uint16(1 shl 9) # A
  wGrab* = uint16(1 shl 10) # A
  # Rendering - Opaque and Forced Hidden
  wOpaque* = uint16(1 shl 11) # C
  wHidden* = uint16(1 shl 12) # C
  # ------ WIDGET FLAGS MASKS ------
  wFocusable* = wEnabled or wKeyboard
  wClickable = wVisible or wMouse
  # -- Flags Checking Mask
  wFrameCheck* = wFramed or wVisible
  wWalkCheck* = wStacked or wWalker
  wGrabCheck* = wWalkCheck or wGrab
  wFocusCheck* = wFocusable or wFocus
  wRenderCheck = wVisible or wOpaque
  # -- Default Flags - Widget Constructor
  wStandard* = wFocusable or wMouse
  wPopup* = wStacked or wStandard
  # -- Window-Only Automatic Handling
  wStackGrab* = wStacked or wGrab
  wHoverGrab* = wHover or wGrab
  # -- Reactive Handling Mask Flags
  wHandleMask = wFramed or wDirty or wFocus
  wHandleClear = wFramed or wFocusCheck
  # -- Protect Automatic / Define Flags
  wProtected = # Avoid Changing Automatics
    not(wStacked or wWalker or wVisible or wHoverGrab)

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

# --------------------------
# WIDGET SIGNAL TARGET PROCS
# --------------------------

proc target*(self: GUIWidget): GUITarget {.inline.} =
  assert(not self.isNil); cast[GUITarget](self)

template trigger*(target: GUITarget) =
  pushSignal(target, msgTrigger)

template trigger*(target: GUITarget, data: typed) =
  pushSignal(target, msgTrigger, data)

# -------------------------------
# WIDGET FLAGS MANIPULATION PROCS
# -------------------------------

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
    # Open Widget as Subwindow
    if (delta and wFramed) == wFramed:
      pushSignal(target, msgOpen)
      delta = delta or wDirty
    # Relayout Widget and Childrens
    if (delta and wDirty) == wDirty:
      pushSignal(target, msgDirty)
    # Request Replace Window Focus
    if (delta and wFocus) == wFocus:
      pushSignal(target, msgFocus)
      delta = delta and not wFocus
  self.flags = # Merge Flags Mask
    self.flags or (delta and wProtected)

proc clear*(self: GUIWidget, mask: GUIFlags) =
  var delta = mask and self.flags
  # Check if mask needs handling
  if (delta and wHandleClear) > 0:
    let target = self.target
    # Close Window Subwindow
    if (delta and wFramed) == wFramed:
      pushSignal(target, msgClose)
    # Check if focus status is altered
    if (delta and wFocusCheck) > 0:
      pushSignal(target, msgCheck)
  self.flags = # Clear Flags Mask
    self.flags and not (delta and wProtected)

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

# -- Used by Layout for Surface Visibility
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
  return (widget.flags and wClickable) == wClickable and
    x >= widget.rect.x and x <= widget.rect.x + widget.rect.w and
    y >= widget.rect.y and y <= widget.rect.y + widget.rect.h

# -----------------------------
# WIDGET FRAMED Move and Resize
# -----------------------------

proc move*(widget: GUIWidget, x,y: int32) =
  if (widget.flags and wFramed) != 0:
    widget.rect.x = x; widget.rect.y = y
    # Mark Widget as Dirty
    widget.set(wDirty)

proc resize*(widget: GUIWidget, w,h: int32) =
  if (widget.flags and wFramed) != 0:
    widget.rect.w = max(w, widget.hint.w)
    widget.rect.h = max(h, widget.hint.h)
    # Mark Widget as Dirty
    widget.set(wDirty)

# -----------------------------------------
# WIDGET ABSTRACT METHODS - Single-Threaded
# -----------------------------------------

method handle*(widget: GUIWidget, kind: GUIHandle) {.base.} = discard
method event*(widget: GUIWidget, state: ptr GUIState) {.base.} = discard
method notify*(widget: GUIWidget, data: pointer) {.base.} = discard
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
  widget.flags = # Clear Dirty
    widget.flags and not wDirty

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
