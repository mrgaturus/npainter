import ../logger
# Check sufixes of XI2 name
from strutils import 
  endsWith, startsWith, toLowerAscii
# Import X11 Module and XInput2
import x11/[x, xlib, xi2, xinput2]
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
  # XInput2 Device
  GUITool* = enum
    devStylus
    devEraser
    devMouse
  GUIDevice = object
    id: int32
    tool: GUITool
    # Pressure ID
    number: int32
    # Pressure Info
    min, max, last: float32
  # GUI State
  GUIEvent* = enum
    evCursorMove
    evCursorClick
    evCursorRelease
    # Key Events
    evKeyDown
    evKeyUp
  GUIState* = object
    opcode: int32
    devices: seq[GUIDevice]
    # Event Kind
    kind*: GUIEvent
    # Pointer Kind
    tool*: GUITool
    # Mouse Coords
    mx*, my*: int32
    # Tablet Coords
    px*, py*: float32
    pressure*: float32
    # Key Event ID
    key*: uint
    # Key Event UTF8
    utf8state*: int32
    utf8cap, utf8size*: int32
    utf8str*: cstring
    # Key Modifiers
    mods*: uint32

# ----------------------------------
# UTF8Buffer allocation/reallocation
# ----------------------------------

# I can get rid of this if i can get capacity of string/seq
proc utf8buffer*(state: var GUIState, cap: int32) =
  if state.utf8str.isNil: # Alloc First Time
    state.utf8str = cast[cstring](alloc(cap))
  else: state.utf8str = cast[cstring](
    realloc(state.utf8str, cap))
  state.utf8cap = cap # Expand

# ----------------------------------
# GUI Event State Construction Procs
# ----------------------------------
const no_pressure = cast[int32](not 0)

# check labels for xwayland, wacom and libinput
proc toolXI2(name: cstring): GUITool =
  # Lowered case name, for better check
  var lower = ($name).toLowerAscii()
  # Check Kind of Cursor Device
  if lower.startsWith("virtual core"):
    result = devMouse # Virtual or Test
  elif lower.endsWith("stylus") or lower.endsWith("pen"):
    result = devStylus # Pen nib
  elif lower.endsWith("eraser"):
    result = devEraser # Eraser
  # Otherwise, consider as Mouse
  else: result = devMouse

proc devicesXI2(state: var GUIState, display: PDisplay) =
  var 
    device_n: int32
    device: PXIDeviceInfo
    device_class: PXIAnyClassInfo
  let 
    device_list = cast[ptr UncheckedArray[XIDeviceInfo]](
      XIQueryDevice(display, XIAllDevices, addr device_n))
    # Look for Pressure Axis, Tilt will be added sometime
    p_label = XInternAtom(display, "Abs Pressure", false.XBool)
  # Iterate Each Device
  for i in 0..<device_n:
    device = addr device_list[i]
    if device.use != XISlavePointer:
      continue # Skip Not Cursors
    # New Device Item
    var item: GUIDevice
    # Store Device ID
    item.id = device.deviceid
    # Mark Pressure ID as Invalid
    item.number = no_pressure
    # Shortcut for Device Classes
    let device_classes = cast[ptr 
      UncheckedArray[PXIAnyClassInfo]](device.classes)
    # Get Buttons and Valuators
    for j in 0..<device.num_classes:
      device_class = device_classes[j]
      # Store Pressure Information
      if device_class.`type` == XIValuatorClass:
        let valuator = cast[PXIValuatorClassInfo](device_class)
        if valuator.label == p_label:
          item.number = valuator.number
          # Store Pressure Range
          item.min = valuator.min
          item.max = valuator.max
    # Set Cursor Tool Kind
    item.tool = toolXI2(device.name)
    # Store New Device Item
    state.devices.add(item)
  # Free Device Info
  XIFreeDeviceInfo(
    cast[PXIDeviceInfo](device_list))

proc enableXI2(display: PDisplay, win: Window) =
  const master_pointer = 2
  # Define XI2 Config
  var
    em: XIEventMask
    mask: uint8
    # Nim Shortcut
    p_mask = addr mask
  # Select Master Pointer Group
  em.deviceid = master_pointer
  # Select XI2 Event Masks
  em.mask_len = 1
  em.mask = cast[ptr cuchar](p_mask)
  # Set XInput2 Masks
  XISetMask(p_mask, XI_ButtonPress)
  XISetMask(p_mask, XI_ButtonRelease)
  XISetMask(p_mask, XI_Motion)
  # Bind To Current Display and Window
  discard XISelectEvents(display, win, addr em, 1)

proc newGUIState*(display: PDisplay, win: Window): GUIState =
  # Alloc UTF8 Buffer
  result.utf8buffer(32)
  # Dummy var for XI2
  var check: int32
  # Check if XI2 is present
  check = XQueryExtension(display, "XInputExtension", 
    addr result.opcode, addr check, addr check)
  if check == 0:
    log(lvError, "XInput extension not presented")
  # Check XInput version if is XI2
  block:
    # Dumb way of X11 for query
    var major, minor: int32
    major = 2; minor = 0
    # Check XInput version
    check = XIQueryVersion(display, addr major, addr minor)
    if check == BadRequest:
      log(lvError, "XInput extension found is not XInput2")
  # Find Cursor Devices
  result.devicesXI2(display)
  # Enable XInput2 Events
  enableXI2(display, win)

# -------------------------
# Event State Runtime Procs
# -------------------------

proc translateXI2(state: var GUIState, event: PXEvent) =
  let evXI2 = cast[PXIDeviceEvent](event.xcookie.data)
  # Get Device Coordinates
  state.px = evXI2.event_x
  state.py = evXI2.event_y
  # Get Cursor Coordinates
  state.mx = int32(state.px)
  state.my = int32(state.py)
  # Get Event Kind
  case evXI2.evtype
  of XI_Motion:
    state.kind = evCursorMove
  of XI_ButtonPress:
    state.kind = evCursorClick
    # Get Cursor Button Pressed
    state.key = cast[cuint](evXI2.detail)
  of XI_ButtonRelease:
    state.kind = evCursorRelease
    # Get Cursor Button Pressed
    state.key = cast[cuint](evXI2.detail)
  # Impossible State, but handled
  else: state.kind = evCursorMove
  # Get key mods for all three events
  state.mods = cast[cuint](evXI2.mods.base)
  # Find Device that cause event
  var found: ptr GUIDevice
  for dev in mitems(state.devices):
    if dev.id == evXI2.sourceid:
      found = addr dev
  # Get Pressure if found and is valid device
  if not isNil(found) and found.number > no_pressure:
    let mask = evXI2.valuators.mask
    # Return Tool Kind of Found
    state.tool = found.tool
    # Use Last Pressure for avoid discontinues
    if XIMaskIsSet(mask, found.number) == 0:
      state.pressure = found.last
    else: # Lookup Pressure
      var current: int
      for i in 0..<found.number:
        if XIMaskIsSet(mask, i) != 0:
          inc(current)
      # Get Raw Pressure and Normalize it
      var press = cast[ptr UncheckedArray[cdouble]](
        evXI2.valuators.values)[current]
      press = (press - found.min) / (found.max - found.min)
      # Change Last Pressure
      found.last = press
      # Return Normalized Pressure
      state.pressure = press
  else: # Fallback to full pressure
    state.tool = devMouse
    state.pressure = 1.0

proc translateXEvent*(state: var GUIState, display: PDisplay, event: PXEvent,
    xic: XIC): bool =
  case event.theType
  of GenericEvent:
    # Check if event belongs to XInput2
    if event.xcookie.extension == state.opcode and
    XGetEventData(display, addr event.xcookie) != 0:
      translateXI2(state, event)
      # Free Allocated Event Data
      XFreeEventData(display, addr event.xcookie)
  of KeyPress:
    # Set Event Kind
    state.kind = evKeyDown
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
    # Set Event Kind
    state.kind = evKeyUp
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
