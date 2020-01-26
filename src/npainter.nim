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

proc click*(g: ptr Counter, d: pointer) =
  inc(g.clicked)
  pushSignal(ExampleID, msgA, nil, 0)
  echo "Click Count: ", g.clicked

proc release*(g: ptr Counter, d: pointer) =
  inc(g.released)
  pushSignal(ExampleID, msgB, nil, 0)
  echo "Released Count: ", g.clicked

method draw*(widget: GUIBlank, ctx: ptr CTXRender) =
  #echo "reached lol"
  ctx.push(widget.rect)
  let color = # Test Color
    if widget.test(wHover): 0xAA252525'u32
    elif widget.test(wGrab): 0xAAFF00FF'u32
    elif widget.test(wFocus): 0xAAFFFF00'u32
    else: 0xAAFFFFFF'u32

  ctx.color = color
  fill(ctx, widget.rect)
  ctx.color = 0xEECCCCCC'u32
  rectangle(ctx, widget.rect, 1)
  ctx.pop()
  # Rect Test
  block:
    var rect = widget.rect
    rect.x += rect.w div 2
    rect.y += rect.h div 2
    ctx.push(rect)
    ctx.color = 0xFF000000'u32
    triangle(ctx, widget.rect, toLEFT)
    ctx.pop()
  ctx.color = 0xAACCCCCC'u32
  triangle(ctx, widget.rect, toDown)
  ctx.pop()


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
  #echo "handle done: ", kind.repr
  #echo "by: ", cast[uint](widget)
  if kind == outHold: close(widget.frame)

when isMainModule:
  # Create Counter
  var counter = Counter(
    clicked: 0, 
    released: 0
  )
  # Create a new Window
  var win: GUIWindow
  # Create Widgets
  block:
    # Create two blanks
    var
      sub, blank: GUIBlank
      con: GUIContainer
    # Initialize Root
    let root = new GUIContainer
    root.rect.w = 1024
    root.rect.h = 600
    root.color = 0xFF000000'u32
    root.flags = wStandard or wOpaque
    # --- Blank #1 ---
    blank = new GUIBlank
    blank.flags = wStandard
    blank.rect = GUIRect(x: 20, y: 150, w: 100, h: 100)
    root.add(blank)
    # --- Blank #2 ---
    blank = new GUIBlank
    blank.flags = wStandard
    blank.rect = GUIRect(x: 20, y: 20, w: 100, h: 100)
    block: # Menu Blank #2
      con = new GUIContainer
      con.color = 0xAA637a90'u32
      con.flags = wPopup
      con.rect.w = 200
      con.rect.h = 100
      # Sub-Blank #1
      sub = new GUIBlank
      sub.flags = wStandard
      sub.rect = GUIRect(x: 10, y: 10, w: 20, h: 20)
      block: # Sub Menu #1
        let subcon = new GUIContainer
        subcon.color = 0xAA676466'u32
        subcon.flags = wPopup
        subcon.rect.w = 200
        subcon.rect.h = 80
        # Sub-sub blank 1#
        var subsub = new GUIBlank
        subsub.flags = wStandard
        subsub.rect = GUIRect(x: 10, y: 10, w: 180, h: 20)
        subcon.add(subsub)
        # Sub-sub blank 2#
        subsub = new GUIBlank
        subsub.flags = wStandard
        subsub.rect = GUIRect(x: 10, y: 40, w: 180, h: 20)
        subcon.add(subsub)
        # Add to Sub
        sub.frame = subcon
      con.add(sub)
      # Sub-Blank #2
      sub = new GUIBlank
      sub.flags = wStandard
      sub.rect = GUIRect(x: 40, y: 10, w: 20, h: 20)
      block: # Sub Menu #1
        let subcon = new GUIContainer
        subcon.color = 0xFFbdb88f'u32
        subcon.flags = wEnabled
        subcon.rect.w = 200
        subcon.rect.h = 80
        # Sub-sub blank 1#
        var subsub = new GUIBlank
        subsub.flags = wStandard
        subsub.rect = GUIRect(x: 10, y: 10, w: 180, h: 20)
        subcon.add(subsub)
        # Sub-sub blank 2#
        subsub = new GUIBlank
        subsub.flags = wStandard
        subsub.rect = GUIRect(x: 10, y: 40, w: 180, h: 20)
        subcon.add(subsub)
        # Add to Sub
        sub.frame = subcon
      con.add(sub)
      # Add Blank 2
      blank.frame = con
    root.add(blank)
    # Creates new Window
    win = newGUIWindow(root, addr counter)
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
