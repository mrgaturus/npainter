import nogui/ux/layouts/base
from nogui/builder import widget, controller, child
import nogui/ux/prelude
# Import Controllers
import main/[menu, tools, frame]
import docks, state, dispatch

# ---------------------
# Main Frame Controller
# ---------------------

controller NCMainFrame:
  attributes:
    # Window Stuff
    menu: NCMainMenu
    tools: NCMainTools
    docks: CXDocks
    # NPainter Dispatcher
    dispatch: UXPainterDispatch
    # Main Frame
    {.public.}:
      state: NPainterState
      frame: UXMainFrame

  callback dummy: 
    discard

  proc createFrame: UXMainFrame =
    let
      # Menu, Toolbar and Dock Session
      title = createMenu(self.menu)
      tools = createToolbar(self.tools)
      session = self.docks.session
    mainframe title, mainbody(tools, session)

  new cxnpainter0proof(w, h: int32, checker = 0'i32):
    let state = npainterstate()
    state.engine0proof(w, h, checker)
    # Create Frame Docks
    let
      dispatch = npainterdispatch(state)
      docks = cxdocks(state, dispatch)
    result.state = state
    result.dispatch = dispatch
    result.docks = docks
    # Create Main Frame
    result.menu = ncMainMenu()
    result.tools = ncMainTools(state.tool)
    let frame = result.createFrame()
    result.frame = frame
    # XXX: proof of concept
    docks.proof0arrange()
    state.tool.react[] = ord stBrush
