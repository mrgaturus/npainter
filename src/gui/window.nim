import ../libs/egl
import x11/xlib, x11/x
import widget, event, context, container, frame

from builder import signal
from ../libs/gl import glFinish, gladLoadGL
from x11/keysym import XK_Tab, XK_ISO_Left_Tab

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
    ctx*: GUIContext
    state: GUIState
    gui*: GUIContainer
    # Frames (subwindows)
    frames: seq[GUIFrame]
    focusedFrame: int

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
    var gui = newContainer(layout)
    gui.id = WindowID
    gui.rect.w = w
    gui.rect.h = h
    # Resize context to initial gui size
    result.ctx.resize(addr gui.rect)
    result.gui = gui
  # Alloc Global GUIQueue
  allocQueue()

proc exec*(win: var GUIWindow): bool =
  # Shows the win on the screen
  result = XMapWindow(win.display, win.xID) != BadWindow
  discard XSync(win.display, 0)

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
# WINDOW GUI PROCS
# --------------------

proc add*(win: var GUIWindow, widget: GUIWidget) =
  win.ctx.createRegion(addr widget.rect)
  win.gui.add(widget)

# --------------------
# WINDOW RUNNING PROCS
# --------------------

proc handleEvents*(win: var GUIWindow) =
  var event: TXEvent
  # Input Event Handing
  while XPending(win.display) != 0:
    discard XNextEvent(win.display, event.addr)
    if XFilterEvent(addr event, 0) != 0:
      continue

    case event.theType:
    of Expose: setMask(win.gui.flags, wDirty)
    of ConfigureNotify: # Resize
      let
        w = win.gui.rect.w
        h = win.gui.rect.h
      if event.xconfigure.window == win.xID and
          (event.xconfigure.width != w or
          event.xconfigure.height != h):
        win.gui.rect.w = event.xconfigure.width
        win.gui.rect.h = event.xconfigure.height
        # Resize CTX Root
        win.ctx.resize(addr win.gui.rect)
        # Relayout and Redraw GUI
        setMask(win.gui.flags, wDirty)
    else:
      translateXEvent(win.state, win.display, addr event, win.xic)
      # Check if tab is pressed for step focus
      if win.state.eventType == evKeyDown and
          (win.state.key == XK_Tab or
          win.state.key == XK_ISO_Left_Tab):
        step(win.gui, win.state.key == XK_ISO_Left_Tab)
      else:
        event(win.gui, addr win.state)

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
    else:
      trigger(win.gui, signal)
      # Signal for frames
      for frame in mitems(win.frames):
        trigger(frame, signal)
  # Update -> Layout
  if testMask(win.gui.flags, wUpdate):
    update(win.gui)
  if anyMask(win.gui.flags, 0x000C):
    layout(win.gui)
    update(win.ctx)

  return true

proc render*(win: var GUIWindow) =
  # Draw hot/invalidated widgets
  #start(win.ctx)
  #if testMask(win.gui.flags, wDraw):
  #  makeCurrent(win.ctx)
  #  draw(win.gui, addr win.ctx)
  #  clearCurrent(win.ctx)
  # Draw Root
  #win.ctx.render()
  # Present to X11/EGL Window
  discard eglSwapBuffers(win.eglDsp, win.eglSur)
  #finish(win.ctx)
