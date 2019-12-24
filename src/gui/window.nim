import widget, event, context, render, container
import x11/xlib, x11/x
import ../libs/egl

from builder import signal
from timer import sleep
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
    # Renderer
    render: CTXRender
    surf: CTXRoot
    # Unused Renderer Frames (Cache)
    unused: seq[CTXFrame]
    # GUI State
    state: GUIState
    # GUI Widgets and frames
    root: GUIContainer
    last: GUIWidget
    # Cache Frames
    focus: GUIWidget
    hover: GUIWidget

signal Window:
  # Basic Window
  Terminate
  FocusIM
  UnfocusIM
  # Grab Control
  HardGrab
  SoftGrab

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

proc newGUIWindow*(global: pointer, w, h: int32, layout: GUILayout): GUIWindow =
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
  result.render = newCTXRender()
  result.surf = newCTXRoot()
  # Disable VSync - Avoid Input Lag
  discard eglSwapInterval(result.eglDsp, 0)
  # Create new root container
  block:
    let color = GUIColor(r: 0, g: 0, b: 0, a: 1)
    var root = newGUIContainer(layout, color)
    root.signals = {WindowID, FrameID}
    root.rect.w = w
    root.rect.h = h
    # Set the new root at first and next
    result.root = root
    result.last = root
  # Alloc Global GUIQueue with Global
  allocQueue(global)

# --------------------
# WINDOW GUI CREATION PROCS
# --------------------

proc add*(win: var GUIWindow, widget: GUIWidget, region: bool = true) =
  if region: createRegion(win.surf, addr widget.rect)
  # Add Widget to Root
  add(win.root, widget)

# -----------------------
# WINDOW WIDGET ITERATORS
# -----------------------

# Only Floating Frames
iterator frames(win: var GUIWindow): GUIWidget =
  var frame = win.root.next
  while frame != nil:
    yield frame
    frame = frame.next

# Every Widget
iterator forward(win: var GUIWindow): GUIWidget =
  var frame = cast[GUIWidget](win.root)
  while frame != nil:
    yield frame
    frame = frame.next

iterator reverse(win: var GUIWindow): GUIWidget =
  var frame = win.last
  while frame != nil:
    yield frame
    frame = frame.prev

# --------------
# WINDOW EXEC/EXIT
# --------------

proc exec*(win: var GUIWindow): bool =
  # Shows the win on the screen
  result = XMapWindow(win.display, win.xID) != BadWindow
  discard XSync(win.display, 0)
  # Resize Root FBO
  resize(win.surf, addr win.root.rect)
  allocRegions(win.surf)

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

# Grab X11 Window
proc grab(win: var GUIWindow, evtype: int32) =
  if evtype == ButtonPress:
    discard XGrabPointer(win.display, win.xID, 0,
        ButtonPressMask or ButtonReleaseMask or PointerMotionMask,
        GrabModeAsync, GrabModeAsync, None, None, CurrentTime)
  elif evtype == ButtonRelease:
    discard XUngrabPointer(win.display, CurrentTime)

# Assign a ctxframe to a widget
proc useCTXFrame(win: var GUIWindow, frame: GUIWidget) {.inline.} =
  if len(win.unused) > 0: frame.surf = pop(win.unused)
  else: frame.surf = createFrame()

proc unuseCTXFrame(win: var GUIWindow, frame: GUIWidget) {.inline.} =
  add(win.unused, frame.surf)
  frame.surf = nil

# --------------------
# WINDOW FLOATING PRIVATE PROCS
# --------------------

proc addFrame(win: var GUIWindow, frame: GUIWidget) =
  # Next is nil, because is last
  frame.next = nil
  # Prev is last
  frame.prev = win.last
  win.last.next = frame
  # Last is frame
  win.last = frame
  # Use CTX Frame
  useCTXFrame(win, frame)
  # Mark as Framed
  set(frame, 0x418)

proc delFrame(win: var GUIWindow, frame: GUIWidget) =
  # Change next prev or last
  if win.last == frame: win.last = frame.prev
  else: frame.next.prev = frame.prev
  # Change prev next (first is root)
  frame.prev.next = frame.next
  # Remove next and prev
  frame.next = nil
  frame.prev = nil
  # Remove Hover, Grab or Focus
  if frame == win.hover:
    hoverOut(frame)
    clear(frame, wHover or wGrab)
  if frame == win.focus:
    focusOut(frame)
    clear(frame, wFocus)
  # Unuse CTX Frame
  unuseCTXFrame(win, frame)
  # Unmark as Framed
  clear(frame, 0x418)

proc elevateFrame(win: var GUIWindow, frame: GUIWidget) =
  if frame != win.last and frame.prev != nil:
    # Remove frame from it's position
    frame.prev.next = frame.next
    frame.next.prev = frame.prev
    # Next is nil because is last
    frame.next = nil
    # Move frame to last
    frame.prev = win.last
    win.last.next = frame
    win.last = frame

# --------------------
# WINDOW RUNNING PROCS
# --------------------

proc processEvent*(win: var GUIWindow, tabbed: bool) =
  var found: GUIWidget
  let state = addr win.state
  # Look for Mouse event o key event
  case state.eventType
  of evMouseMove, evMouseClick, evMouseRelease, evMouseAxis:
    if win.hover != nil and test(win.hover, wGrab):
      found = win.hover
    else: # Search on other frames
      for widget in reverse(win):
        if pointOnFrame(widget, state.mx, state.my):
          if win.state.eventType == evMouseClick:
            elevateFrame(win, widget)
          # A frame was hovered
          found = widget
          break
      # Unhover prev frame
      if found != win.hover:
        if win.hover != nil:
          hoverOut(win.hover)
          clear(win.hover, wHover)
        # Set hover current
        win.hover = found
  of evKeyDown, evKeyUp:
    found = win.focus
  # Check if a widget was found
  if found != nil:
    if tabbed: step(found, state.key == LeftTab)
    else:
      relative(found, state)
      event(found, state)
    # Change focused or focus out
    if found.test(wFocusCheck):
      if found != win.focus:
        if win.focus != nil:
          focusOut(win.focus)
          clear(win.focus, wFocus)
        win.focus = found
    elif found == win.focus:
      focusOut(win.focus)
      clear(win.focus, wFocus)
      win.focus = nil

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
        resize(win.surf, addr win.root.rect)
        # Relayout and Redraw GUI
        win.root.set(wDirty)
    else:
      # Grab/UnGrab X11 Window
      win.grab(event.theType)
      # Process Event if is a valid gui event
      if translateXEvent(win.state, win.display, addr event, win.xic):
        processEvent(win,
          win.state.eventType == evKeyDown and
            (win.state.key == RightTab or
            win.state.key == LeftTab)
        )

proc handleTick*(win: var GUIWindow): bool =
  # Signal ID Handling
  for signal in pollQueue():
    # is GUI Callback?
    if callSignal(signal):
      continue
    # is GUI Signal?
    case signal.id:
    of WindowID:
      case WindowMsg(signal.msg):
      of msgTerminate: return false
      of msgFocusIM: XSetICFocus(win.xic)
      of msgUnfocusIM: XUnsetICFocus(win.xic)
      else: discard
    of FrameID:
      let frame = 
        convert(signal.data, GUIWidget)[]
      if frame != nil:
        case FrameMsg(signal.msg)
        of msgRegion: # Move or resize
          if test(frame, wFramed):
            if region(frame.surf, frame.region):
              frame.set(wDirty)
        of msgClose: # Remove frame from window
          if test(frame, wFramed):
            delFrame(win, frame)
        of msgOpen: # Add frame to window
          if not test(frame, wFramed):
            addFrame(win, frame)
            # Update frame region after added
            region(frame.surf, frame.region)
    else: # Process signal to widgets
      for widget in forward(win):
        if signal.id in widget: 
          trigger(widget, signal)
  # Update -> Layout
  for widget in forward(win):
    if test(widget, wUpdate):
      update(widget)
    if any(widget, 0x0C):
      layout(widget)
      if widget.prev == nil: 
        update(win.surf)
  # The loop isn't terminated
  return true

proc render*(win: var GUIWindow) =
  # Start GUI Rendering
  start(win.render)
  # Draw hot/invalidated widgets
  if test(win.root, wDraw):
    makeCurrent(win.render, win.surf)
    draw(win.root, addr win.render)
    clearCurrent(win.render, win.surf)
  # Draw Root Regions
  render(win.surf)
  # Render floating widgets
  for frame in frames(win):
    if frame.test(wDraw):
      makeCurrent(win.render, frame.surf)
      draw(frame, addr win.render)
      clearCurrent(win.render, win.surf)
    render(frame.surf)
  # Finish GUI Rendering
  finish(win.render)
  # Present to X11/EGL Window
  discard eglSwapBuffers(win.eglDsp, win.eglSur)
  # TODO: FPS Strategy
  sleep(16)
