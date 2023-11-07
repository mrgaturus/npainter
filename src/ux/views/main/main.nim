import menu, tools, ../../containers/main
from nogui/builder import widget, controller, child
import nogui/ux/prelude
# Import Controllers
import ../[docks, state]

widget UXMainDummy:
  attributes:
    color: uint32

  new dummy(w, h: int16): 
    result.metrics.minW = w
    result.metrics.minH = h
    result.color = 0xFFFFFFFF'u32

  new dummy():
    discard

  method layout =
    for w in forward(self.first):
      let m = addr w.metrics
      m.h = m.minH

  method draw(ctx: ptr CTXRender) =
    ctx.color self.color
    ctx.fill rect(self.rect)

# ---------------------
# Main Frame Controller
# ---------------------

controller NCMainFrame:
  attributes:
    state: NPainterState
    # Window Stuff
    menu: NCMainMenu
    tools: NCMainTools
    docks: CXDocks
    # Main Frame
    {.public.}:
      frame: UXMainFrame

  callback dummy: 
    discard

  proc createFrame: UXMainFrame =
    let
      title = createMenu(self.menu)
      tools = createToolbar(self.tools)
      session = self.docks.session
    # Return Main Frame
    mainframe title, mainbody(tools, dummy(), session)

  new ncMainWindow():
    result.state = npainterstate()
    # Create Main Frame Stuff
    result.menu = ncMainMenu()
    result.tools = ncMainTools()
    # Create Docks
    let docks = cxdocks(result.state)
    result.docks = docks
    # Create Main Frame
    let frame = result.createFrame()
    docks.proof0arrange()
    frame.set(wDirty)
    result.frame = frame
