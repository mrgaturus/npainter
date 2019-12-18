from event import GUIState, GUIEvent, GUISignal
import widget, render

const
  wDrawDirty* = uint16(1 shl 10)
  # Combinations
  wFocusCheck* = 0xb0'u16
  wReactive = 0x0f'u16

type
  # GUIContainer, GUILayout and Decorator
  GUILayout* = ref object of RootObj
  GUIContainer* = ref object of GUIWidget
    first, last: GUIWidget  # Iterating / Inserting
    focus, hover: GUIWidget # Cache Pointers
    layout*: GUILayout
    color*: GUIColor

# LAYOUT ABSTRACT METHOD
method layout*(self: GUILayout, container: GUIContainer) {.base.} = discard

# CONTAINER PROCS
proc newGUIContainer*(layout: GUILayout, color: GUIColor): GUIContainer =
  new result
  # GUILayout
  result.layout = layout
  result.color = color
  # GUIWidget Default Flags
  result.flags = wVisible or wSignal or wDirty

proc add*(self: GUIContainer, widget: GUIWidget) =
  if self.first.isNil:
    self.first = widget
    self.last = widget
  else:
    widget.prev = self.last
    self.last.next = widget

  self.last = widget

# CONTAINER PROCS PRIVATE
iterator items*(self: GUIContainer): GUIWidget =
  var widget: GUIWidget = self.first
  while widget != nil:
    yield widget
    widget = widget.next

proc stepWidget(self: GUIContainer, back: bool): bool =
  if back:
    if self.focus.isNil:
      self.focus = self.last
    else:
      self.focus = self.focus.prev
  else:
    if self.focus.isNil:
      self.focus = self.first
    else:
      self.focus = self.focus.next

  result = not self.focus.isNil

proc checkFocus(self: GUIContainer) =
  var focus: GUIWidget = self.focus
  if focus != nil and (focus.flags and wFocusCheck) != wFocusCheck:
    focus.focusOut()
    focus.clear(wFocus)

    self.flags =
      (self.flags and not wFocus.uint16) or (focus.flags and wReactive)
    self.focus = nil

# CONTAINER METHODS
method draw(self: GUIContainer, ctx: ptr CTXRender) =
  var count = 0;

  # Push Clipping and Color Level
  ctx.push(self.rect, self.color)
  # Clear color if it was dirty
  if self.test(wDrawDirty):
    self.clear(wDrawDirty)
    ctx.clear()
  # Draw Widgets
  for widget in self:
    if (widget.flags and wDraw) == wDraw:
      widget.draw(ctx)
      inc(count)
  # Pop Clipping and Color Level
  ctx.pop()

  if count == 0:
    self.clear(wDraw)

method update(self: GUIContainer) =
  var count = 0;

  for widget in self:
    if (widget.flags and wUpdate) == wUpdate:
      widget.update()
      inc(count)

  self.checkFocus()

  if count == 0:
    self.clear(wUpdate)

method event(self: GUIContainer, state: ptr GUIState) =
  var found: GUIWidget = nil

  case state.eventType
  of evMouseMove, evMouseClick, evMouseRelease, evMouseAxis:
    found = self.hover

    if (self.flags and wGrab) == wGrab:
      if found != nil and (found.flags and wGrab) == wGrab:
        if pointOnArea(self.rect, state.mx, state.my):
          found.set(wHover)
        else:
          found.clear(wHover)
    elif found.isNil or not pointOnArea(found.rect, state.mx, state.my):
      if found != nil:
        found.hoverOut()
        found.clear(wHover)
        self.set(found.flags and wReactive)

      found = nil
      for widget in self:
        if (widget.flags and wVisible) == wVisible and
            pointOnArea(widget.rect, state.mx, state.my):
          widget.set(wHover)
          self.set(wHover)

          found = widget
          break
      if found.isNil:
        self.clear(wHover)

      self.hover = found
  of evKeyDown, evKeyUp:
    if (self.flags and wFocus) == wFocus:
      found = self.focus

  if found != nil:
    found.event(state)
    if state.eventType > evKeyDown:
      self.flags = (self.flags and not wGrab.uint16) or (
          found.flags and wGrab)

    var focus: GUIWidget = self.focus
    let check = (found.flags and wFocusCheck) xor 0x30'u16

    if check == wFocus:
      if found != focus and focus != nil:
        focus.focusOut()
        focus.clear(wFocus)

        self.set(found.flags and wReactive)
        self.focus = self.hover
      elif focus.isNil:
        self.focus = self.hover
        self.set(wFocus)
    elif (check and wFocus) == wFocus or found != focus:
      found.focusOut()
      found.clear(wFocus)

      if (found == focus):
        self.focus = nil
        self.clear(wFocus)

    self.set(found.flags and wReactive)

method trigger(self: GUIContainer, signal: GUISignal) =
  var focus = self.focus
  for widget in self:
    if (widget.flags and wSignal) == wSignal and
        (widget.id == signal.id or widget.id == 0):
      widget.trigger(signal)

      let check = (widget.flags and wFocusCheck) xor 0x30'u16
      if (check and wFocus) == wFocus and widget != focus:
        if check == wFocus:
          if focus != nil:
            focus.focusOut()
            focus.clear(wFocus)

            self.set(focus.flags and wReactive)
          focus = widget
        else:
          widget.focusOut()
          widget.clear(wFocus)

      self.set(widget.flags and wReactive)

  if focus != self.focus:
    self.focus = focus
    self.set(wFocus)
  else:
    self.checkFocus()

method step(self: GUIContainer, back: bool) =
  var widget: GUIWidget = self.focus

  if widget != nil:
    widget.step(back)
    self.set(widget.flags and wReactive)

    if (widget.flags and wFocusCheck) == wFocusCheck: return
    else:
      widget.focusOut()
      widget.clear(wFocus)

      self.set(widget.flags and wReactive)

  while self.stepWidget(back):
    widget = self.focus
    if (widget.flags and 0x0030) == 0x0030:
      widget.step(back)
      self.set(widget.flags and wReactive)

      if (widget.flags and wFocus) == wFocus:
        self.set(wFocus)
        return

  self.focus = nil
  self.clear(wFocus)

method layout(self: GUIContainer) =
  if (self.flags and wDirty) == wDirty:
    self.layout.layout(self)
    self.set(wDrawDirty)

  for widget in self:
    widget.set(self.flags and wDirty)
    if (widget.flags and 0x0C) != 0:
      widget.layout()
      widget.clear(0x0D)

      if (widget.flags and wVisible) == wVisible:
        widget.set(wDraw)
      else:
        zeroMem(addr widget.rect, sizeof(GUIRect))

      self.set(widget.flags and wReactive)

  self.checkFocus()
  self.clear(0x0C)

method hoverOut(self: GUIContainer) =
  var hover: GUIWidget = self.hover
  if hover != nil:
    hover.hoverOut()
    hover.clear(wHover)
    # if is focused check focus
    if hover == self.focus and
        (hover.flags and wFocusCheck) != wFocusCheck:
      hover.focusOut()
      hover.clear(wFocus)
      self.focus = nil

    self.hover = nil
    self.set(hover.flags and wReactive)

method focusOut(self: GUIContainer) =
  var focus: GUIWidget = self.focus
  if focus != nil:
    focus.focusOut()
    focus.clear(wFocus)

    self.focus = nil
    self.set(focus.flags and wReactive)
