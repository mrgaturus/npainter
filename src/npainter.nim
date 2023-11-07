from nogui/libs/gl import 
  glClear, 
  glClearColor, 
  GL_COLOR_BUFFER_BIT, 
  GL_DEPTH_BUFFER_BIT
from nogui import createApp, executeApp
# Import Main Controller
import ux/views/main/main

proc main() =
  createApp(1280, 720, nil)
  let c = ncMainWindow()
  # Open Window
  executeApp(c.frame):
    #glClearColor(0.25, 0.25, 0.25, 1.0)
    glClearColor(0.09019607843137255, 0.10196078431372549, 0.10196078431372549, 1.0)
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

when isMainModule:
  main()