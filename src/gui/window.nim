import ../libs/egl
import x11/xlib, x11/x
import widget, event, context, container, frame

from builder import signal
from ../libs/gl import gladLoadGL

let
  # NPainter EGL Configurations
  attEGL = [
    # Color Channels
    EGL_RED_SIZE, 8,
    EGL_GREEN_SIZE, 8,
    EGL_BLUE_SIZE, 8,
    # Render Type
    EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
    EGL_NONE
  ]
  attCTX = [
    EGL_NONE
  ]
  attSUR = [
    EGL_RENDER_BUFFER, EGL_BACK_BUFFER,
    EGL_NONE
  ]

var
  signalQueue*: GUIQueue
type
  GUIWindow* = object
    # X11 Display & Window
    display: PDisplay
    xID: TWindow
    # X11 Input Method
    xim: TXIM
    xic: TXIC
    # EGL Context
    eglDsp: EGLDisplay
    eglCfg: EGLConfig
    eglCtx: EGLContext
    eglSur: EGLSurface
    # Itself
    ctx: GUIContext
    state: GUIState
    root: GUIContainer
    # Cache
    focus: GUIFrame
    hover: GUIFrame

signal Window:
  Terminate
  FocusIM
  UnfocusIM

const LC_ALL = 6 # Hardcopied from gcc header
proc setlocale(category: cint, locale: cstring): cstring
  {.cdecl, importc, header: "<locale.h>".}

# -----------------------
# WINDOW CREATION PRIVATE
# -----------------------

proc createXIM(win: var GUIWindow) =
  if setlocale(LC_ALL, "").isNil or XSetLocaleModifiers("").isNil:
    echo "WARNING: proper C locale not found"

  win.xim = XOpenIM(win.display, nil, nil, nil)
  win.xic = XCreateIC(win.xim, XNInputStyle, XIMPreeditNothing or
      XIMStatusNothing, XNClientWindow, win.xID, nil)

  if win.xic == nil:
    echo "WARNING: failed creating XIM context"

proc createXWindow(dsp: PDisplay, w, h: uint32): TWindow =
  let root = DefaultRootWindow(dsp)
  var attr: TXSetWindowAttributes
  attr.event_mask =
    KeyPressMask or
    KeyReleaseMask or
    ButtonPressMask or
    ButtonReleaseMask or
    PointerMotionMask or
    StructureNotifyMask

  result = XCreateWindow(dsp, root, 0, 0, w, h, 0, CopyFromParent,
      CopyFromParent, nil, CWEventMask, addr attr)

  if result == 0:
    echo "ERROR: failed creating X11 win"

proc createEGL(win: var GUIWindow) =
  var
    # New EGL Instance
    eglDsp: EGLDisplay
    eglCfg: EGLConfig
    eglCtx: EGLContext
    eglSur: EGLSurface
    # Checks
    ignore: EGLint
    cfgNum: EGLint
    ok: EGLBoolean

  # Bind OpenGL API
  ok = eglBindAPI(EGL_OPENGL_API)
  if not ok: return

  # Get EGL Display
  eglDsp = eglGetDisplay(win.display)
  if eglDsp.pointer.isNil: return

  # Initialize EGL
  ok = eglInitialize(eglDsp, ignore.addr, ignore.addr)
  if not ok: return

  # Choose Config
  ok = eglChooseConfig(eglDsp, cast[ptr EGLint](attEGL[0].unsafeAddr),
      eglCfg.addr, 1, cfgNum.addr)
  if not ok or cfgNum == 0: return

  # Create Context and Window Surface
  eglCtx = eglCreateContext(eglDsp, eglCfg, EGL_NO_CONTEXT, cast[ptr EGLint](
      attCTX[0].unsafeAddr))
  eglSur = eglCreateWindowSurface(eglDsp, eglCfg, win.xID, cast[ptr EGLint](
      attSUR[0].unsafeAddr))
  if eglCtx.pointer.isNil or eglSur.pointer.isNil: return

  # Make Current
  ok = eglMakeCurrent(eglDsp, eglSur, eglSur, eglCtx)
  if not ok: return

  if eglDsp.pointer.isNil or
      eglCfg.pointer.isNil or
      eglCtx.pointer.isNil or
      eglSur.pointer.isNil:
    echo "ERROR: failed creating EGL Context"
    return

  if not gladLoadGL(eglGetProcAddress):
    echo "ERROR: failed loading GL Functions"
    return

  # Save new EGL Context
  win.eglDsp = eglDsp
  win.eglCfg = eglCfg
  win.eglCtx = eglCtx
  win.eglSur = eglSur

# --------------------
# WINDOW CREATION PROCS
# --------------------

proc newGUIWindow*(w, h: int32, layout: GUILayout): GUIWindow =
  # Create new X11 Display
  result.display = XOpenDisplay(nil)
  if result.display.isNil:
    echo "ERROR: failed opening X11 display"
  # Initialize X11 Window and IM
  result.xID = createXWindow(result.display, uint32 w, uint32 h)
  result.createXIM()
  # Alloc a 32 byte UTF8Buffer
  result.state.utf8buffer(32)
  # Initialize EGL and GL
  result.createEGL()
  result.ctx = newGUIContext()
  # Create new root container
  block:
    let color = GUIColor(r: 0, g: 0, b: 0, a: 1)
    var root = newGUIContainer(layout, color)
    root.id = WindowID
    root.rect.w = w
    root.rect.h = h
    # Set the new root with initial sizes
    result.root = root
  # Alloc Global GUIQueue
  allocQueue()

# --------------------
# WINDOW GUI CREATION PROCS
# --------------------

proc addWidget*(win: var GUIWindow, widget: GUIWidget, region: bool = true) =
  if region:
    win.ctx.createRegion(addr widget.rect)
  win.root.add(widget)

proc addFrame*(win: var GUIWindow, layout: GUILayout,
    color: GUIColor): GUIFrame =
  result = newGUIFrame(layout, color)
  if win.root.prev == nil:
    win.root.prev = result
  # Change Next Prev
  if win.root.next != nil:
    win.root.next.prev = result
  # Change Next
  result.next = win.root.next
  win.root.next = result

# --------------
# WINDOW FRAME ITERATORS
# --------------

iterator forward(gui: GUIWidget): GUIFrame =
  var frame = gui.next
  while frame != nil:
    yield cast[GUIFrame](frame)
    frame = frame.next

iterator reverse(gui: GUIWidget): GUIFrame =
  var frame = gui.prev
  while frame != nil:
    yield cast[GUIFrame](frame)
    frame = frame.prev

# --------------
# WINDOW EXEC/EXIT
# --------------

proc exec*(win: var GUIWindow): bool =
  # Shows the win on the screen
  result = XMapWindow(win.display, win.xID) != BadWindow
  discard XSync(win.display, 0)
  # Resize Root FBO
  resize(win.ctx, addr win.root.rect)
  # Resize Frames FBO
  for frame in reverse(win.root):
    boundaries(frame)

proc exit*(win: var GUIWindow) =
  # Dispose Queue
  disposeQueue()
  # Dispose UTF8Buffer
  dealloc(win.state.utf8str)
  # Dispose EGL
  discard eglDestroySurface(win.eglDsp, win.eglSur)
  discard eglDestroyContext(win.eglDsp, win.eglCtx)
  discard eglTerminate(win.eglDsp)
  # Dispose all X Stuff
  XDestroyIC(win.xic)
  discard XCloseIM(win.xim)
  discard XDestroyWindow(win.display, win.xID)
  discard XCloseDisplay(win.display)

# --------------------
# WINDOW PRIVATE PROCS
# --------------------

proc elevateFrame*(root: GUIWidget, frame: GUIFrame) =
  if frame.prev != nil:
    # Remove frame from it's position
    frame.prev.next = frame.next
    if frame.next == nil: # Prev to root
      root.prev = frame.prev
    else: # Somewhere
      frame.next.prev = frame.prev
    # Prev is always nil
    frame.prev = nil
    # Move frame next to root
    frame.next = root.next
    frame.next.prev = frame
    root.next = frame

# --------------------
# WINDOW RUNNING PROCS
# --------------------

proc notFramed*(win: var GUIWindow, tab: bool): bool =
  var
    found: GUIFrame
    state = addr win.state
  case state.eventType
  of evMouseMove, evMouseClick, evMouseRelease, evMouseAxis:
    for frame in forward(win.root):
      if pointOnArea(frame, state.mx, state.my):
        if state.eventType == evMouseClick:
          elevateFrame(win.root, frame)
        # A frame was hovered
        found = frame
        break
    # Unhover root
    if found != nil and win.hover == nil:
      hoverOut(win.root)
    # Unhover prev frame
    if win.hover != found:
      if win.hover != nil:
        hoverOut(win.hover)
      # Set hover current
      win.hover = found
  of evKeyDown, evKeyUp:
    found = win.focus
  # Check if was framed
  if found != nil:
    if tab: step(win.focus, state.key == LeftTab)
    else:
      relative(found, win.state)
      event(found, addr win.state)
    # Event is framed
    return false
  # Event is not framed
  return true

proc handleEvents*(win: var GUIWindow) =
  var event: TXEvent
  # Input Event Handing
  while XPending(win.display) != 0:
    discard XNextEvent(win.display, addr event)
    if XFilterEvent(addr event, 0) != 0:
      continue
    case event.theType:
    of Expose: echo "look why use exposed"
    of ConfigureNotify: # Resize
      let
        w = win.root.rect.w
        h = win.root.rect.h
      if event.xconfigure.window == win.xID and
          (event.xconfigure.width != w or
          event.xconfigure.height != h):
        win.root.rect.w = event.xconfigure.width
        win.root.rect.h = event.xconfigure.height
        # Resize CTX Root
        resize(win.ctx, addr win.root.rect)
        # Relayout and Redraw GUI
        setMask(win.root.flags, wDirty)
    else:
      if translateXEvent(win.state, win.display, addr event, win.xic):
        let tabbed =
          win.state.eventType == evKeyDown and
          (win.state.key == RightTab or
          win.state.key == LeftTab)
        # Handle on any of the frames
        if notFramed(win, tabbed):
          if tabbed: step(win.root, win.state.key == LeftTab)
          else: event(win.root, addr win.state)

proc handleTick*(win: var GUIWindow): bool =
  # Signal ID Handling
  for signal in pollQueue():
    case signal.id:
    of NoSignalID: discard
    of WindowID:
      case WindowMsg(signal.msg):
      of msgTerminate: return false
      of msgFocusIM: XSetICFocus(win.xic)
      of msgUnfocusIM: XUnsetICFocus(win.xic)
    of FrameID:
      let data = convert(signal.data, SFrame)
      for frame in forward(win.root):
        if frame.fID == data.fID:
          case FrameMsg(signal.msg):
          of msgMove: frame.boundaries(data, false)
          of msgResize: frame.boundaries(data, true)
          of msgShow:
            setMask(frame.flags, wVisible)
          of msgHide: clearMask(frame.flags, wVisible)
    else:
      trigger(win.root, signal)
      # Send signal to frames
      for frame in forward(win.root):
        trigger(frame, signal)
  # Update -> Layout Root
  if testMask(win.root.flags, wUpdate):
    update(win.root)
  if anyMask(win.root.flags, 0x000C):
    layout(win.root)
    update(win.ctx)
  # Update -> Layout Frames
  for frame in forward(win.root):
    handleTick(frame)
  # The loop isn't terminated
  return true

proc render*(win: var GUIWindow) =
  start(win.ctx)
  # Draw hot/invalidated widgets
  if testMask(win.root.flags, wDraw):
    makeCurrent(win.ctx)
    draw(win.root, addr win.ctx)
    clearCurrent(win.ctx)
  # Draw Root Regions
  render(win.ctx)
  # Render floating frames
  for frame in reverse(win.root):
    render(frame, win.ctx)
  # Present to X11/EGL Window
  finish(win.ctx)
  discard eglSwapBuffers(win.eglDsp, win.eglSur)
