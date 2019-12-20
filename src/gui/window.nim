import ../libs/egl
import x11/xlib, x11/x
import widget, event, context, render, container

from builder import signal
from ../libs/gl import gladLoadGL
from os import sleep

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

proc newGUIWindow*(g: pointer, w, h: int32, layout: GUILayout): GUIWindow =
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
    # Set the new root with initial sizes
    result.root = root
    result.last = root
  # Alloc Global GUIQueue with Global
  allocQueue(g)

# --------------------
# WINDOW GUI CREATION PROCS
# --------------------

proc addWidget*(win: var GUIWindow, widget: GUIWidget, region: bool = true) =
  if region: createRegion(win.surf, addr widget.rect)
  # Add Widget to Root
  add(win.root, widget)

# --------------
# WINDOW FRAME ITERATORS
# --------------

iterator forward(win: var GUIWindow): GUIWidget =
  var frame = win.root.next
  while frame != nil:
    yield frame
    frame = frame.next

iterator reverse(win: var GUIWindow): GUIWidget =
  var frame = win.last
  while frame != win.root:
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

proc useCTXFrame(win: var GUIWindow, frame: GUIWidget) {.inline.} =
  if len(win.unused) > 0: frame.surf = pop(win.unused)
  else: frame.surf = createFrame()

proc unuseCTXFrame(win: var GUIWindow, frame: GUIWidget) {.inline.} =
  add(win.unused, frame.surf)
  frame.surf = nil

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

proc delFrame(win: var GUIWindow, frame: GUIWidget) =
  # Change next prev or last
  if win.last == frame: win.last = frame.prev
  else: frame.next.prev = frame.prev
  # Change prev next (first is root)
  frame.prev.next = frame.next
  # Remove next and prev
  frame.next = nil
  frame.prev = nil
  # Unuse CTX Frame
  unuseCTXFrame(win, frame)

proc elevateFrame(win: var GUIWindow, frame: GUIWidget) =
  if win.last != frame:
    # Remove frame from it's position
    frame.prev.next = frame.next
    frame.next.prev = frame.prev
    # Next is nil because is last
    frame.next = nil
    # Move frame to last
    frame.prev = win.last
    win.last.next = frame
    win.last = frame

proc grab(win: var GUIWindow, evtype: int32) =
  if evtype == ButtonPress:
    discard XGrabPointer(win.display, win.xID, 0, 
        ButtonPressMask or ButtonReleaseMask or PointerMotionMask,
        GrabModeAsync, GrabModeAsync, None, None, CurrentTime)
  elif evtype == ButtonRelease:
    discard XUngrabPointer(win.display, CurrentTime)

# --------------------
# WINDOW RUNNING PROCS
# --------------------

proc notFramed*(win: var GUIWindow, tab: bool): bool =
  var found: GUIWidget
  case win.state.eventType
  of evMouseMove, evMouseClick, evMouseRelease, evMouseAxis:
    if test(win.root, wGrab): return true
    elif win.hover != nil and test(win.hover, wGrab):
      found = win.hover
    else: # Search on other frames
      for frame in reverse(win):
        if relative(frame, win.state):
          if win.state.eventType == evMouseClick:
            elevateFrame(win, frame)
          # A frame was hovered
          found = frame
          break
      # Unhover prev frame
      if found != win.hover:
        if win.hover == nil:
          hoverOut(win.root)
        else: hoverOut(win.hover)
        # Set hover current
        win.hover = found
  of evKeyDown, evKeyUp:
    found = win.focus
  # Check if was framed
  if found != nil:
    if tab: step(found, win.state.key == LeftTab)
    else: event(found, addr win.state)
    # Change focused
    if found.test(wFocus):
      if found != win.focus:
        if test(win.root, wFocus):
          focusOut(win.root)
          clear(win.root, wFocus)
        elif win.focus != nil:
          focusOut(win.focus)
          clear(win.focus, wFocus)
        win.focus = found
    elif found == win.focus:
      win.focus = nil
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
        resize(win.surf, addr win.root.rect)
        # Relayout and Redraw GUI
        win.root.set(wDirty)
    else:
      # Grab/UnGrab X11 Window
      win.grab(event.theType)
      # Handle Event if was translated
      if translateXEvent(win.state, win.display, addr event, win.xic):
        let tabbed =
          win.state.eventType == evKeyDown and
          (win.state.key == RightTab or
          win.state.key == LeftTab)
        # Handle on any of the frames
        if notFramed(win, tabbed):
          if tabbed and test(win.root, wFocus):
            step(win.root, win.state.key == LeftTab)
          else: event(win.root, addr win.state)

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
      let frame = convert(signal.data, GUIWidget)[]
      if frame != nil:
        case FrameMsg(signal.msg)
        of msgRebound:
          if test(frame, wFramed):
            region(frame.surf, frame.region)
        of msgOpen:
          if not test(frame, wFramed):
            addFrame(win, frame)
            region(frame.surf, frame.region)
            # Mark Framed
            set(frame, wFramed or wDirty)
        of msgClose:
          if test(frame, wFramed):
            delFrame(win, frame)
            # UnMark Framed
            clear(frame, wFramed)
    else: trigger(win.root, signal)
  # Update -> Layout Root
  if test(win.root, wUpdate):
    update(win.root)
  if any(win.root, 0x000C):
    layout(win.root)
    update(win.surf)
  for frame in forward(win):
    if test(frame, wUpdate):
      update(frame)
    if any(frame, 0x000C):
      layout(frame)
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
  # Render floating frames
  for frame in forward(win):
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