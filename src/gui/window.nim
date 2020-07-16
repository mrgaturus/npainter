# Import Modules
import ../logger
import ../libs/egl
import x11/xlib, x11/x
import widget, event, render
# Import Somes
from timer import 
  walkTimers, sleep
from config import metrics
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
    ctx: CTXRender
    state: GUIState
    # GUI Widgets
    root: GUIWidget
    above: GUIWidget
    last: GUIWidget
    # Cache Widgets
    hold: GUIWidget
    focus: GUIWidget
    hover: GUIWidget

const LC_ALL = 6 # Hardcopied from gcc header
proc setlocale(category: cint, locale: cstring): cstring
  {.cdecl, importc, header: "<locale.h>".}

# -----------------------------
# X11/EGL WINDOW CREATION PROCS
# -----------------------------

proc createXIM(win: var GUIWindow) =
  if setlocale(LC_ALL, "").isNil or XSetLocaleModifiers("").isNil:
    log(lvWarning, "proper C locale not found")
  win.xim = XOpenIM(win.display, nil, nil, nil)
  win.xic = XCreateIC(win.xim, XNInputStyle, XIMPreeditNothing or
      XIMStatusNothing, XNClientWindow, win.xID, nil)
  if win.xic == nil:
    log(lvWarning, "failed creating XIM context")

proc createXWindow(x11: PDisplay, w, h: uint32): TWindow =
  var # Attributes and EGL
    attr: TXSetWindowAttributes
  attr.event_mask =
    KeyPressMask or
    KeyReleaseMask or
    ButtonPressMask or
    ButtonReleaseMask or
    PointerMotionMask or
    StructureNotifyMask
  # Get Default Root Window From Display
  let root = DefaultRootWindow(x11)
  # -- Create X11 Window With Default Flags
  result = XCreateWindow(x11, root, 0, 0, w, h, 0, 
    CopyFromParent, CopyFromParent, nil, CWEventMask, addr attr)
  if result == 0: # Check if Window was created properly
    log(lvError, "failed creating X11 window")

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
  # Get EGL Display from X11 Display
  eglDsp = eglGetDisplay(win.display)
  # Initialize EGL
  ok = ok and eglInitialize(eglDsp, ignore.addr, ignore.addr)
  # Choose EGL Configuration for Standard OpenGL
  ok = ok and eglChooseConfig(eglDsp, 
    cast[ptr EGLint](attEGL.unsafeAddr),
    eglCfg.addr, 1, cfgNum.addr) and cfgNum != 0
  # Create Context and Window Surface
  eglCtx = eglCreateContext(eglDsp, eglCfg, EGL_NO_CONTEXT, 
    cast[ptr EGLint](attCTX.unsafeAddr))
  # Check if EGL Context was created properly
  if not ok or eglDsp.pointer.isNil or 
      eglCfg.pointer.isNil or eglCtx.pointer.isNil:
    log(lvError, "failed creating EGL context"); return
  # Create EGL Surface and make it current
  eglSur = eglCreateWindowSurface(eglDsp, eglCfg, 
    win.xID, cast[ptr EGLint](attSUR.unsafeAddr))
  if eglSur.pointer.isNil or not # Check if was created properly
      eglMakeCurrent(eglDsp, eglSur, eglSur, eglCtx):
    log(lvError, "failed creating EGL surface"); return
  # -- Load GL functions and check it
  if not gladLoadGL(eglGetProcAddress):
    log(lvError, "failed loading GL functions"); return
  # Save new EGL Context
  win.eglDsp = eglDsp
  win.eglCfg = eglCfg
  win.eglCtx = eglCtx
  win.eglSur = eglSur

proc newGUIWindow*(w, h: int32, global: pointer): GUIWindow =
  if not isNil(metrics.opaque): # Check if there is an instance
    log(lvWarning, "window already created, software malformed")
  # Create new X11 Display
  result.display = XOpenDisplay(nil)
  if isNil(result.display):
    log(lvError, "failed opening X11 display")
  # Create a X11 Window
  result.xID = # With Initial Dimensions
    createXWindow(result.display, uint32 w, uint32 h)
  metrics.width = w; metrics.height = h
  # Create X11 Input Manager
  result.createXIM() # UTF8
  result.state.utf8buffer(32)
  # Create EGL Context
  result.createEGL() # Disable VSync
  discard eglSwapInterval(result.eglDsp, 0)
  # Create CTX Renderer
  result.ctx = newCTXRender()
  # Alloc GUI Signal Queue
  newQueue(global)

# -----------------------
# WINDOW OPEN/CLOSE PROCS
# -----------------------

proc open*(win: var GUIWindow, root: GUIWidget): bool =
  # Set the new root at first and next
  win.root = root; win.last = root
  # Root has Window and Frame Signals
  root.flags = wStandard or wOpaque
  # Set to Global Dimensions
  root.rect.w = metrics.width
  root.rect.h = metrics.height
  # Shows the Window on the screen
  result = XMapWindow(win.display, win.xID) != BadWindow
  discard XSync(win.display, 0) # Wait for show it
  # Set Renderer Viewport Dimension
  viewport(win.ctx, metrics.width, metrics.height)
  # Mark root as Dirty
  set(win.root, wDirty)

proc close*(win: var GUIWindow) =
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
# WINDOW FLOATING PRIVATE PROCS
# --------------------

# --- Add Helpers ---
proc addLeft(pivot: GUIWidget, frame: GUIWidget) {.inline.} =
  # Add to right of widget prev
  frame.prev = pivot.prev
  pivot.prev.next = frame
  # Add to left of widget
  frame.next = pivot
  pivot.prev = frame

# Guaranted to be added last to the list
proc addLast(last: var GUIWidget, frame: GUIWidget) {.inline.} =
  frame.next = nil
  # Prev allways exist
  frame.prev = last
  last.next = frame
  # Last is frame
  last = frame

proc addFrame(win: var GUIWindow, frame: GUIWidget) =
  # Add to left of head of stack or to tail
  if test(frame, wStacked):
    if isNil(win.above):
      win.above = frame
    addLast(win.last, frame)
  elif isNil(win.above): 
    addLast(win.last, frame)
  else: addLeft(win.above, frame)
  # Handle FrameIn
  handle(frame, inFrame)
  # Mark Visible and Dirty
  set(frame, wFrameOpen)

proc delFrame(win: var GUIWindow, frame: GUIWidget) =
  # Unfocus if was focused
  if frame == win.focus:
    handle(frame, outFocus)
    clear(frame, wFocus)
    # Remove focus
    win.focus = nil
  # Unhover if has hover or grab
  if frame == win.hover:
    handle(frame, outHover)
    clear(frame, wHoverGrab)
    # Remove Hover
    win.hover = nil
  # Unhold if is holded
  if frame.test(wHold):
    handle(frame, outHold)
    clear(frame, wHold)
    # Remove Hold
    if frame == win.hold:
      win.hold = nil
  # Handle FrameOut
  handle(frame, outFrame)
  # Unmark Visible
  clear(frame, wFrameOpen)
  # Check if above is removed
  if frame == win.above:
    win.above = frame.next
  # Change next prev or last
  if frame == win.last:
    win.last = frame.prev
  else: frame.next.prev = frame.prev
  # Change prev next
  frame.prev.next = frame.next
  # Remove next and prev
  frame.next = nil
  frame.prev = nil

# --- Mark As Top Level ---
proc elevateFrame(win: var GUIWindow, frame: GUIWidget) =
  if frame != win.root and frame != win.last:
    # Remove frame from it's position
    frame.prev.next = frame.next
    frame.next.prev = frame.prev
    # Next is nil because is last
    frame.next = nil
    # Move frame to last
    frame.prev = win.last
    win.last.next = frame
    win.last = frame

# ---------------------------------
# GUI WINDOW MAIN LOOP HELPER PROCS
# ---------------------------------

# Grab X11 Window
proc grab(win: var GUIWindow, widget: GUIWidget, evtype: int32) =
  if evtype == ButtonPress:
    # Grab X11 Window Mouse Input
    discard XGrabPointer(win.display, win.xID, 0,
        ButtonPressMask or ButtonReleaseMask or PointerMotionMask,
        GrabModeAsync, GrabModeAsync, None, None, CurrentTime)
    # Grab Current Widget
    widget.set(wGrab)
    # Elevate Frame if is not Stacked
    let frame = widget.frame
    if not test(frame, wStacked):
      elevateFrame(win, frame)
  elif evtype == ButtonRelease:
    # UnGrab X11 Mouse Input
    discard XUngrabPointer(win.display, CurrentTime)
    # UnGrab Current Widget
    widget.clear(wGrab)

proc focus(win: var GUIWindow, widget: GUIWidget) =
  if widget != win.focus:
    # Handle Focus Out
    if not isNil(win.focus):
      handle(win.focus, outFocus)
      clear(win.focus, wFocus)
    # Handle Focus In
    handle(widget, inFocus)
    widget.flags = # Put Flag
      widget.flags or wFocus
    # Replace Focus
    win.focus = widget

proc step(win: var GUIWindow, back: bool) =
  var widget = win.focus
  if not isNil(widget.parent):
    widget = step(widget, back)
    if widget != win.focus:
      # Handle Focus Out
      handle(win.focus, outFocus)
      clear(win.focus, wFocus)
      # Handle Focus In
      handle(widget, inFocus)
      widget.flags = # Put Flag
        widget.flags or wFocus
      # Change Focus
      win.focus = widget

proc hold(win: var GUIWindow, widget: GUIWidget) =
  if widget != win.hold and isNil(win.above):
    # Handle Hold Out
    if not isNil(win.hold):
      handle(win.hold, outHold)
      clear(win.hold, wHold)
    # Handle Focus Out
    if not isNil(win.focus):
      handle(win.focus, outFocus)
      clear(win.focus, wFocus)
    # Handle Hold In
    handle(widget, inHold)
    widget.flags = # Put Flag
      widget.flags or wHold
    # Replace Hold
    win.hold = widget

proc check(win: var GUIWindow, widget: GUIWidget) =
  if widget == win.focus and 
    not widget.test(wFocusCheck):
    # Handle Widget Unfocus
    widget.handle(outFocus)
    widget.clear(wFocus)
    # Remove Widget Focus
    win.focus = nil
  if widget == win.hold and 
    not widget.test(wHold):
    # Handle Widget UnHold
    widget.handle(outHold)
    # Remove Widget Hold
    win.hold = nil

proc find(win: var GUIWindow, state: ptr GUIState): GUIWidget =
  case state.eventType
  of evMouseMove, evMouseClick, evMouseRelease, evMouseAxis:
    if not isNil(win.hover) and test(win.hover, wGrab):
      result = win.hover # Grabbed Inside
    elif isNil(win.above): # Not Stacked
      if isNil(win.hold): # Find Frames
        for widget in reverse(win.last):
          if pointOnArea(widget, state.mx, state.my):
            result = widget; break # Frame Found
      else: result = win.hold
    else: # Stacked
      for widget in reverse(win.last):
        if widget.next == win.above: break
        if widget.test(wHold) or pointOnArea(widget, state.mx, state.my):
          result = widget; break # Frame Found
      # Use Holded Widget if not found
      if isNil(result): result = win.hold
    # Check if is Nil
    if isNil(result):
      if not isNil(win.hover):
        handle(win.hover, outHover)
        clear(win.hover, wHover)
        # Remove Hover
        win.hover = nil
    # Check if is grabbed of holded
    elif result.any(wGrab or wHold):
      if pointOnArea(result, state.mx, state.my):
        result.set(wHover)
      else: result.clear(wHover)
    # Check if is at the same frame
    elif not isNil(win.hover) and result == win.hover.frame:
      result = # Find Interior Widget
        find(win.hover, state.mx, state.my)
      if result != win.hover:
        # Handle Hover Out
        handle(win.hover, outHover)
        clear(win.hover, wHover)
        # Handle Hover In
        result.handle(inHover)
        result.set(wHover)
        # Replace Hover
        win.hover = result
    else: # Not at the same frame
      if not isNil(win.hover):
        handle(win.hover, outHover)
        clear(win.hover, wHover)
      result = # Find Interior Widget
        find(result, state.mx, state.my)
      # Handle Hover In
      result.handle(inHover)
      result.set(wHover)
      # Replace Hover
      win.hover = result
  of evKeyDown, evKeyUp:
    if not isNil(win.focus):
      return win.focus # Use Normal focus
    elif not isNil(win.above): # Stacked
      for widget in reverse(win.above):
        if widget.next == win.above: break
        if widget.test(wHold):
          result = widget
          break # Hold Found
    if isNil(result): result = win.hold

# --------------------------
# GUI WINDOW MAIN LOOP PROCS
# --------------------------

proc handleEvents*(win: var GUIWindow) =
  var event: TXEvent
  # Input Event Handing
  while XPending(win.display) != 0:
    discard XNextEvent(win.display, addr event)
    if XFilterEvent(addr event, 0) != 0:
      continue
    case event.theType:
    of Expose: discard
    of ConfigureNotify: # Resize
      let rect = addr win.root.rect
      if event.xconfigure.window == win.xID and
          (event.xconfigure.width != rect.w or
          event.xconfigure.height != rect.h):
        rect.w = event.xconfigure.width
        rect.h = event.xconfigure.height
        # Set Global Metrics
        metrics.width = rect.w
        metrics.height = rect.h
        # Set Renderer Viewport
        viewport(win.ctx, rect.w, rect.h)
        # Relayout and Redraw GUI
        set(win.root, wDirty)
    else: # Check if the event is valid for be processed by a widget
      if translateXEvent(win.state, win.display, addr event, win.xic):
        let # Avoids win.state everywhere
          state = addr win.state
          tabbed = state.eventType == evKeyDown and
            (state.key == RightTab or state.key == LeftTab)
        # Find Widget for Process Event
        if tabbed and not isNil(win.focus):
          step(win, state.key == LeftTab)
        else: # Process Event
          let found = find(win, addr win.state)
          # Check if was found
          if not isNil(found):
            # Grab/UnGrab x11 window and widget
            win.grab(found, event.theType)
            # Procces Event
            event(found, state)
            # Check Focus and Hold
            check(win, found)

proc handleSignals*(win: var GUIWindow): bool =
  for signal in pollQueue():
    # is GUI Callback?
    if callSignal(signal): continue
    elif isNil(signal.id):
      case WindowSignal(signal.msg)
      of msgOpenIM: XSetICFocus(win.xic)
      of msgCloseIM: XUnsetICFocus(win.xic)
      of msgTerminate: return true
      else: discard
    else: # Process Widget Signal
      let widget = cast[GUIWidget](signal.id)
      case WidgetSignal(signal.msg)
      of msgOpen, msgClose:
        if not isNil(widget) and widget != win.root:
          if signal.msg == ord(msgOpen) and
              not test(widget, wFramed):
            addFrame(win, widget)
          elif signal.msg == ord(msgClose) and
              test(widget, wFramed):
            delFrame(win, widget)
      of msgFocus: focus(win, widget)
      of msgHold: hold(win, widget)
      of msgDirty: dirty(widget)
      of msgTrigger: notify(widget, signal)
      # Check Focus and Hold
      check(win, widget)
  # Still Alive
  return false

proc handleTimers*(win: var GUIWindow) =
  for widget in walkTimers():
    widget.update()
    # Check Focus and Hold
    check(win, widget)

proc render*(win: var GUIWindow) =
  begin(win.ctx) # -- Begin GUI Rendering
  for widget in forward(win.root):
    render(widget, addr win.ctx)
    # Draw Commands
    render(win.ctx)
  finish() # -- End GUI Rendering
  # Present Frame to X11/EGL
  discard eglSwapBuffers(win.eglDsp, win.eglSur)
  # 60 FPS Limit
  sleep(16)
