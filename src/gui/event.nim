import x11/xlib, x11/x
from x11/keysym import XK_Tab, XK_ISO_Left_Tab

const
  # Mouse Buttons
  LeftButton* = Button1
  MiddleButton* = Button2
  RightButton* = Button3
  WheelUp* = Button4
  WheelDown* = Button5
  # Tab Buttons
  RightTab* = XK_Tab
  LeftTab* = XK_ISO_Left_Tab
  # Modifiers
  ShiftMod* = ShiftMask
  CtrlMod* = ControlMask
  AltMod* = Mod1Mask
  # UTF8 Status
  UTF8Keysym* = XLookupKeysym
  UTF8Success* = XLookupBoth
  UTF8String* = XLookupChars
  UTF8Nothing* = XLookupNone

type
  GUIEvent* = enum
    evKeyDown
    evKeyUp
    evMouseClick
    evMouseRelease
    evMouseMove
    evMouseAxis
  GUIState* = object
    eventType*: GUIEvent
    key*: uint
    # Mouse Event Detail
    mx*, my*: int32
    pressure*: float32
    # Key Event Detail
    utf8state*: int32
    utf8cap, utf8size*: int32
    utf8str*: cstring
    # Modifiers for Both
    mods*: uint16
  # GUI Signal Private
  SKind = enum
    sSignal, sCallback
  Signal = object
    next: GUISignal
    # Signal or Callback
    case kind: SKind
    of sSignal: 
      id*, msg*: uint8
    of sCallback: 
      cb: GUICallback
    # Signal Data
    data*: GUISData
  # Signal Generic Data
  GUICallback* = proc(g, d: pointer) {.nimcall.}
  GUISData* = object
  # GUI Signal and Queue
  GUISignal* = ptr Signal
  GUIQueue* = object
    back, front: GUISignal
    global: pointer

# UTF8Buffer allocation/reallocation
proc utf8buffer*(state: var GUIState, cap: int32) =
  if state.utf8str.isNil:
    state.utf8str = cast[cstring](alloc(cap))
  else:
    state.utf8str = cast[cstring](realloc(state.utf8str, cap))
  state.utf8cap = cap

# X11 to GUIState translation
proc translateXEvent*(state: var GUIState, display: PDisplay, event: PXEvent,
    xic: TXIC): bool =
  state.eventType = cast[GUIEvent](event.theType - 2)
  case event.theType
  of ButtonPress, ButtonRelease:
    state.mx = event.xbutton.x
    state.my = event.xbutton.y
    state.key = event.xbutton.button
  of MotionNotify:
    state.mx = event.xmotion.x
    state.my = event.xmotion.y
  of KeyPress:
    # Lookup UTF8 Char
    state.utf8size =
      Xutf8LookupString(xic, cast[PXKeyPressedEvent](event), state.utf8str,
          state.utf8cap, state.key.addr, state.utf8state.addr)
    # Check is buffer size is not enough
    if state.utf8state == XBufferOverflow:
      utf8buffer(state, state.utf8size)
      state.utf8cap = state.utf8size
      state.utf8size =
        Xutf8LookupString(xic, cast[PXKeyPressedEvent](event), state.utf8str,
            state.utf8cap, state.key.addr, state.utf8state.addr)
    # Update Modifers
    state.mods = cast[uint16](event.xkey.state and 0x0D)
  of KeyRelease:
    # Handle key-repeat properly
    if XEventsQueued(display, QueuedAfterReading) != 0:
      var nEvent: TXEvent
      discard XPeekEvent(display, nEvent.addr)
      if nEvent.theType == KeyPress and
          nEvent.xkey.time == event.xkey.time and
          nEvent.xkey.keycode == event.xkey.keycode:
        return false

    let mods: cint = cast[cint](event.xkey.state)
    # Ignoring UTF8Chars when key releasing
    state.key =
      XLookupKeysym(cast[PXKeyEvent](event), (mods and ShiftMask) or (mods and LockMask))
    state.utf8state = UTF8Nothing
    state.mods = cast[uint16](mods and 0x0D)
  else: return false
  # Event is valid
  return true

# ------------
# SIGNAL QUEUE
# ------------

var queue: ptr GUIQueue = nil
proc allocQueue*(g: pointer) =
  if queue.isNil:
    queue = cast[ptr GUIQueue](
      alloc0(sizeof(GUIQueue))
    )
    # Define Global Data
    queue.global = g

proc disposeQueue*() =
  var signal = queue.back
  while signal != nil:
    # Use back as prev
    queue.back = signal
    signal = signal.next
    # dealloc prev
    dealloc(queue.back)
  dealloc(queue)

iterator pollQueue*(): GUISignal =
  var signal = queue.back
  while signal != nil:
    yield signal
    # Use back as prev
    queue.back = signal
    signal = signal.next
    # dealloc prev
    dealloc(queue.back)
  queue.back = nil
  queue.front = nil

# ---------------
# CALLBACK CALLER
# ---------------

proc callSignal*(signal: GUISignal): bool =
  result = signal.kind == sCallback
  if result: signal.cb(
    queue.global, 
    cast[pointer](addr signal.data)
  )

# ------------
# SIGNAL PUSHER
# ------------

proc pushSignal*(id: uint8, msg: enum, data: pointer, size: Natural) =
  # Allocs new signal
  let nsignal = cast[GUISignal](
    alloc0(sizeof(Signal) + size)
  )
  nsignal.next = nil
  # Signal Kind
  nsignal.kind = sSignal
  # Assign Msg
  nsignal.id = id
  nsignal.msg = uint8(msg)
  # Copy Extra Data
  copyMem(addr nsignal.data, data, size)
  # Add new signal to Front
  if queue.front.isNil:
    queue.back = nsignal
    queue.front = nsignal
  else:
    queue.front.next = nsignal
    queue.front = nsignal

proc pushCallback(cb: GUICallback, data: pointer, size: Natural) =
  # Allocs new signal
  let nsignal = cast[GUISignal](
    alloc0(sizeof(Signal) + size)
  )
  nsignal.next = nil
  # Assign Callback
  nsignal.kind = sCallback
  nsignal.cb = cb
  # Copy Extra Data
  copyMem(addr nsignal.data, data, size)
  # Add new signal to Front
  if queue.front.isNil:
    queue.back = nsignal
    queue.front = nsignal
  else:
    queue.front.next = nsignal
    queue.front = nsignal

template pushCallback*(cb: proc, data: pointer, size: Natural) =
  pushCallback(cast[GUICallback](cb), data, size)

# ---------------------
# SIGNAL DATA CONVERTER
# ---------------------

template convert*(data: GUISData, t: type): untyped =
  cast[ptr t](addr data)
