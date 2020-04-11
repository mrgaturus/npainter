from event import GUIState, GUIEvent, GUISignal
import widget, render

const
  # Partial Layout Handling
  cDirty* = uint16(1 shl 11)
  # Reactive for Indicators
  cReactive = 0x0e'u16

type
  # GUIContainer, Base class for Layout creation
  GUIContainer* = ref object of GUIWidget
    first*, last*: GUIWidget  # Iterating / Inserting
    hold, focus, hover: GUIWidget # Cache Pointers
    color*: GUIColor # Background Color

# --------------------------
# CONTAINER ABSTRACT METHODS
# --------------------------

method arrange*(self: GUIContainer) {.base.} = discard
# notify(signal) is a reusable method

# -------------------------
# CONTAINER ADD WIDGET PROC
# -------------------------

proc add*(self: GUIContainer, widget: GUIWidget) =
  widget.parent =
    cast[GUIParent](self)
  # Add Widget to List
  if self.first.isNil:
    self.first = widget
  else:
    widget.prev = self.last
    self.last.next = widget
  # Set Widget To Last
  self.last = widget

# -----------------------
# CONTAINER PRIVATE PROCS
# -----------------------

proc semiReactive(self: GUIContainer, flags: GUIFlags) =
  self.flags = self.flags or (flags and cReactive)
  # Partial Relayout Reaction
  if (flags and wDirty) == wDirty:
    self.flags = flags or 0x804'u16

proc reactive(self: GUIContainer, widget: GUIWidget) =
  self.flags = self.flags or (widget.flags and cReactive)
  # Partial Relayout Reaction
  if (widget.flags and wDirty) == wDirty:
    self.flags = self.flags or 0x804'u16
  # Check Hold and Focus
  let check = # Check if is enabled and visible
    (widget.flags and 0x4b0) xor 0x30'u16
  # Check/Change Hold
  if (check and wHold) == wHold:
    if widget != self.hold:
      let hold = self.hold
      if isNil(hold):
        self.set(wHold)
      elif hold.test(wHold):
        hold.handle(outHold)
        hold.clear(wHold)
        # React to indicators
        self.semiReactive(hold.flags)
      # Change Current Hold
      self.hold = widget
  elif widget == self.hold:
    self.clear(wHold)
  # Check/Change Focus
  if check == wFocus:
    if widget != self.focus:
      let focus = self.focus
      if isNil(focus):
        self.set(wFocus)
      elif focus.test(wFocus):
        # Handle Focus Out
        focus.handle(outFocus)
        focus.clear(wFocus)
        # Handle Focus In
        widget.handle(inFocus)
        widget.set(wFocus)
        # React to indicators
        self.semiReactive(focus.flags)
        self.semiReactive(widget.flags)
      # Change Current Focus
      self.focus = widget
  elif widget == self.focus:
    self.clear(wFocus)
  elif (check and wFocus) == wFocus and check > wFocus:
    widget.clear(wFocus) # Invalid focus

# ------------------------------
# CONTAINER SIGNAL REACTIVE PROC
# ------------------------------

proc reflect*(w: GUIWidget): GUIWidget =
  var c = cast[GUIContainer](w.parent)
  while not isNil(c):
    c.reactive(w) # React to flag changes
    c = cast[GUIContainer](c.parent)
  # Return Top Widget
  if isNil(c): w
  else: c

# ------------------------
# CONTAINER WIDGET METHODS
# ------------------------

method draw(self: GUIContainer, ctx: ptr CTXRender) =
  # Push Clipping
  ctx.push(self.rect)
  # Draw Background
  if (self.flags and wOpaque) == 0:
    ctx.color(self.color)
    ctx.fill rect(self.rect)
  # Draw Widgets
  for widget in forward(self.first):
    # Draw Widget if is Visible
    if (widget.flags and wVisible) == wVisible:
      widget.draw(ctx)
  # Pop Clipping
  ctx.pop()

method update(self: GUIContainer) =
  self.clear(wUpdate)
  # Update marked widgets
  for widget in forward(self.first):
    if widget.test(wUpdate):
      widget.update()
      # This mantains update marked
      self.reactive(widget)

method event(self: GUIContainer, state: ptr GUIState) =
  var found = self.hold
  # Find widget for process event
  if isNil(found): # if hold is nil, search
    case state.eventType # Mouse or Keyboard
    of evMouseMove, evMouseClick, evMouseRelease, evMouseAxis:
      found = self.hover # Cached Widget
      # If is Grabbed don't find otherwise find
      if isNil(found) and (self.test(wGrab) or
        state.eventType == evMouseRelease): discard
      elif isNil(found) or not found.test(wGrab) and
          not pointOnArea(found, state.mx, state.my):
        # Handle HoverOut
        if not isNil(found):
          found.handle(outHover)
          found.clear(wHoverGrab)
          # Update Indicators
          self.semiReactive(found.flags)
          # Clear Found
          found = nil
        # Search hovered widget
        for widget in forward(self.first):
          if pointOnArea(widget, state.mx, state.my):
            found = widget
            # Handle HoverIn
            found.handle(inHover)
            found.set(wHover)
            # Update Indicators
            self.semiReactive(found.flags)
            # Hovered Found
            break
        # Can be nil or not
        self.hover = found
    of evKeyDown, evKeyUp:
      # Use Focused widget
      found = self.focus

  if not isNil(found):
    if state.eventType >= evMouseClick:
      # Heredate Grab and Hover
      found.flags = (found.flags and not wGrab) or
        (self.flags and wGrab)
      # Check if cursor is on boundaries
      if found.any(wGrab or wHold):
        if pointOnArea(found, state.mx, state.my):
          found.set(wHover)
        else: found.clear(wHover)
    found.event(state)
    # React and Check
    self.reactive(found)

method step(self: GUIContainer, back: bool) =
  var focus =
    if isNil(self.focus):
      if back: self.last
      else: self.first
    elif back: self.focus.prev
    else: self.focus.next
  while not isNil(focus):
    focus.step(back)
    self.reactive(focus)
    # Check if widget was focused
    if self.test(wFocusCheck): return
    focus =
      if back: focus.prev
      else: focus.next
  # Unfocus if reached end
  self.clear(wFocus)

method layout(self: GUIContainer) =
  let dirty = # Check Dirty/Partial Dirty
    self.any(wDirty or cDirty)
  # Arrange Widgets
  if dirty: arrange(self)
  for widget in forward(self.first):
    # Mark as dirty if container is dirty
    widget.set(cast[uint16](dirty) shl 3'u16) 
    # Layout Indicator Check
    if widget.any(0x0C):
      widget.clear(0x0C)
      if dirty: # Change Absolute Position
        calcAbsolute(widget, self.rect)
      # Do Layoutning if visible
      if widget.test(wVisible):
        widget.layout()
        # React To Flag Changes
        self.reactive(widget)

method handle(self: GUIContainer, kind: GUIHandle) =
  var
    widget: GUIWidget
    flag: GUIFlags
  case kind
  of inHover: # Hover Back Hold
    widget = self.hold
    # Change Hover to Hold
    self.hover = widget
  of outHover: # Unhover current widget
    widget = self.hover
    flag = wHoverGrab
    # Remove Hover
    self.hover = nil
  of inFocus, outFocus:
    widget = self.focus
    flag = wFocus
    # Remove Focus if is Out
    if kind == outFocus:
      self.focus = nil
  of inHold, outHold:
    widget = self.hold
    flag = wHold
    # Remove Hold if is Out
    if kind == outHold:
      self.hold = nil
  else: discard
  # Handle In/Out on widget
  if not isNil(widget):
    # Call In/Out Method
    widget.handle(kind)
    # Turn on or off the flag
    if kind < outFocus:
      widget.set(flag)
    else: widget.clear(flag)
    # Only React to Draw, Update, Layout
    self.semiReactive(widget.flags)
