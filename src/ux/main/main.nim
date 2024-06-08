import menu, tools, ../../containers/main
from nogui/builder import widget, controller, child
import nogui/ux/prelude
# Import Controllers
import ../[docks, state, dispatch]

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
      dispatch = npainterdispatch(self.state)
      # Menu, Toolbar and Dock Session
      title = createMenu(self.menu)
      tools = createToolbar(self.tools)
      session = self.docks.session
    # Return Main Frame
    mainframe title, mainbody(tools, dispatch, session) 

  new cxnpainter0proof(w, h: int32, checker = 0'i32):
    let state = npainterstate()
    result.state = state
    # Initialize Engine
    state.engine0proof(w, h, checker)
    # Create Frame Docks
    let docks = cxdocks(result.state)
    result.docks = docks
    # Create Main Frame Stuff
    result.menu = ncMainMenu()
    result.tools = ncMainTools(state.tool)
    # Create Main Frame
    let frame = result.createFrame()
    result.frame = frame

    # XXX: proof of concept
    docks.proof0arrange()
    frame.set(wDirty)
    # XXX: default to brush
    state.tool.react[] = ord stBrush
