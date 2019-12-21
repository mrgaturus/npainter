import libs/gl
import gui/[window, widget, render, container, event]
from gui/builder import signal

signal Example:
  A
  B

type
  Counter = object
    clicked, released: int
  GUIBlank = ref object of GUIWidget
    frame: GUIWidget
    color: GUIColor
    colorn: GUIColor
    colorf: GUIColor

proc click(g: ptr Counter, d: pointer) =
  inc(g.clicked)
  pushSignal(ExampleID, msgA, nil, 0)
  echo "Click Count: ", g.clicked

proc release(g: ptr Counter, d: pointer) =
  inc(g.released)
  pushSignal(ExampleID, msgB, nil, 0)
  echo "Released Count: ", g.clicked

method draw*(widget: GUIBlank, ctx: ptr CTXRender) =
  if widget.any(wHover or wGrab):
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
    if widget.frame != nil:
      if test(widget.frame, wFramed):
        pushSignal(FrameID, msgClose, addr widget.frame, sizeof(GUIWidget))
      else:
        widget.frame.rect.x = widget.rect.x
        widget.frame.rect.y = widget.rect.y + widget.rect.h
        pushSignal(FrameID, msgOpen, addr widget.frame, sizeof(GUIWidget))
    widget.set(wFocus)
    pushCallback(click, nil, 0)
  elif state.eventType == evMouseRelease: 
    widget.clear(wGrab)
    pushCallback(release, nil, 0)
  widget.set(wDraw)
 # block:
    #var click = ClickData(x: state.mx, y: state.my)
    #pushSignal(ExampleID, msgB, addr click, sizeof(ClickData))

method trigger*(widget: GUIWidget, signal: GUISignal) =
  case ExampleMsg(signal.msg)
  of msgA: echo "Recived A"
  of msgB: echo "Recived B"

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
    var blank1 = new GUIBlank
    blank1.rect = GUIRect(x: 20, y: 20, w: 50, h: 60)
    blank1.color = GUIColor(r: 1.0, g: 0.0, b: 1.0, a: 1.0)
    blank1.colorn = GUIColor(r: 1.0, g: 1.0, b: 1.0, a: 1.0)
    blank1.colorf = GUIColor(r: 1.0, g: 1.0, b: 0.0, a: 1.0)
    blank1.signals = {ExampleID}
    blank1.flags = wVisible or wEnabled or wSignal

    # A Frame
    var blankf = new GUIBlank
    blankf.rect = GUIRect(x: 20, y: 20, w: 50, h: 60)
    blankf.color = GUIColor(r: 1.0, g: 0.0, b: 1.0, a: 1.0)
    blankf.colorn = GUIColor(r: 1.0, g: 1.0, b: 1.0, a: 1.0)
    blankf.colorf = GUIColor(r: 1.0, g: 1.0, b: 0.0, a: 1.0)
    blankf.signals = {ExampleID}
    blankf.flags = wVisible or wEnabled or wSignal

    var frame = newGUIContainer(layout, GUIColor(r: 0.0, g: 1.0, b: 1.0, a: 0.5))
    frame.rect = GUIRect(x: 80, y: 120, w: 100, h: 100)
    frame.add(blankf)
    frame.flags = wDirty or wVisible or wEnabled
    blank1.frame = frame

    win.addWidget(blank1)

    blank1 = new GUIBlank
    blank1.rect = GUIRect(x: 100, y: 80, w: 50, h: 60)
    blank1.color = GUIColor(r: 1.0, g: 0.0, b: 1.0, a: 1.0)
    blank1.colorn = GUIColor(r: 1.0, g: 1.0, b: 1.0, a: 1.0)
    blank1.colorf = GUIColor(r: 1.0, g: 1.0, b: 0.0, a: 1.0)
    blank1.signals = {ExampleID}
    blank1.flags = wVisible or wEnabled or wSignal

    # A Frame
    blankf = new GUIBlank
    blankf.rect = GUIRect(x: 20, y: 20, w: 50, h: 60)
    blankf.color = GUIColor(r: 1.0, g: 0.0, b: 1.0, a: 1.0)
    blankf.colorn = GUIColor(r: 1.0, g: 1.0, b: 1.0, a: 1.0)
    blankf.colorf = GUIColor(r: 1.0, g: 1.0, b: 0.0, a: 1.0)
    blankf.signals = {ExampleID}
    blankf.flags = wVisible or wEnabled or wSignal
    
    frame = newGUIContainer(layout, GUIColor(r: 1.0, g: 1.0, b: 0.0, a: 0.5))
    frame.rect = GUIRect(x: 60, y: 100, w: 100, h: 100)
    frame.add(blankf)
    frame.flags = wDirty or wVisible or wEnabled
    blank1.frame = frame

    win.addWidget(blank1)

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
