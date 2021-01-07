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
