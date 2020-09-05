import x11/xlib, x11/x
from x11/keysym import 
  XK_Tab, XK_ISO_Left_Tab

# ----------------------------------
# SECTION: GUI X11 STATE TRANSLATION
# ----------------------------------

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
  UTF8Keysym* = XLookupKeysymVal
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
    kind*: GUIEvent
    key*: uint
    # Mouse Event Detail
    mx*, my*: int32
    pressure*: float32
    # Key Event Detail
    utf8state*: int32
    utf8cap, utf8size*: int32
    utf8str*: cstring
    # Key Modifiers
    mods*: uint32

# UTF8Buffer allocation/reallocation
proc utf8buffer*(state: var GUIState, cap: int32) =
  if state.utf8str.isNil: # Alloc First Time
    state.utf8str = cast[cstring](alloc(cap))
  else: state.utf8str = cast[cstring](
    realloc(state.utf8str, cap))
  state.utf8cap = cap # Expand

# X11 to GUIState translation
proc translateXEvent*(state: var GUIState, display: PDisplay, event: PXEvent,
    xic: XIC): bool =
  state.kind = # Set Event Kind
    cast[GUIEvent](event.theType - 2)
  case event.theType
  of ButtonPress, ButtonRelease:
    state.mx = event.xbutton.x
    state.my = event.xbutton.y
    state.key = event.xbutton.button
    # Update Keyboard Modifiers
    state.mods = event.xbutton.state
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
      state.utf8size = # Retry Lookup Char Again
        Xutf8LookupString(xic, cast[PXKeyPressedEvent](event), state.utf8str,
            state.utf8cap, state.key.addr, state.utf8state.addr)
    # Update Keyboard Modifers
    state.mods = event.xkey.state
  of KeyRelease:
    # Handle key-repeat properly
    if XEventsQueued(display, QueuedAfterReading) != 0:
      var nEvent: XEvent
      discard XPeekEvent(display, nEvent.addr)
      if nEvent.theType == KeyPress and
          nEvent.xkey.time == event.xkey.time and
          nEvent.xkey.keycode == event.xkey.keycode:
        return false
    let mods = cast[cint](event.xkey.state)
    state.key = # Ignoring UTF8Chars when key releasing
      XLookupKeysym(cast[PXKeyEvent](event), 
        (mods and ShiftMask) or (mods and LockMask))
    state.utf8state = UTF8Nothing
    # Update Keyboard Modifers
    state.mods = cast[uint32](mods)
  else: return false
  # Event is valid
  return true

# -------------------------------------
# SECTION: GUI SIGNAL QUEUE PROCS/TYPES
# -------------------------------------

type
  # GUI Signal Private
  SKind* = enum
    sCallback # CB
    sWidget, sWindow
  WidgetSignal* = enum
    msgDirty, msgFocus, msgCheck
    msgClose, msgFrame
    msgPopup, msgTooltip
  WindowSignal* = enum
    msgOpenIM, msgCloseIM
    msgUnfocus, msgUnhover
    msgTerminate # Close
  Signal = object
    next: GUISignal
    # Signal or Callback
    case kind*: SKind
    of sCallback:
      cb*: GUICallback
    of sWidget:
      id*: GUITarget
      msg*: WidgetSignal
    of sWindow:
      w_msg*: WindowSignal
    # Signal Data
    data*: GUIOpaque
  # Signal Generic Data
  GUITarget* = distinct pointer
  GUICallback* = # Standard Procs
    proc(g, d: pointer) {.nimcall.}
  GUIOpaque* = object
  # GUI Signal and Queue
  GUISignal* = ptr Signal
  GUIQueue* = object
    back, front: GUISignal
    global: pointer
var # Global Queue
  queue: ptr GUIQueue

proc newQueue*(g: pointer) =
  if queue.isNil:
    queue = cast[ptr GUIQueue](
      alloc0(sizeof(GUIQueue))
    ); queue.global = g

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

# ---------------------------
# SIGNAL UNSAFE PUSHING PROCS
# ---------------------------

proc pushSignal*(id: GUITarget, msg: WidgetSignal) =
  assert(not cast[pointer](id).isNil)
  # Allocs New Signal
  let nsignal = cast[GUISignal](
    alloc0(Signal.sizeof)
  ); nsignal.next = nil
  # Widget Signal Kind
  nsignal.kind = sWidget
  nsignal.id = id
  nsignal.msg = msg
  # Add new signal to Front
  if queue.front.isNil:
    queue.back = nsignal
    queue.front = nsignal
  else:
    queue.front.next = nsignal
    queue.front = nsignal

proc pushSignal(msg: WindowSignal, data: pointer, size: Natural) =
  # Allocs New Signal
  let nsignal = cast[GUISignal](
    alloc0(Signal.sizeof + size)
  ); nsignal.next = nil
  # Window Signal Kind
  nsignal.kind = sWindow
  nsignal.w_msg = msg
  # Copy Optionally Data
  if size > 0 and not isNil(data):
    copyMem(addr nsignal.data, data, size)
  # Add new signal to Front
  if queue.front.isNil:
    queue.back = nsignal
    queue.front = nsignal
  else:
    queue.front.next = nsignal
    queue.front = nsignal

proc pushCallback(cb: GUICallback, data: pointer, size: Natural) =
  assert(not cb.isNil)
  # Allocs New Signal
  let nsignal = cast[GUISignal](
    alloc0(Signal.sizeof + size)
  ); nsignal.next = nil
  # Assign Callback
  nsignal.kind = sCallback
  nsignal.cb = cb
  # Copy Optionally Data
  if size > 0 and not isNil(data):
    copyMem(addr nsignal.data, data, size)
  # Add new signal to Front
  if queue.front.isNil:
    queue.back = nsignal
    queue.front = nsignal
  else:
    queue.front.next = nsignal
    queue.front = nsignal

# ----------------------------------
# GUI WIDGET SIGNAL PUSHER TEMPLATES
# ----------------------------------

template pushSignal*(msg: WindowSignal, data: typed) =
  pushSignal(msg, addr data, sizeof data)

template pushSignal*(msg: WindowSignal) =
  pushSignal(msg, nil, 0)

# ------------------------------------
# GUI CALLBACK SIGNAL PUSHER TEMPLATES
# ------------------------------------

template pushCallback*(cb: proc, data: typed) =
  pushCallback(cast[GUICallback](cb), addr data, sizeof data)

template pushCallback*(cb: proc) =
  pushCallback(cast[GUICallback](cb), nil, 0)

# ---------------------------------
# GUI SIGNAL DATA POINTER CONVERTER
# ---------------------------------

template call*(sig: GUISignal) =
  sig.cb(queue.global, addr signal.data)

template convert*(data: GUIOpaque, t: type): ptr t =
  cast[ptr t](addr data)
