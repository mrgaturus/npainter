import x11/xlib, x11/x

const
  GUIQueueSize = 16
  GUIQueueEmpty = -1

const
  # No Signal
  NoSignalID* = 0'u16
  # Mouse Buttons
  LeftButton* = Button1
  MiddleButton* = Button2
  RightButton* = Button3
  WheelUp* = Button4
  WheelDown* = Button5
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
    evMouseUnclick
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
  GUISignal* = object
    id*, message*: uint16
  GUIQueue* = object
    front, back: int16
    signals: array[GUIQueueSize, GUISignal]

proc allocUTF8Buffer*(state: var GUIState, cap: int32) =
  if state.utf8str.isNil:
    state.utf8str = cast[cstring](alloc(cap))
  else:
    state.utf8str = cast[cstring](realloc(state.utf8str, cap))
  state.utf8cap = cap

# X11 to GUIState translation
proc translateXEvent*(state: var GUIState, display: PDisplay, event: PXEvent, xic: TXIC) =
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
      state.allocUTF8Buffer(state.utf8size)
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
        return

    let mods: cint = cast[cint](event.xkey.state)
    # Ignoring UTF8Chars when key releasing
    state.key =
      XLookupKeysym(cast[PXKeyEvent](event), (mods and ShiftMask) or (mods and LockMask))
    state.utf8state = UTF8Nothing
    state.mods = cast[uint16](mods and 0x0D)
  else:
    discard

# Signal ID Queue
proc newGUIQueue*(): GUIQueue =
  zeroMem(result.addr, sizeof(GUIQueue))
  result.front = GUIQueueEmpty
  result.back = GUIQueueEmpty

proc pushSignal*(queue: var GUIQueue, id: uint16, message: enum): bool =
  if id == NoSignalID or
      queue.front == 0 and queue.back == GUIQueueSize - 1 or
      queue.back == queue.front - 1:
    return false

  if queue.front == GUIQueueEmpty:
    zeroMem(queue.addr, sizeof(GUIQueue))
  else:
    queue.back = (queue.back + 1) mod GUIQueueSize

  queue.signals[queue.back] =
    GUISignal(id: id, message: message.uint16)
  return true

proc popSignal(queue: var GUIQueue): GUISignal =
  let front = queue.front
  if front == GUIQueueEmpty:
    zeroMem(result.addr, GUISignal.sizeof)
  else:
    if front == queue.back:
      queue.front = GUIQueueEmpty
      queue.back = GUIQueueEmpty
    else:
      queue.front = (front + 1) mod GUIQueueSize
    result = queue.signals[front]

iterator items*(queue: var GUIQueue): GUISignal =
  var signal: GUISignal
  while true:
    signal = queue.popSignal()
    if signal.id == NoSignalID:
      break

    yield signal
