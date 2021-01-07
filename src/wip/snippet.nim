import gui/[window, widget, render, event, signal]
import libs/gl

when isMainModule:
  var # Create Basic Widgets
    win = newGUIWindow(1280, 720, nil)
    root: GUIWidget
  # Open Window
  if win.open(root):
    while true:
      win.handleEvents() # Input
      if win.handleSignals(): break
      win.handleTimers() # Timers
      # Render Main Program
      glClearColor(0.5, 0.5, 0.5, 1.0)
      glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
      # Render GUI
      win.render()
  # Close Window
  win.close()