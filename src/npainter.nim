import libs/gl
import gui/[window, widget, context, container]

type
  GUIBlank = ref object of GUIWidget
    color: GUIColor

method draw*(widget: GUIBlank, ctx: ptr GUIContext) =
  clip(ctx, addr widget.rect)
  color(ctx, addr widget.color)
  clear(ctx)
  clearMask(widget.flags, wDraw)

when isMainModule:
  # Create a new Window
  let layout = new GUILayout
  var win = newGUIWindow(1280, 720, layout)

  # Create Widgets
  block:
    let color = GUIColor(r: 1.0, g: 0.0, b: 1.0, a: 1.0)
    # A Blank
    var blank = new GUIBlank
    blank.rect = GUIRect(x: 20, y: 20, w: 50, h: 60)
    blank.color = color
    blank.flags = wVisible
    win.addWidget(blank)
    # A Frame
    var frame = win.addFrame(layout, GUIColor(r: 0.0, g: 1.0, b: 1.0, a: 1.0))
    frame.rect = GUIRect(x: 50, y: 100, w: 100, h: 100)
    frame.add(blank)
    # A Frame
    frame = win.addFrame(layout, GUIColor(r: 1.0, g: 1.0, b: 1.0, a: 1.0))
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
