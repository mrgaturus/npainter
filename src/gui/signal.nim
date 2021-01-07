# GUI Signal/Callback Queue
from config import opaque

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
  GUIQueue* = ref object
    back, front: GUISignal

proc newGUIQueue*(global: pointer): GUIQueue =
  new result # Create Object
  opaque.queue = cast[pointer](result)
  # Define User Global Pointer
  opaque.user = global

# --------------------
# SIGNAL RUNTIME PROCS
# --------------------

iterator poll*(queue: GUIQueue): GUISignal =
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

proc dispose*(queue: GUIQueue) =
  var signal = queue.back
  while signal != nil:
    # Use back as prev
    queue.back = signal
    signal = signal.next
    # dealloc prev
    dealloc(queue.back)

# ---------------------------
# SIGNAL UNSAFE PUSHING PROCS
# ---------------------------

proc pushSignal*(id: GUITarget, msg: WidgetSignal) =
  assert(not cast[pointer](id).isNil)
  # Get Queue Pointer from Global
  var queue = cast[GUIQueue](opaque.queue)
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
  # Get Queue Pointer from Global
  var queue = cast[GUIQueue](opaque.queue)
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
  # Get Queue Pointer from Global
  var queue = cast[GUIQueue](opaque.queue)
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
  sig.cb(opaque.user, addr signal.data)

template convert*(data: GUIOpaque, t: type): ptr t =
  cast[ptr t](addr data)
