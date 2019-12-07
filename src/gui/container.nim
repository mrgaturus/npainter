from state import GUIState, GUIEvent, GUISignal
import widget, context

const
  wDrawDirty = 0x0400'u16
  # Flags Combinations
  wReactive = 0x000F'u16
  wFocusCheck = 0x0070'u16

type
  # GUIContainer, GUILayout and Decorator
  GUILayout* = ref object of RootObj
  GUIContainer* = ref object of GUIWidget
    # Iterating / Inserting
    wFirst, wLast: GUIWidget
    # Cache Pointers
    wFocus, wHover: GUIWidget
    color: GUIColor
    layout: GUILayout

# LAYOUT ABSTRACT METHOD
method layout*(layout: GUILayout, container: GUIContainer) {.base.} = discard

# CONTAINER PROCS
proc newContainer*(layout: GUILayout): GUIContainer =
  new result
  # GUILayout
  result.layout = layout
  # GUIWidget Handlers
  result.wFirst = nil
  result.wLast = nil
  result.wHover = nil
  result.wFocus = nil
  # GUIWidget Default Flags
  result.flags = 0x0638
  # Initialize Rect with zeros
  zeroMem(addr result.rect, sizeof GUIRect)

proc add*(container: GUIContainer, widget: GUIWidget) =
  if container.wFirst.isNil:
    container.wFirst = widget
    container.wLast = widget
  else:
    widget.wPrev = container.wLast
    container.wLast.wNext = widget

  container.wLast = widget

# CONTAINER PROCS PRIVATE
iterator items(container: GUIContainer): GUIWidget =
  var wCurrent: GUIWidget = container.wFirst
  while wCurrent != nil:
    yield wCurrent
    wCurrent = wCurrent.wNext

proc stepWidget(container: GUIContainer, back: bool): bool =
  if back:
    if container.wFocus.isNil:
      container.wFocus = container.wLast
    else:
      container.wFocus = container.wFocus.wPrev
  else:
    if container.wFocus.isNil:
      container.wFocus = container.wFirst
    else:
      container.wFocus = container.wFocus.wNext

  result = not container.wFocus.isNil

proc checkFocus(container: GUIContainer) =
  var wAux: GUIWidget = container.wFocus
  if wAux != nil and (wAux.flags and wFocusCheck) != wFocusCheck:
    wAux.focusOut()
    wAux.flags.clearMask(wFocus)

    container.flags =
      (container.flags and not wFocus.uint16) or (wAux.flags and wReactive)
    container.wFocus = nil

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
  var wAux: GUIWidget = nil

  case state.eventType
  of evMouseMove, evMouseClick, evMouseUnclick, evMouseAxis:
    wAux = container.wHover

    if (container.flags and wGrab) == wGrab:
      if wAux != nil and (wAux.flags and wGrab) == wGrab:
        if container.rect.pointOnArea(state.mx, state.my):
          wAux.flags.setMask(wHover)
        else:
          wAux.flags.clearMask(wHover)
      else:
        container.flags.clearMask(wGrab)
    elif wAux.isNil or not wAux.rect.pointOnArea(state.mx, state.my):
      if wAux != nil:
        wAux.hoverOut()
        wAux.flags.clearMask(wHover)
        container.flags.setMask(wAux.flags and wReactive)

      wAux = nil
      for widget in container:
        if (widget.flags and wVisible) == wVisible and
            widget.rect.pointOnArea(state.mx, state.my):
          widget.flags.setMask(wHover)
          container.flags.setMask(wHover)

          wAux = widget
          break

      if wAux.isNil:
        container.flags.clearMask(wHover)

      container.wHover = wAux

      if state.eventType == evMouseClick:
        container.flags.setMask(wGrab)
  of evKeyDown, evKeyUp:
    if (container.flags and wFocus) == wFocus:
      wAux = container.wFocus

  if wAux != nil:
    wAux.event(state)
    if state.eventType < evKeyDown:
      container.flags = (container.flags and not wGrab.uint16) or (
          wAux.flags and wGrab)

    var focusAux: GUIWidget = container.wFocus
    let focusCheck = (wAux.flags and wFocusCheck) xor 0x0030'u16

    if focusCheck == wFocus:
      if wAux != focusAux and focusAux != nil:
        focusAux.focusOut()
        focusAux.flags.clearMask(wFocus)

        container.flags.setMask(wAux.flags and wReactive)
        container.wFocus = container.wHover
      elif focusAux.isNil:
        container.wFocus = container.wHover
        container.flags.setMask(wFocus)
    elif (focusCheck and wFocus) == wFocus or wAux != focusAux:
      wAux.focusOut()
      wAux.flags.clearMask(wFocus)

      if (wAux == focusAux):
        container.wFocus = nil
        container.flags.clearMask(wFocus)

    container.flags.setMask(wAux.flags and wReactive)

method trigger(container: GUIContainer, signal: GUISignal) =
  var focusAux = container.wFocus
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

  if focusAux != container.wFocus:
    container.wFocus = focusAux
    container.flags.setMask(wFocus)
  else:
    container.checkFocus()

method step(container: GUIContainer, back: bool) =
  var widget: GUIWidget = container.wFocus

  if widget != nil:
    widget.step(back)
    container.flags.setMask(widget.flags and wReactive)

    if (widget.flags and wFocusCheck) == wFocusCheck: return
    else:
      widget.focusOut()
      widget.flags.clearMask(wFocus)

      container.flags.setMask(widget.flags and wReactive)

  while container.stepWidget(back):
    widget = container.wFocus
    if (widget.flags and 0x0030) == 0x0030:
      widget.step(back)
      container.flags.setMask(widget.flags and wReactive)

      if (widget.flags and wFocus) == wFocus:
        container.flags.setMask(wFocus)
        return

  container.wFocus = nil
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
  var wAux: GUIWidget = container.wHover
  if wAux != nil:
    wAux.hoverOut()
    wAux.flags.clearMask(wHover)
    # if is focused check focus
    if wAux == container.wFocus and
        (wAux.flags and wFocusCheck) != wFocusCheck:
      wAux.focusOut()
      wAux.flags.clearMask(wFocus)
      container.wFocus = nil

    container.wHover = nil
    container.flags.setMask(wAux.flags and wReactive)


method focusOut(container: GUIContainer) =
  var wAux: GUIWidget = container.wFocus
  if wAux != nil:
    wAux.focusOut()
    wAux.flags.clearMask(wFocus)

    container.wFocus = nil
    container.flags.setMask(wAux.flags and wReactive)
