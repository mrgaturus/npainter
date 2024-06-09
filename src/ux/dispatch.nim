import nogui, state
import nogui/core/shortcut
import nogui/ux/[prelude, pivot]

# ---------------------------------
# NPainter Engine Dispatcher Widget
# ---------------------------------

widget UXPainterDispatch:
  attributes:
    {.cursor.}:
      state: NPainterState
    {.public.}:
      cbTools: array[CKPainterTool, GUICallback]
      cbCanvas: GUICallback
    hold: GUICallback
    holdCanvas: bool
    # Keyboard Watcher
    keyWatch: GUIObserver

  callback keyCapture:
    let
      engine {.cursor.} = self.state.engine
      state0 = addr engine.state0
      state = engine.state
    # Capture Key State
    state0[].capture(state)

  # -- Dispatcher Constructor --
  proc register(state: NPainterState) =
    self.cbCanvas = state.canvas.cbDispatch
    self.cbTools[stBrush] = state.brush.cbDispatch
    self.cbTools[stFill] = state.bucket.cbDispatch

  new npainterdispatch(state: NPainterState):
    result.flags = {wMouse}
    # Register States
    result.state = state
    result.register(state)
    # Register Key Capture Observer
    let obs = observer(result.keyCapture, {evKeyDown, evKeyUp})
    getWindow().observers[].register(obs)

  proc canvasAux(state: ptr GUIState): bool =
    let
      key = state.key
      spaced = key == NK_Space
    result = self.holdCanvas
    # Check Canvas Key
    case state.kind
    of evKeyDown: result = result or spaced
    of evKeyUp: result = result and not spaced
    else: discard
    # Replace Canvas Check
    self.holdCanvas = result

  method event(state: ptr GUIState) =
    let
      s {.cursor.} = self.state
      id = peek(s.tool)
      tool = CKPainterTool id[]
    # Capture Pivot
    let s0 = addr s.engine.state0
    s0[].capture(state)
    # Lookup Dispatcher
    var cb = self.cbTools[tool]
    if self.canvasAux(state):
      cb = self.cbCanvas
    # Hold Tool Callback
    if state.kind == evCursorClick:
      self.hold = cb
    elif self.test(wGrab):
      cb = self.hold
    # TODO: callback-based hotkeys
    elif state.kind == evKeyDown and state.key == NK_Delete:
      force(s.layers.cbClearLayer)
      return
    # Dispatch Event
    force(cb)

  method layout =
    let
      engine {.cursor.} = self.state.engine
      m = engine.canvas.affine
      size = getWindow().rect
    # Set Viewport Size
    m.vw = size.w
    m.vh = size.h
    # Update View
    self.state.canvas.update()

  # -- Dispatcher Cursor Clearing --
  method handle(reason: GUIHandle) =
    #let app = getApp()
    if reason == inHover: discard
    elif reason == outHover: discard
