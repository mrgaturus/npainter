from state import GUIState, GUIEvent, GUISignal
import widget, context

const
  wDrawDirty = 0x0400'u16
  wReactive = 0x000F'u16

type
  # GUIContainer, GUILayout and Decorator
  GUILayout* = ref object of RootObj
  GUIContainer* = ref object of GUIWidget
    first, last: GUIWidget  # Iterating / Inserting
    focus, hover: GUIWidget # Cache Pointers
    # Layout and Color
    layout: GUILayout
    color: GUIColor

# LAYOUT ABSTRACT METHOD
method layout*(layout: GUILayout, container: GUIContainer) {.base.} = discard

# CONTAINER PROCS
proc newContainer*(layout: GUILayout): GUIContainer =
  new result
  # GUILayout
  result.layout = layout
  # GUIWidget Handlers
  result.first = nil
  result.last = nil
  result.hover = nil
  result.focus = nil
  # GUIWidget Default Flags
  result.flags = 0x0638
  # Initialize Rect with zeros
  zeroMem(addr result.rect, sizeof GUIRect)

proc add*(container: GUIContainer, widget: GUIWidget) =
  if container.first.isNil:
    container.first = widget
    container.last = widget
  else:
    widget.prev = container.last
    container.last.next = widget

  container.last = widget

# CONTAINER PROCS PRIVATE
iterator items(container: GUIContainer): GUIWidget =
  var current: GUIWidget = container.first
  while current != nil:
    yield current
    current = current.next

proc stepWidget(container: GUIContainer, back: bool): bool =
  if back:
    if container.focus.isNil:
      container.focus = container.last
    else:
      container.focus = container.focus.prev
  else:
    if container.focus.isNil:
      container.focus = container.first
    else:
      container.focus = container.focus.next

  result = not container.focus.isNil

proc checkFocus(container: GUIContainer) =
  var aux: GUIWidget = container.focus
  if aux != nil and (aux.flags and wFocusCheck) != wFocusCheck:
    aux.focusOut()
    aux.flags.clearMask(wFocus)

    container.flags =
      (container.flags and not wFocus.uint16) or (aux.flags and wReactive)
    container.focus = nil

# CONTAINER METHODS
method draw(container: GUIContainer, ctx: ptr GUIContext) =
  var count = 0;

  # Make Decorator current
  ctx.push(addr container.rect, addr container.color)
  # Clear color if it was dirty
  if testMask(container.flags, wDrawDirty):
    container.flags.clearMask(wDrawDirty)
    ctx.clear()
  # Draw Widgets
  for widget in container:
    if (widget.flags and wDraw) == wDraw:
      widget.draw(ctx)
      inc(count)
  # Unmake Decorator current
  ctx.pop()

  if count == 0:
    container.flags.clearMask(wDraw)

method update(container: GUIContainer) =
  var count = 0;

  for widget in container:
    if (widget.flags and wUpdate) == wUpdate:
      widget.update()
      inc(count)

  container.checkFocus()

  if count == 0:
    container.flags.clearMask(wUpdate)

method event(container: GUIContainer, state: ptr GUIState) =
  var aux: GUIWidget = nil

  case state.eventType
  of evMouseMove, evMouseClick, evMouseUnclick, evMouseAxis:
    aux = container.hover

    if (container.flags and wGrab) == wGrab:
      if aux != nil and (aux.flags and wGrab) == wGrab:
        if container.rect.pointOnArea(state.mx, state.my):
          aux.flags.setMask(wHover)
        else:
          aux.flags.clearMask(wHover)
      else:
        container.flags.clearMask(wGrab)
    elif aux.isNil or not aux.rect.pointOnArea(state.mx, state.my):
      if aux != nil:
        aux.hoverOut()
        aux.flags.clearMask(wHover)
        container.flags.setMask(aux.flags and wReactive)

      aux = nil
      for widget in container:
        if (widget.flags and wVisible) == wVisible and
            widget.rect.pointOnArea(state.mx, state.my):
          widget.flags.setMask(wHover)
          container.flags.setMask(wHover)

          aux = widget
          break

      if aux.isNil:
        container.flags.clearMask(wHover)

      container.hover = aux

      if state.eventType == evMouseClick:
        container.flags.setMask(wGrab)
  of evKeyDown, evKeyUp:
    if (container.flags and wFocus) == wFocus:
      aux = container.focus

  if aux != nil:
    aux.event(state)
    if state.eventType < evKeyDown:
      container.flags = (container.flags and not wGrab.uint16) or (
          aux.flags and wGrab)

    var focusAux: GUIWidget = container.focus
    let focusCheck = (aux.flags and wFocusCheck) xor 0x0030'u16

    if focusCheck == wFocus:
      if aux != focusAux and focusAux != nil:
        focusAux.focusOut()
        focusAux.flags.clearMask(wFocus)

        container.flags.setMask(aux.flags and wReactive)
        container.focus = container.hover
      elif focusAux.isNil:
        container.focus = container.hover
        container.flags.setMask(wFocus)
    elif (focusCheck and wFocus) == wFocus or aux != focusAux:
      aux.focusOut()
      aux.flags.clearMask(wFocus)

      if (aux == focusAux):
        container.focus = nil
        container.flags.clearMask(wFocus)

    container.flags.setMask(aux.flags and wReactive)

method trigger(container: GUIContainer, signal: GUISignal) =
  var focusAux = container.focus
  for widget in container:
    if (widget.flags and wSignal) == wSignal and
        (widget.id == signal.id or widget.id == 0):
      widget.trigger(signal)

      let focusCheck = (widget.flags and wFocusCheck) xor 0x0030'u16
      if (focusCheck and wFocus) == wFocus and widget != focusAux:
        if focusCheck == wFocus:
          if focusAux != nil:
            focusAux.focusOut()
            focusAux.flags.clearMask(wFocus)

            container.flags.setMask(focusAux.flags and wReactive)
          focusAux = widget
        else:
          widget.focusOut()
          widget.flags.clearMask(wFocus)

      container.flags.setMask(widget.flags and wReactive)

  if focusAux != container.focus:
    container.focus = focusAux
    container.flags.setMask(wFocus)
  else:
    container.checkFocus()

method step(container: GUIContainer, back: bool) =
  var widget: GUIWidget = container.focus

  if widget != nil:
    widget.step(back)
    container.flags.setMask(widget.flags and wReactive)

    if (widget.flags and wFocusCheck) == wFocusCheck: return
    else:
      widget.focusOut()
      widget.flags.clearMask(wFocus)

      container.flags.setMask(widget.flags and wReactive)

  while container.stepWidget(back):
    widget = container.focus
    if (widget.flags and 0x0030) == 0x0030:
      widget.step(back)
      container.flags.setMask(widget.flags and wReactive)

      if (widget.flags and wFocus) == wFocus:
        container.flags.setMask(wFocus)
        return

  container.focus = nil
  container.flags.clearMask(wFocus)

method layout(container: GUIContainer) =
  if (container.flags and wDirty) == wDirty:
    container.layout.layout(container)
    container.flags.setMask(wDrawDirty)

  for widget in container:
    widget.flags.setMask(container.flags and wDirty)
    if (widget.flags and 0x000C) != 0:
      widget.layout()
      widget.flags.clearMask(0x000D)

      if (widget.flags and wVisible) == wVisible:
        widget.flags.setMask(wDraw)
      else:
        zeroMem(addr widget.rect, sizeof(GUIRect))

      container.flags.setMask(widget.flags and wReactive)

  container.checkFocus()
  container.flags.clearMask(0x000C)

method hoverOut(container: GUIContainer) =
  var aux: GUIWidget = container.hover
  if aux != nil:
    aux.hoverOut()
    aux.flags.clearMask(wHover)
    # if is focused check focus
    if aux == container.focus and
        (aux.flags and wFocusCheck) != wFocusCheck:
      aux.focusOut()
      aux.flags.clearMask(wFocus)
      container.focus = nil

    container.hover = nil
    container.flags.setMask(aux.flags and wReactive)


method focusOut(container: GUIContainer) =
  var aux: GUIWidget = container.focus
  if aux != nil:
    aux.focusOut()
    aux.flags.clearMask(wFocus)

    container.focus = nil
    container.flags.setMask(aux.flags and wReactive)
