from nogui/libs/gl import 
  glClear, 
  glClearColor, 
  GL_COLOR_BUFFER_BIT, 
  GL_DEPTH_BUFFER_BIT
from nogui import createApp, executeApp
# Import Main Controller
import ux/views/main/main

proc main() =
  let c = ncMainWindow()
  createApp(1024, 600, nil)
  # Open Window
  executeApp(c.createFrame):
    glClearColor(0.5, 0.5, 0.5, 1.0)
    #glClearColor(0.09019607843137255, 0.10196078431372549, 0.10196078431372549, 1.0)
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

when isMainModule:
  main()