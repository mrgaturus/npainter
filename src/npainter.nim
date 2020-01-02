import libs/gl
import gui/[window, widget, render, container, event, timer]
from gui/builder import signal

signal Example:
  A
  B

type
  Counter = object
    clicked, released: int
  GUIBlank = ref object of GUIWidget
    frame: GUIWidget
    t: GUITimer

proc click(g: ptr Counter, d: pointer) =
  inc(g.clicked)
  pushSignal(ExampleID, msgA, nil, 0)
  echo "Click Count: ", g.clicked

proc release(g: ptr Counter, d: pointer) =
  inc(g.released)
  pushSignal(ExampleID, msgB, nil, 0)
  echo "Released Count: ", g.clicked

method draw*(widget: GUIBlank, ctx: ptr CTXRender) =
  #echo "reached lol"
  var color = if widget.test(wHover):
    GUIColor(r: 0.4, g: 0.4, b: 0.4, a: 1.0)
  elif widget.test(wGrab):
    GUIColor(r: 1.0, g: 0.0, b: 1.0, a: 1.0)
  elif widget.test(wFocus):
    GUIColor(r: 1.0, g: 1.0, b: 0.0, a: 1.0)
  else:
    GUIColor(r: 1.0, g: 1.0, b: 1.0, a: 1.0)

  color(ctx, color)
  fill(ctx, widget.rect)
  widget.clear(wDraw)


method event*(widget: GUIBlank, state: ptr GUIState) =
  #echo "cursor mx: ", state.mx, " cursor my: ", state.my
  if state.eventType == evMouseClick:
    if not isNil(widget.frame) and test(widget.frame, wVisible):
      echo "true"
      widget.clear(wHold)
    else:
      widget.t = newTimer(250)
      widget.set(wFocus or wUpdate)
  elif state.eventType == evMouseRelease:
    if not checkTimer(widget.t):
      widget.clear(wUpdate)
  if not isNil(widget.frame) and not test(widget.frame, wVisible):
    move(widget.frame, state.mx + 5, state.my + 5)

  widget.set(wDraw)

method trigger*(widget: GUIWidget, signal: GUISignal) =
  case ExampleMsg(signal.msg)
  of msgA: echo "Recived A"
  of msgB: echo "Recived B"

method update*(widget: GUIBlank) =
  if checkTimer(widget.t):
    if widget.frame != nil:
      open(widget.frame)
      widget.set(wHold)
    widget.clear(wUpdate)

method handle*(widget: GUIBlank, kind: GUIHandle) =
  echo "handle done: ", kind.repr
  echo "by: ", cast[uint](widget)
  if kind == outHold:
    close(widget.frame)
  widget.set(wDraw)

when isMainModule:
  # Create Counter
  var counter = Counter(
    clicked: 0, 
    released: 0
  )
  # Create a new Window
  let layout = new GUILayout
  var win = newGUIWindow(addr counter, 1024, 600, layout)

  # Create Widgets
  block:
    # A Blank
    var blank1 = new GUIBlank
    blank1.rect = GUIRect(x: 20, y: 20, w: 50, h: 60)
    blank1.signals = {ExampleID}
    blank1.flags = wVisible or wEnabled

    # A Frame
    var blankf = new GUIBlank
    blankf.rect = GUIRect(x: 20, y: 20, w: 50, h: 60)
    blankf.signals = {ExampleID}
    blankf.flags = wVisible or wEnabled

    var blankz = new GUIBlank
    blankf.rect = GUIRect(x: 20, y: 20, w: 50, h: 60)
    blankf.signals = {ExampleID}
    blankf.flags = wVisible or wEnabled

    var frame2 = newGUIContainer(layout, GUIColor(r: 0.0, g: 1.0, b: 1.0, a: 0.5))
    frame2.rect = GUIRect(x: 80, y: 120, w: 100, h: 100)
    frame2.flags = wPopup
    frame2.add(blankf)
    #blankz.frame = frame2

    var frame1 = newGUIContainer(layout, GUIColor(r: 0.0, g: 1.0, b: 1.0, a: 0.5))
    frame1.rect = GUIRect(x: 80, y: 120, w: 100, h: 100)
    frame1.flags = wPopup
    frame1.add(blankz)

    blank1.frame = frame1

    win.add(blank1)

    blank1 = new GUIBlank
    blank1.rect = GUIRect(x: 100, y: 80, w: 50, h: 60)
    blank1.signals = {ExampleID}
    blank1.flags = wVisible or wEnabled

    # A Frame
    blankf = new GUIBlank
    blankf.rect = GUIRect(x: 20, y: 20, w: 50, h: 60)
    blankf.signals = {ExampleID}
    blankf.flags = wVisible or wEnabled
    
    var frame = newGUIContainer(layout, GUIColor(r: 1.0, g: 1.0, b: 0.0, a: 0.5))
    frame.rect = GUIRect(x: 60, y: 100, w: 100, h: 100)
    #frame.add(blankf)
    frame.flags = wPopup
    blank1.frame = frame

    win.add(blank1)

  # MAIN LOOP
  var running = win.exec()
  while running:
    # Render Main Program
    glClearColor(0.5, 0.5, 0.5, 1.0)
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
    # Render GUI
    running = win.tick()
  # Close Window and Dispose Resources
  win.exit()
