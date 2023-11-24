from nogui import windowSize
import nogui/ux/prelude
import state

# ------------------------------------------
# NPainter Engine Dispatcher Widget
# XXX: proof of concept
#      i have plans for high-end shortcut editor
# ------------------------------------------
type AUXCallback = GUICallbackEX[AuxState]

widget UXPainterDispatch:
  attributes:
    {.cursor.}:
      state: NPainterState
    {.public.}:
      fnTools: array[CKPainterTool, AUXCallback]
      fnCanvas: AUXCallback
    # XXX: hacky way to avoid flooding engine events
    #      - This will be solved unifying event/callback queue
    #      - Also allow deferring a callback after polling events/callbacks
    busy: bool
    aux: AuxState
    # Canvas Activation
    canvasKey: bool

  # -- Dispatcher Constructor --
  proc register(state: NPainterState) =
    # Canvas Dispatch
    self.fnCanvas = state.canvas.cbDispatch

  new npainterdispatch(state: NPainterState):
    # XXX: AuxState is Passed by Copy to Callback
    result.aux.busy = addr result.busy
    result.flags = wMouseKeyboard
    # Register States
    result.state = state
    result.register(state)

  # -- Dispatcher Event --
  proc prepareAux(state: ptr GUIState): ptr AuxState =
    result = addr self.aux
    # Prepare Cursor Event
    result.x = state.px
    result.y = state.py
    result.pressure = state.pressure
    # Prepare First Cursor Event
    let first = state.kind == evCursorClick
    result.first = first
    if first:
      result.x0 = state.px
      result.y0 = state.py
      result.mods = state.mods
    # Bind Common Handle
    result.flags = self.flags
    result.kind = state.kind
    result.key = state.key

  proc canvasAux(state: ptr GUIState): bool =
    let key = state.key
    result = self.canvasKey
    # Check Canvas Key
    # 32 -> spacebar
    # XXX: native platform rework will improve this
    case state.kind
    of evKeyDown: result = result or (key == 32)
    of evKeyUp: result = result and (key != 32)
    else: discard
    # Replace Current Canvas Check
    self.canvasKey = result

  method event(state: ptr GUIState) =
    let
      id = peek(self.state.tool)
      tool = CKPainterTool id[]
      aux = self.prepareAux(state)
    # Lookup Dispatcher
    var fn = self.fnTools[tool]
    if self.canvasAux(state):
      fn = self.fnCanvas
    # Dispatch Event
    force(fn, aux)

  method layout =
    let
      engine {.cursor.} = self.state.engine
      m = engine.canvas.affine
      size = getApp().windowSize()
    # Set Viewport Size
    m.vw = size.w
    m.vh = size.h
    # Update View
    self.state.canvas.update()

  # -- Dispatcher Cursor Clearing --
  method handle(kind: GUIHandle) =
    discard
