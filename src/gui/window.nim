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
    xID: Window
    # X11 Input Method
    xim: XIM
    xic: XIC
    # EGL Context
    eglDsp: EGLDisplay
    eglCfg: EGLConfig
    eglCtx: EGLContext
    eglSur: EGLSurface
    # Main Window
    ctx: CTXRender
    state: GUIState
    root: GUIWidget
    # Last Widgets
    frame: GUIWidget
    popup: GUIWidget
    tooltip: GUIWidget
    # Cache Widgets
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

proc createXWindow(x11: PDisplay, w, h: uint32): Window =
  var # Attributes and EGL
    attr: XSetWindowAttributes
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
  # Set First Widget and Last Frame
  win.root = root; win.frame = root
  # Root is Standard and has framing protection
  root.flags = wStandard or wVisible or wChild
  # Set to Global Dimensions
  root.rect.w = metrics.width
  root.rect.h = metrics.height
  # Shows the Window on the screen
  result = XMapWindow(win.display, win.xID) != BadWindow
  discard XSync(win.display, 0) # Wait for show it
  # Set Renderer Viewport Dimensions
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

# -----------------------------
# WINDOW FLOATING PRIVATE PROCS
# -----------------------------

# -- Add Helper
proc insert(pivot, widget: GUIWidget) =
  # Add to left of widget next
  widget.next = pivot.next
  if not isNil(pivot.next):
    pivot.next.prev = widget
  # Add to right of widget
  widget.prev = pivot
  pivot.next = widget

# -- Delete Helper
proc delete(widget: GUIWidget) =
  # Check if next is not nil
  if not isNil(widget.next):
    widget.next.prev = widget.prev
  # Prev Widget is allways not nil
  widget.prev.next = widget.next
  # Remove next and prev
  widget.next = nil
  widget.prev = nil

# --- Mark As Top Level ---
proc elevate(win: var GUIWindow, widget: GUIWidget) =
  if widget != win.root and widget != win.frame:
    # Remove frame from it's position
    widget.prev.next = widget.next
    widget.next.prev = widget.prev
    # Move frame to last frame
    widget.prev = win.frame
    widget.next = win.frame.next
    # Change Prev Last Next
    if not isNil(widget.next):
      widget.next.prev = widget
    # Change Last Frame
    win.frame.next = widget
    win.frame = widget

# ---------------------------------
# GUI WINDOW MAIN LOOP HELPER PROCS
# ---------------------------------

# -- Find Widget by State
proc find(win: var GUIWindow, state: ptr GUIState): GUIWidget =
  case state.eventType
  of evMouseMove, evMouseClick, evMouseRelease, evMouseAxis:
    if not isNil(win.hover) and test(win.hover, wGrab):
      result = win.hover # Grabbed Inside
    elif isNil(win.popup): # Find Frames
      for widget in reverse(win.frame):
        if pointOnArea(widget, state.mx, state.my):
          result = widget; break # Frame Found
    else: # Find Popups
      for widget in reverse(win.popup):
        if widget == win.frame: break # Not Found
        if (widget.flags and wWalkCheck) == wPopup or
        pointOnArea(widget, state.mx, state.my):
          result = widget; break # Popup Found
    # Check if Not Found
    if isNil(result):
      if not isNil(win.hover):
        handle(win.hover, outHover)
        clear(win.hover.flags, wHover)
        # Remove Hover
        win.hover = nil
    # Check if is Grabbed
    elif result.test(wGrab):
      if pointOnArea(result, state.mx, state.my):
        result.flags.set(wHover)
      else: result.flags.clear(wHover)
    # Check if is at the same frame
    elif not isNil(win.hover) and result == win.hover.frame:
      result = # Find Interior Widget
        find(win.hover, state.mx, state.my)
      if result != win.hover:
        # Handle Hover Out
        handle(win.hover, outHover)
        clear(win.hover.flags, wHover)
        # Handle Hover In
        result.handle(inHover)
        result.flags.set(wHover)
        # Replace Hover
        win.hover = result
      # Check if is Popup and not Popup Children
      if (result.flags and wWalkCheck) == wPopup:
        if pointOnArea(result, state.mx, state.my):
          result.flags.set(wHover)
        else: result.flags.clear(wHover)
    else: # Not at the same frame
      if not isNil(win.hover):
        handle(win.hover, outHover)
        clear(win.hover.flags, wHover)
      result = # Find Interior Widget
        find(result, state.mx, state.my)
      # Handle Hover In
      result.handle(inHover)
      result.flags.set(wHover)
      # Replace Hover
      win.hover = result
  of evKeyDown, evKeyUp:
    result = # Focus Root if there is no popup
      if isNil(win.focus) and isNil(win.popup):
        win.root # Fallback
      else: win.focus # Use Focus

# -- Grab X11 Window
proc grab(win: var GUIWindow, widget: GUIWidget, evtype: int32) =
  if evtype == ButtonPress:
    # Grab X11 Window Mouse Input
    discard XGrabPointer(win.display, win.xID, 0,
        ButtonPressMask or ButtonReleaseMask or PointerMotionMask,
        GrabModeAsync, GrabModeAsync, None, None, CurrentTime)
    # Grab Current Widget
    widget.flags.set(wGrab)
    # Elevate if is a Frame
    let frame = widget.frame
    if (frame.flags and wFraming) == wFrame:
      elevate(win, frame) # Guaranted a Frame 
  elif evtype == ButtonRelease:
    # Ungrab X11 Mouse Input
    discard XUngrabPointer(win.display, CurrentTime)
    # Ungrab Current Widget
    widget.flags.clear(wGrab)

# -- Step Focus
proc step(win: var GUIWindow, back: bool) =
  var widget = win.focus
  if not isNil(widget.parent):
    widget = step(widget, back)
    if widget != win.focus:
      # Handle Focus Out
      clear(win.focus.flags, wFocus)
      handle(win.focus, outFocus)
      # Handle Focus In
      widget.flags.set(wFocus)
      widget.handle(inFocus)
      # Change Focus
      win.focus = widget

# -- Relayout Widget
proc dirty(win: var GUIWindow, widget: GUIWidget) =
  if widget.test(wVisible):
    widget.dirty()
    # Check Focus Visibility
    if not isNil(win.focus) and 
    not win.focus.visible:
      clear(win.focus.flags, wFocus)
      handle(win.focus, outFocus)
      # Remove Focus
      win.focus = nil
  widget.flags.clear(wDirty)

# -- Focus Handling
proc focus(win: var GUIWindow, widget: GUIWidget) =
  if widget != win.root and 
  widget.test(wFocusable) and 
  widget != win.focus:
    if not isNil(win.focus):
      clear(win.focus.flags, wFocus)
      handle(win.focus, outFocus)
    # Handle Focus In
    widget.flags.set(wFocus)
    widget.handle(inFocus)
    # Replace Focus
    win.focus = widget

proc check(win: var GUIWindow, widget: GUIWidget) =
  # Check if is still focused
  if widget == win.focus and 
  not widget.test(wFocusCheck):
    widget.flags.clear(wFocus)
    widget.handle(outFocus)
    # Remove Focus
    win.focus = nil

# -- Close any Frame/Popup/Tooltip
proc close(win: var GUIWindow, widget: GUIWidget) =
  if widget.test(wVisible) and 
  not widget.test(wChild):
    # is Last Frame?
    if widget == win.frame:
      win.frame = widget.prev
    # is Last Popup?
    elif widget == win.popup:
      let prev = widget.prev
      # No more popups?
      if prev == win.frame:
        win.popup = nil
      else: win.popup = prev
    # is Last Tooltip?
    elif widget == win.tooltip:
      let prev = widget.prev
      # No more tooltips?
      if prev == win.popup or
         prev == win.frame:
        win.tooltip = nil
      else: win.tooltip = prev
    # Remove from List
    widget.delete()
    # Remove Visible Flag
    widget.flags.clear(
      wVisible or wWalker)

# -- Open as Frame/Popup/Tooltip
proc frame(win: var GUIWindow, widget: GUIWidget) =
  if not widget.any(wChild or wVisible):
    insert(win.frame, widget)
    win.frame = widget
    # Remove Parent if has
    widget.parent = nil
    # Mark as Visible and Dirty
    widget.flags.set(wVisible)
    widget.set(wDirty)
  else: widget.flags.clear(wFrame)

proc popup(win: var GUIWindow, widget: GUIWidget) =
  if not widget.any(wChild or wVisible):
    if not isNil(widget.parent) and 
    test(widget.parent, wPopup or wVisible):
      insert(widget.parent, widget)
      # Change Last Popup if is after Last
      if widget.parent == win.popup:
        win.popup = widget
      # Mark as Popup Children
      widget.flags.set(wWalker)
    elif isNil(win.popup):
      insert(win.frame, widget)
      win.popup = widget
    else: # Change Last Popup
      insert(win.popup, widget)
      win.popup = widget
    # Remove Parent if has
    widget.parent = nil
    # Mark as Visible and Dirty
    widget.flags.set(wVisible)
    widget.set(wDirty)
  else: widget.flags.clear(wPopup)

proc tooltip(win: var GUIWindow, widget: GUIWidget) =
  if not widget.any(wChild or wVisible):
    if not isNil(win.tooltip):
      insert(win.tooltip, widget)
    elif not isNil(win.popup):
      insert(win.popup, widget)
    else: # Insert at Frame
      insert(win.frame, widget)
    # Change Last Tooltip
    win.tooltip = widget
    # Remove Parent if has
    widget.parent = nil
    # Mark as Visible and Dirty
    widget.flags.set(wVisible)
    widget.set(wDirty)
  else: widget.flags.clear(wTooltip)

# --------------------------
# GUI WINDOW MAIN LOOP PROCS
# --------------------------

proc handleEvents*(win: var GUIWindow) =
  var event: XEvent
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

proc handleSignals*(win: var GUIWindow): bool =
  for signal in pollQueue():
    case signal.kind
    of sCallback:
      signal.call()
    of sWidget:
      let widget =
        cast[GUIWidget](signal.id)
      case signal.msg
      of msgDirty: dirty(win, widget)
      of msgFocus: focus(win, widget)
      of msgCheck: check(win, widget)
      of msgClose: close(win, widget)
      of msgFrame: frame(win, widget)
      of msgPopup: popup(win, widget)
      of msgTooltip: tooltip(win, widget)
    of sWindow:
      case signal.w_msg
      of msgOpenIM: XSetICFocus(win.xic)
      of msgCloseIM: XUnsetICFocus(win.xic)
      of msgTerminate: return true
  # Still Alive
  return false

proc handleTimers*(win: var GUIWindow) =
  for widget in walkTimers():
    widget.update()

proc render*(win: var GUIWindow) =
  begin(win.ctx) # -- Begin GUI Rendering
  for widget in forward(win.root):
    widget.draw(addr win.ctx)
    # Render Widget Childrens
    if not isNil(widget.first):
      render(widget, addr win.ctx)
    # Draw Commands
    render(win.ctx)
  finish() # -- End GUI Rendering
  # Present Frame to X11/EGL
  discard eglSwapBuffers(win.eglDsp, win.eglSur)
  # 60 FPS Limit
  sleep(16)
