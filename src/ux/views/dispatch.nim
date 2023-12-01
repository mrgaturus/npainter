import nogui, state
import nogui/ux/prelude

# ---------------------------------------------------------
# XXX: XPM Cursor Hack for Default Cursors
# TODO: remove this when native platforms on nogui are done
# ---------------------------------------------------------
import nogui/gui/window
import x11/[x, xlib]
# AzPainter Opaque Cursor
type AzCursor = distinct pointer

{.passL: "-lX11".}
{.compile: "mlk_x11_cursor.c".}
proc azpainter_x11_cursor(dsp: PDisplay, xid: Window, cursor: AzCursor): Cursor {.cdecl, importc.}
# Alternative to codegenDecl
{.emit: "extern const char az_cursor_draw[];".}
{.emit: "extern const char az_cursor_rotate[];".}
let az_cursor_draw {.nodecl, importc.}: AzCursor

proc createAzCursor(buffer: AzCursor): Cursor =
  # Hacky Access to X11 Symbols
  let app = getApp()
  privateAccess(type app[])
  privateAccess(GUIWindow)
  # Lookup Display and Window
  let
    win = getApp().window
    dsp = win.display
    xid = win.xID
  # Create AzPainter Cursor
  azpainter_x11_cursor(dsp, xid, buffer)

# ----------------------------------------------
# NPainter Engine Dispatcher Widget
# XXX: proof of concept
#      i have plans for high-end shortcut editor
# ----------------------------------------------
type AUXCallback = GUICallbackEX[AuxState]

widget UXPainterDispatch:
  attributes:
    {.cursor.}:
      state: NPainterState
    {.public.}:
      fnTools: array[CKPainterTool, AUXCallback]
      fnCanvas: AUXCallback
      fnClear: GUICallback
    # XXX: hacky way to avoid flooding engine events
    #      - This will be solved unifying event/callback queue
    #      - Also allow deferring a callback after polling events/callbacks
    busy: bool
    aux: AuxState
    hold: AUXCallback
    # Canvas Activation
    canvasKey: bool
    drawCursor: Cursor

  # -- Dispatcher Constructor --
  proc register(state: NPainterState) =
    # Canvas Dispatch
    self.fnCanvas = state.canvas.cbDispatch
    self.fnClear = state.canvas.cbClear0proof
    # Tools Dispatch
    self.fnTools[stBrush] = state.brush.cbDispatch
    self.fnTools[stFill] = state.bucket.cbDispatch

  new npainterdispatch(state: NPainterState):
    # XXX: AuxState is Passed by Copy to Callback
    result.aux.busy = addr result.busy
    result.flags = wMouseKeyboard
    # Register States
    result.state = state
    result.register(state)
    # Create Draw Cursor
    result.drawCursor = createAzCursor(az_cursor_draw)

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
      result.click0 = state.key
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
    # Hold Callback
    if aux.first:
      self.hold = fn
    elif self.test(wGrab):
      fn = self.hold
    # TODO: callback-based hotkeys
    elif state.kind == evKeyDown and state.key == 65535:
      force(self.fnClear)
      return
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
    let app = getApp()
    if kind == inHover:
      app.setCursorCustom(self.drawCursor)
    elif kind == outHover:
      app.clearCursor()
