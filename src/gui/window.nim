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
    # GUI Render Context & State
    ctx: GUIContext
    state: GUIState
    # GUI Widgets and frames
    root: GUIContainer
    wLast: GUIWidget
    sLast: GUIWidget
    # Cache Frames
    focus: GUIWidget
    wHover: GUIWidget
    sHover: GUIWidget

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
  result.ctx = newGUIContext()
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
    result.wLast = root
  # Alloc Global GUIQueue with Global
  allocQueue(global)

# --------------------
# WINDOW GUI CREATION PROCS
# --------------------

proc add*(win: var GUIWindow, widget: GUIWidget, region: bool = true) =
  if region: createRegion(win.ctx, addr widget.rect)
  # Add Widget to Root
  add(win.root, widget)

# -----------------------
# WINDOW WIDGET ITERATORS
# -----------------------

# Root -> Last Frame
iterator forward(root: GUIWidget): GUIWidget =
  var frame = root
  while frame != nil:
    yield frame
    frame = frame.next

# Last Frame -> Root
iterator reverse(last: GUIWidget): GUIWidget =
  var frame = last
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
  resize(win.ctx, addr win.root.rect)
  allocRegions(win.ctx)

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

# --------------------
# WINDOW FLOATING PRIVATE PROCS
# --------------------

# --- Helpers ---
proc addLeft(last: GUIWidget, frame: GUIWidget) =
  # Add to right of widget prev
  frame.prev = last.prev
  last.prev.next = frame
  # Add to left of widget
  frame.next = last
  last.prev = frame

# Guaranted to be added wLast to the list
proc addLast(last: var GUIWidget, frame: GUIWidget) =
  frame.next = nil
  # Prev allways exist
  frame.prev = last
  last.next = frame
  # Last is frame
  last = frame

# --- Add or Delete ---
proc addStacked(win: var GUIWindow, frame: GUIWidget) =
  # Create a Popup Stack using Last as First
  if test(win.wLast, wStacked):
    addLast(win.sLast, frame)
  else: # Mark as have a stack
    addLast(win.wLast, frame)
    win.sLast = win.wLast
  # Alloc or Reuse a CTXFrame
  useFrame(win.ctx, frame.surf)
  # Mark Visible and Dirty
  set(frame, 0x18)

proc addFrame(win: var GUIWindow, frame: GUIWidget) =
  if test(win.wLast, wStacked):
    addLeft(win.wLast, frame)
  else:
    addLast(win.wLast, frame)
    if frame.test(wGrab):
      if win.wHover != nil:
        hoverOut(win.wHover)
        clear(win.wHover, wHover or wGrab)
      win.wHover = frame
  # Alloc or Reuse a CTXFrame
  useFrame(win.ctx, frame.surf)
  # Mark Visible and Dirty
  set(frame, 0x18)

proc delFrame(win: var GUIWindow, frame: GUIWidget) =
  # Unfocus if was focused
  if test(frame, wFocus):
    focusOut(frame)
    clear(frame, wFocus)
    # Remove focus
    win.focus = nil
  # Unhover if has hover or grab
  if any(frame, wHover or wGrab):
    hoverOut(frame)
    clear(frame, wHover or wGrab)
    # Remove Hover
    if frame == win.wHover:
      win.wHover = nil
    elif frame == win.sHover:
      win.sHover = nil
  # Unmark Visible
  clear(frame, 0x18)
  # Unuse CTX Frame
  unuseFrame(win.ctx, frame.surf)
  # Change next prev or wLast
  if frame == win.wLast:
    if test(frame, wStacked) and
        frame != win.sLast:
      win.wLast = frame.next
    else: # There is no popup
      win.wLast = frame.prev
      win.sLast = nil
  elif frame == win.sLast:
    win.sLast = frame.prev
  else: frame.next.prev = frame.prev
  # Change prev next (first is root)
  frame.prev.next = frame.next
  # Remove next and prev
  frame.next = nil
  frame.prev = nil

# --- Mark As Top Level ---
proc elevateFrame(win: var GUIWindow, frame: GUIWidget) =
  if frame != win.root and frame != win.wLast:
    # Remove frame from it's position
    frame.prev.next = frame.next
    frame.next.prev = frame.prev
    # Next is nil because is wLast
    frame.next = nil
    # Move frame to wLast
    frame.prev = win.wLast
    win.wLast.next = frame
    win.wLast = frame

# --------------------
# WINDOW RUNNING PROCS
# --------------------

proc checkFocus(win: var GUIWindow) =
  # if is no focused properly, call focusOut
  if win.focus != nil and not test(win.focus, wFocusCheck):
    focusOut(win.focus)
    clear(win.focus, wFocus)
    # Remove focus from cache
    win.focus = nil

proc findStacked(win: var GUIWindow): GUIWidget =
  let state = addr win.state
  # Look for Mouse event o key event
  case state.eventType
  of evMouseMove, evMouseClick, evMouseRelease, evMouseAxis:
    for widget in reverse(win.sLast):
      if not widget.test(wStacked): break
      if widget.test(wGrab) or pointOnFrame(widget, state.mx, state.my):
        # A popup was hovered or is grabbed
        result = widget
        break
    # Use Grabbed Widget if a popup was not found
    if isNil(result) and not isNil(win.wHover) and test(win.wHover, wGrab):
      result = win.wHover
    # Change hover
    if result != win.sHover:
      # Unhover prev hover
      if win.sHover != nil:
        if not test(win.sHover, wGrab):
          hoverOut(win.sHover)
        clear(win.sHover, wHover)
      # Mark as hover or unhover
      if result != nil:
        if result.test(wGrab):
          if pointOnFrame(result, state.mx, state.my):
            result.set(wHover)
          else: result.clear(wHover)
        else: result.set(wHover)
      win.sHover = result
  of evKeyDown, evKeyUp:
    if isNil(win.focus) or test(win.focus, wStacked):
      result = win.focus

proc findWidget(win: var GUIWindow): GUIWidget =
  let state = addr win.state
  # Look for Mouse event o key event
  case state.eventType
  of evMouseMove, evMouseClick, evMouseRelease, evMouseAxis:
    if win.wHover != nil and test(win.wHover, wGrab):
      result = win.wHover
      if pointOnFrame(result, state.mx, state.my):
        result.set(wHover)
      else: result.clear(wHover)
    else: # Search on other frames
      for widget in reverse(win.wLast):
        if pointOnFrame(widget, state.mx, state.my):
          if win.state.eventType == evMouseClick:
            elevateFrame(win, widget)
          # A frame was hovered
          result = widget
          break
      # Unhover prev frame
      if result != win.wHover:
        if win.wHover != nil:
          hoverOut(win.wHover)
          clear(win.wHover, wHover)
        # Set wHover current
        if result != nil:
          result.set(wHover)
        win.wHover = result
  of evKeyDown, evKeyUp:
    result = win.focus

proc handleEvents(win: var GUIWindow) =
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
        win.root.set(wDirty)
    else:
      # Grab/UnGrab X11 Window
      win.grab(event.theType)
      # Process Event if is a valid gui event
      if translateXEvent(win.state, win.display, addr event, win.xic):
        # Find Widget for process event
        let found =
          if win.sLast != nil:
            findStacked(win)
          else: findWidget(win)
        # Process event if was found
        if found != nil:
          let state = addr win.state
          if state.eventType == evKeyDown and
              (state.key == RightTab or
              state.key == LeftTab):
            step(found, state.key == LeftTab)
          else:
            relative(found, state)
            event(found, state)
          # Change win focused if found is focused
          if found.test(wFocusCheck) and found != win.focus:
            if win.focus != nil:
              focusOut(win.focus)
              clear(win.focus, wFocus)
            win.focus = found

proc handleSignals(win: var GUIWindow): bool =
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
    of FrameID:
      let frame =
        convert(signal.data, GUIWidget)[]
      if frame != nil:
        case FrameMsg(signal.msg)
        of msgRegion: # Move or resize
          if frame.surf != nil:
            if region(frame.surf, frame.region):
              frame.set(wDirty)
        of msgClose: # Remove frame from window
          if frame.surf != nil:
            frameOut(frame)
            delFrame(win, frame)
        of msgOpen: # Add frame to window
          if frame.surf == nil:
            if test(frame, wStacked):
              addStacked(win, frame)
            else: addFrame(win, frame)
            # Update frame region after added
            region(frame.surf, frame.region)
    else: # Process signal to widgets
      for widget in forward(win.root):
        if signal.id in widget:
          trigger(widget, signal)
          # Change Focus if is focused and is diferent
          if widget.test(wFocusCheck) and widget != win.focus:
            if win.focus != nil:
              focusOut(win.focus)
              clear(win.focus, wFocus)
            win.focus = widget
  # Event Loop isn't terminated
  return true

# Use this in your main loop
proc tick*(win: var GUIWindow): bool =
  # Check Focus
  checkFocus(win)
  # Event -> Signal
  handleEvents(win)
  result = handleSignals(win)
  # Begin GUI Rendering
  start(win.ctx[])
  # Update -> Layout -> Render
  for widget in forward(win.root):
    if test(widget, wUpdate):
      update(widget)
    if any(widget, 0x0C):
      layout(widget)
      if widget.prev == nil:
        update(win.ctx) # Update Regions
    if test(widget, wDraw):
      makeCurrent(win.ctx, widget.surf)
      draw(widget, addr win.ctx[])
      clearCurrent(win.ctx)
    # Render root or frame
    render(win.ctx, widget.surf)
  # End GUI Rendering
  finish(win.ctx[])
  # Present to X11/EGL Window
  discard eglSwapBuffers(win.eglDsp, win.eglSur)
  # TODO: FPS Strategy
  sleep(16)
