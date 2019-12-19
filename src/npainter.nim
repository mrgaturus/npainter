import libs/gl
import gui/[window, widget, render, container, event]
from gui/builder import signal

signal Example:
  A
  B

type
  ClickData = object
    x, y: int32
  Counter = object
    clicked, released: int
  GUIBlank = ref object of GUIWidget
    color: GUIColor
    colorn: GUIColor
    colorf: GUIColor

proc click(g: ptr Counter, d: pointer) =
  inc(g.clicked)
  pushSignal(ExampleID, msgA, nil, 0)
  echo "Click Count: ", g.clicked

proc release(g: ptr Counter, d: pointer) =
  inc(g.released)
  echo "Released Count: ", g.clicked
  if g.released > 10:
    pushSignal(WindowID, msgTerminate, nil, 0)

method draw*(widget: GUIBlank, ctx: ptr CTXRender) =
  if widget.any(wHover or wGrab):
    echo sizeof(widget.signals)
    color(ctx, widget.color)
  elif widget.test(wFocus):
    color(ctx, widget.colorf)
  else:
    color(ctx, widget.colorn)
  fill(ctx, widget.rect)
  widget.clear(wDraw)

method event*(widget: GUIBlank, state: ptr GUIState) =
  if state.eventType == evMouseClick:
    widget.set(wGrab)
    pushCallback(click, nil, 0)
  elif state.eventType == evMouseRelease: 
    widget.clear(wGrab)
    pushCallback(release, nil, 0)
  block:
    var click = ClickData(x: state.mx, y: state.my)
    pushSignal(ExampleID, msgB, addr click, sizeof(ClickData))

method trigger*(widget: GUIWidget, signal: GUISignal) =
  case ExampleMsg(signal.msg)
  of msgA: echo "Recived A"
  of msgB:
    let data = signal.data.convert(ClickData) 
    echo "Recived B: ", data.x, " ", data.y

when isMainModule:
  # Create Counter
  var counter = Counter(
    clicked: 0, 
    released: 0
  )
  # Create a new Window
  let layout = new GUILayout
  var win = newGUIWindow(addr counter, 1280, 720, layout)

  # Create Widgets
  block:
    # A Blank
    var blank = new GUIBlank
    blank.rect = GUIRect(x: 20, y: 20, w: 50, h: 60)
    blank.color = GUIColor(r: 1.0, g: 0.0, b: 1.0, a: 1.0)
    blank.colorn = GUIColor(r: 1.0, g: 1.0, b: 1.0, a: 1.0)
    blank.colorf = GUIColor(r: 1.0, g: 1.0, b: 0.0, a: 1.0)
    blank.signals = {ExampleID}
    blank.flags = wVisible or wEnabled or wSignal
    win.addWidget(blank)

    blank = new GUIBlank
    blank.rect = GUIRect(x: 100, y: 80, w: 50, h: 60)
    blank.color = GUIColor(r: 1.0, g: 0.0, b: 1.0, a: 1.0)
    blank.colorn = GUIColor(r: 1.0, g: 1.0, b: 1.0, a: 1.0)
    blank.colorf = GUIColor(r: 1.0, g: 1.0, b: 0.0, a: 1.0)
    blank.flags = wVisible or wEnabled

    win.addWidget(blank)
    # A Frame
    blank = new GUIBlank
    blank.rect = GUIRect(x: 20, y: 20, w: 50, h: 60)
    blank.color = GUIColor(r: 1.0, g: 0.0, b: 1.0, a: 1.0)
    blank.colorn = GUIColor(r: 1.0, g: 1.0, b: 1.0, a: 1.0)
    blank.colorf = GUIColor(r: 1.0, g: 1.0, b: 0.0, a: 1.0)
    blank.signals = {ExampleID}
    blank.flags = wVisible or wEnabled or wSignal

    var frame = win.addFrame(layout, GUIColor(r: 0.0, g: 1.0, b: 1.0, a: 0.5))
    frame.rect = GUIRect(x: 110, y: 150, w: 100, h: 100)
    frame.add(blank)
    # A Frame
    blank = new GUIBlank
    blank.rect = GUIRect(x: 20, y: 20, w: 50, h: 60)
    blank.color = GUIColor(r: 1.0, g: 0.0, b: 1.0, a: 1.0)
    blank.colorn = GUIColor(r: 1.0, g: 1.0, b: 1.0, a: 1.0)
    blank.colorf = GUIColor(r: 1.0, g: 1.0, b: 0.0, a: 1.0)
    blank.signals = {ExampleID}
    blank.flags = wVisible or wEnabled or wSignal
    
    frame = win.addFrame(layout, GUIColor(r: 1.0, g: 1.0, b: 0.0, a: 0.5))
    frame.rect = GUIRect(x: 60, y: 100, w: 100, h: 100)
    frame.add(blank)

  # MAIN LOOP
  var running = win.exec()
  while running:
    win.handleEvents()
    running = win.handleTick()
    
    # Render Main Program
    glClearColor(0.5, 0.5, 0.5, 1.0)
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

    # Render GUI
    win.render()

  # Close Window and Dispose Resources
  win.exit()
