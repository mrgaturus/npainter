import nogui, state
import nogui/core/shortcut
import nogui/ux/[prelude, pivot]
import nogui/ux/layouts/base

# ---------------------------------
# NPainter Engine Dispatcher Widget
# TODO: high end shortcuts modifiers
# ---------------------------------

widget UXPainterDispatch:
  attributes:
    tools: array[CKPainterTool, GUIWidget]
    keyWatch: GUIObserver
    dummy: GUIWidget
    # Dispatch State
    {.cursor.}:
      state: NPainterState
      engine: NPainterEngine
      [slot0, slot]: GUIWidget
    # TODO: high end shotcuts modifiers
    spaced: bool

  # -- Dispatcher Selector --
  proc select(widget: GUIWidget) =
    let slot {.cursor.} = self.slot
    if widget == slot: return
    # Handle Select Changes
    slot.vtable.handle(slot, outFrame)
    widget.vtable.handle(widget, inFrame)
    # Replace Current Slot
    widget.flags = {wMouse}
    self.slot = widget

  # -- Dispatcher Register --
  proc capture(state: ptr GUIState) =
    let
      dummy {.cursor.} = self.dummy
      engine {.cursor.} = self.engine
      state0 = addr engine.pivot
    # Capture Key State
    state0[].capture(state)
    # Decide Painter Dispatch
    # TODO: high end shotcuts modifiers
    let
      id = CKPainterTool self.state.tool.peek[]
      spaced = state.key == NK_Space
    var slot = self.tools[id]
    self.slot0 = slot
    # XXX: proof of concept space switching
    if spaced and state.kind == evKeyDown:
      self.spaced = true
    elif spaced and state.kind == evKeyUp:
      self.spaced = false
    # Decide Canvas Dispatch
    if self.spaced:
      slot = self.tools[stView]
    elif isNil(slot):
      slot = dummy
    # Select Canvas Dispatch
    if not dummy.test(wFocus):
      self.select(slot)

  callback keyCapture:
    let state = getApp().state
    self.capture(state)

  proc register(state: NPainterState) =
    let dummy = dummy()
    self.dummy = dummy
    self.slot = dummy
    # Configure Dummy as Focus Stealer
    dummy.flags = {wVisible, wKeyboard}
    # Initialize Dispatch Widgets
    self.tools[stBrush] = uxbrushdispatch(state.brush)
    self.tools[stFill] = uxbucketdispatch(state.bucket)
    self.tools[stView] = uxcanvasdispatch(state.canvas)
    # Initialize State
    self.state = state
    self.engine = state.engine

  new npainterdispatch(state: NPainterState):
    result.flags = {wMouse}
    result.register(state)
    # Register Key Capture Observer
    let obs = observer(result.keyCapture)
    obs.watch = {evKeyDown, evKeyUp}
    getWindow().observers[].register(obs)
    result.keyWatch = obs

  method event(state: ptr GUIState) =
    self.capture(state)
    # Dispatch Selected Tool
    let slot {.cursor.} = self.slot
    slot.send(wsForward)    

  method layout =
    let
      state {.cursor.} = self.state
      engine {.cursor.} = state.engine
      m = engine.canvas.affine
      size = getWindow().rect
    # Set Viewport Size
    m.vw = size.w
    m.vh = size.h
    # Update View
    state.canvas.update()

  method handle(reason: GUIHandle) =
    let win = getWindow()
    # Block all Shortcuts
    if reason == inGrab:
      self.dummy.send(wsFocus)
    elif reason == outGrab:
      win.send(wsUnFocus)
