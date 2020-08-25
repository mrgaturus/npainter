from event import 
  GUIState, GUISignal, GUITarget,
  WidgetSignal, pushSignal
from render import 
  CTXRender, GUIRect, push, pop

const # Widget Bit-Flags
  wDirty* = uint8(1 shl 0) # C
  # Hidden and Visibility Check
  wHidden* = uint8(1 shl 1) # C
  wVisible* = uint8(1 shl 2) # A
  # Enabled and Clickable
  wKeyboard* = uint8(1 shl 3) # C
  wMouse* = uint8(1 shl 4) # C
  # Focus, Hover and Grab
  wFocus* = uint8(1 shl 5) # C
  wHover* = uint8(1 shl 6) # A
  wGrab* = uint8(1 shl 7) # A
  # -- Status Checking Masks
  wFocusCheck* = wVisible or wKeyboard
  wHoverCheck* = wVisible or wMouse
  wHoverGrab* = wHover or wGrab
  # -- Set/Clear Handle Masks
  wHandleMask = wFocus or wDirty
  wHandleClear = wFocus or wFocusCheck
  wProtected = # Protect Automatics
    not(wVisible or wHover or wGrab)
  # -- Widget Constructor Mask
  wStandard* = wKeyboard or wMouse

type
  GUIFlags* = uint8
  GUIHandle* = enum
    inFocus, inHover, inFrame
    outFocus, outHover, outFrame
  GUIKind* = enum
    wgChild, wgFrame # Basic
    wgPopup, wgMenu, wgTooltip
  GUIWidget* {.inheritable.} = ref object
    # Widget Parent
    parent*: GUIWidget
    # Widget Node Tree
    next*, prev*: GUIWidget
    first*, last*: GUIWidget
    # Widget Flags
    kind*: GUIKind
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
    pushSignal(self.target, msgCheck)
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

proc add*(self, widget: GUIWidget) =
  widget.parent = self
  # Add Widget to List
  if self.first.isNil:
    self.first = widget
  else: # Add to Last
    widget.prev = self.last
    self.last.next = widget
  # Set Widget To Last
  self.last = widget
  # Set Kind as Children
  widget.kind = wgChild

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
  # Mark Visible if Passed Visibility Test
  widget.flags = (widget.flags and not wVisible) or 
    (cast[uint8](test) shl 2) # See wVisible

proc pointOnArea*(widget: GUIWidget, x, y: int32): bool =
  return (widget.flags and wHoverCheck) == wHoverCheck and
    x >= widget.rect.x and x <= widget.rect.x + widget.rect.w and
    y >= widget.rect.y and y <= widget.rect.y + widget.rect.h

# -----------------------------
# WIDGET FRAMED Move and Resize
# -----------------------------

proc open*(widget: GUIWidget) =
  let target = widget.target
  case widget.kind
  of wgFrame: # Subwindow
    pushSignal(target, msgFrame)
  of wgPopup, wgMenu: # Stacked
    pushSignal(target, msgPopup)
  of wgTooltip: # Tooltip
    pushSignal(target, msgTooltip)
  of wgChild: discard # Invalid

proc close*(widget: GUIWidget) {.inline.} =
  pushSignal(widget.target, msgClose)

proc move*(widget: GUIWidget, x,y: int32) =
  if widget.kind > wgChild:
    widget.rect.x = x
    widget.rect.y = y
    # Mark Widget as Dirty
    widget.set(wDirty)

proc resize*(widget: GUIWidget, w,h: int32) =
  if widget.kind > wgChild:
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
    if result.test(wFocusCheck) or 
      result == widget: break

# --------------------------------
# WIDGET LAYOUT TREE - EVENT QUEUE
# --------------------------------

proc visible*(widget: GUIWidget): bool =
  var cursor = widget
  # Test Self Visibility
  result = cursor.test(wVisible)
  # Walk to Outermost Parent
  while result:
    cursor = cursor.parent
    if isNil(cursor): break
    else: # Test Parent Visibility
      result = cursor.test(wVisible)

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
    if (cursor.flags and wVisible) == wVisible:
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
