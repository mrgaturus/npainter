import nogui/ux/layouts/base
from nogui/builder import widget, controller, child
import nogui/core/shortcut
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

  callback cbSelectTool: 
    let tool = self.state.tool.peek[]
    # Select Dock and Dispatch
    self.docks.select(tool)
    self.dispatch.select(tool)
    self.state.engine.tool = tool

  proc createFrame: UXMainFrame =
    let
      # Menu, Toolbar and Dock Session
      title = createMenu(self.menu)
      tools = createToolbar(self.tools)
      session = self.docks.session
    mainframe title, mainbody(tools, session)

  proc proof0shortcuts() =
    let shorts = getWindow().shorts
    let state {.cursor.} = self.state
    shorts[].register shortcut(state.layers.cbClearLayer, NK_Delete)
    # XXX: for now both ctrl + shift + z or ctrl + y works
    #      but one will be the default winner
    shorts[].register shortcut(state.cbUndo, NK_Z + {Mod_Control})
    shorts[].register shortcut(state.cbRedo, NK_Z + {Mod_Control, Mod_Shift})
    shorts[].register shortcut(state.cbRedo, NK_Y + {Mod_Control})

  new cxnpainter0proof(w, h: int32, checker = 0'i32):
    let state = npainterstate0proof(w, h, checker)
    state.tool.cb = result.cbSelectTool
    state.tool.react[] = stBrush
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
    state.proof0default()
    docks.proof0arrange()
    result.proof0shortcuts()
