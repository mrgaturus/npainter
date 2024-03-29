from nogui/libs/gl import 
  glClear, 
  glClearColor, 
  GL_COLOR_BUFFER_BIT, 
  GL_DEPTH_BUFFER_BIT
from nogui/pack import folders
from nogui import createApp, executeApp
# Import Main Controller
import ux/views/main/main
# Import Engine Controller
from ux/views/state import engine0proof
import ux/views/state/engine

folders:
  "canvas" -> "glsl"

proc main() =
  createApp(1280, 720, nil)
  let c = ncMainWindow()
  # Create Proof Engine
  c.state.engine0proof(1920, 1080)
  let engine = c.state.engine
  # Open Window
  executeApp(c.frame):
    #glClearColor(0.25, 0.25, 0.25, 1.0)
    glClearColor(0.09019607843137255, 0.10196078431372549, 0.10196078431372549, 1.0)
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
    # Render NPainter
    engine.renderGL()

when isMainModule:
  main()
