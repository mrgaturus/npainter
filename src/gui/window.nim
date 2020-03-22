# TODO: Use ibus instead XIM

import ../logger
import widget, event, render
import x11/xlib, x11/x
import ../libs/egl

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
    # Auxiliar Flags
    aux: GUIFlags

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
    log(lvWarning, "proper C locale not found")
  win.xim = XOpenIM(win.display, nil, nil, nil)
  win.xic = XCreateIC(win.xim, XNInputStyle, XIMPreeditNothing or
      XIMStatusNothing, XNClientWindow, win.xID, nil)
  if win.xic == nil:
    log(lvWarning, "failed creating XIM context")

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
  # Check if EGL is created properly
  if eglDsp.pointer.isNil or
      eglCfg.pointer.isNil or
      eglCtx.pointer.isNil or
      eglSur.pointer.isNil:
    log(lvError, "failed creating EGL context")
    return
  # Check if GL procs was loaded
  if not gladLoadGL(eglGetProcAddress):
    log(lvError, "failed loading GL functions")
    return
  # Save new EGL Context
  win.eglDsp = eglDsp
  win.eglCfg = eglCfg
  win.eglCtx = eglCtx
  win.eglSur = eglSur

# --------------------
# WINDOW CREATION PROCS
# --------------------

proc newGUIWindow*(root: GUIWidget, global: pointer): GUIWindow =
  # Create new X11 Display
  result.display = XOpenDisplay(nil)
  if isNil(result.display):
    log(lvError, "failed opening X11 display")
  # Initialize X11 Window
  result.xID = createXWindow(result.display, 
    uint32(root.rect.w), uint32(root.rect.h)
  ) # Use root initial dimensions
  # Initialize XIM/XIC
  result.createXIM()
  # Alloc a 32 byte UTF8Buffer
  result.state.utf8buffer(32)
  # Initialize EGL and GL
  result.createEGL()
  # Initialize CTX Renderer
  result.ctx = newCTXRender()
  # Disable VSync - Avoid Input Lag
  discard eglSwapInterval(result.eglDsp, 0)
  # Root has Window and Frame Signals
  root.signals = {WindowID, FrameID}
  root.flags = wStandard or wOpaque
  # Set the new root at first and next
  result.root = root
  result.last = root
  # Alloc GUIQueue in Global
  allocQueue(global)

# --------------
# WINDOW EXEC/EXIT
# --------------

proc exec*(win: var GUIWindow): bool =
  # Shows the win on the screen
  result = XMapWindow(win.display, win.xID) != BadWindow
  discard XSync(win.display, 0) # Wait for show it
  # Set Viewport To Rect for First Time
  viewport(win.ctx, win.root.rect.w, win.root.rect.h)
  # Mark root as Dirty
  set(win.root, wDirty)

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
  set(frame, 0x19)

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
  clear(frame, 0x19)
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

# --------------------
# WINDOW RUNNING PROCS
# --------------------

# Grab X11 Window
proc grab(win: var GUIWindow, widget: GUIWidget, evtype: int32) =
  if evtype == ButtonPress:
    # Grab X11 Window Mouse Input
    discard XGrabPointer(win.display, win.xID, 0,
        ButtonPressMask or ButtonReleaseMask or PointerMotionMask,
        GrabModeAsync, GrabModeAsync, None, None, CurrentTime)
    # Grab Current Widget
    widget.set(wGrab)
    # Elevate if is a normal frame
    if not widget.test(wStacked):
      elevateFrame(win, widget)
  elif evtype == ButtonRelease:
    # UnGrab X11 Mouse Input
    discard XUngrabPointer(win.display, CurrentTime)
    # UnGrab Current Widget
    widget.clear(wGrab)

proc checkHandlers(win: var GUIWindow, widget: GUIWidget) =
  var check = win.aux xor widget.flags
  # -- Check/Change Hold
  if (check and wHold) == wHold:
    if (widget.flags and wHold) == wHold:
      # Change Hold is not stacked
      if not widget.test(wStacked) and widget != win.hold:
        # Unhold prev widget
        if not isNil(win.hold):
          handle(win.hold, outHold)
          clear(win.hold, wHold)
        # Change Current Hold
        win.hold = widget
      # Unfocus if is focused
      if not isNil(win.focus):
        handle(win.focus, outFocus)
        clear(win.focus, wFocus)
        # Remove current focus
        win.focus = nil
      # Handle Holded
      widget.handle(inHold)
    else: # Remove Hold
      widget.handle(outHold)
      # Remove current hold
      if widget == win.hold:
        win.hold = nil
  # -- Check/Change Focus
  if (check and wFocus) == wFocus:
    # Check if is enabled and visible
    check = (widget.flags and 0x4b0) xor 0x30'u16
    if check == wFocus:
      if widget != win.focus:
        let focus = win.focus
        # Unfocus prev widget
        if not isNil(focus):
          focus.handle(outFocus)
          focus.clear(wFocus)
        # Change Current Focus
        widget.handle(inFocus)
        win.focus = widget
    elif widget == win.focus:
      widget.handle(outFocus)
      widget.clear(wFocus)
      # Remove current focus
      win.focus = nil
    elif (check and wFocus) == wFocus and check > wFocus:
      widget.clear(wFocus) # Invalid focus

proc findWidget(win: var GUIWindow, state: ptr GUIState,
    tabbed: bool): GUIWidget =
  case state.eventType
  of evMouseMove, evMouseClick, evMouseRelease, evMouseAxis:
    if not isNil(win.hover) and test(win.hover, wGrab):
      result = win.hover
    elif isNil(win.above): # Not Stacked
      if isNil(win.hold): # Find on frames if was not holded
        for widget in reverse(win.last):
          if pointOnArea(widget, state.mx, state.my):
            result = widget
            break # A frame was hovered
      else: result = win.hold
    else: # Stacked
      for widget in reverse(win.last):
        if widget.next == win.above: break
        if widget.test(wHold) or pointOnArea(widget, state.mx, state.my):
          result = widget
          break # A popup was hovered or is holded
      # Use Holded Widget if a popup was not found
      if isNil(result): result = win.hold
    # Change current hover
    if result != win.hover:
      # Unhover prev hover
      if not isNil(win.hover):
        handle(win.hover, outHover)
        clear(win.hover, wHover)
      # Make hover current
      if not isNil(result):
        result.handle(inHover)
        result.set(wHover)
      # Change current hover
      win.hover = result
    # If is grabbed of holded, check if is in area
    elif not isNil(result) and test(result, wGrab or wHold):
      if pointOnArea(result, state.mx, state.my):
        result.set(wHover)
      else: result.clear(wHover)
  of evKeyDown, evKeyUp:
    if not isNil(win.focus) or tabbed:
      return win.focus # Use normal focus
    elif not isNil(win.above): # Stacked
      for widget in reverse(win.above):
        if widget.next == win.above: break
        if widget.test(wHold):
          result = widget
          break # Hold Found
    if isNil(result): result = win.hold

proc handleEvents(win: var GUIWindow) =
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
          found = findWidget(win, state, tabbed)
        # Process event if was found
        if not isNil(found):
          # Save Prev Flags
          win.aux = found.flags
          # Grab/UnGrab x11 window and widget
          win.grab(found, event.theType)
          # Step focus or process event
          if tabbed: # Step Focused if Tabbed
            step(found, state.key == LeftTab)
          else: event(found, state)
          # Check Handlers -Focus and Hold-
          checkHandlers(win, found)

proc handleSignals(win: var GUIWindow): bool =
  for signal in pollQueue():
    # is GUI Callback?
    if callSignal(signal):
      continue
    # is GUI Signal?
    case signal.id:
    of WindowID: # Window Signal
      case WindowMsg(signal.msg):
      of msgTerminate: return false
      of msgFocusIM: XSetICFocus(win.xic)
      of msgUnfocusIM: XUnsetICFocus(win.xic)
    of FrameID: # Frame Signal Operations
      let frame = convert(signal.data, GUIWidget)[]
      if not isNil(frame) and frame != win.root:
        case FrameMsg(signal.msg)
        of msgClose: # Remove frame from window
          if test(frame, wFramed):
            delFrame(win, frame)
        of msgOpen: # Add frame to window
          if not test(frame, wFramed):
            addFrame(win, frame)
    else: # Process signal to widgets
      for widget in forward(win.root):
        if signal.id in widget:
          # Save Prev Flags
          win.aux = widget.flags
          # Trigger Signal
          trigger(widget, signal)
          # Check if hold or focus is changed
          checkHandlers(win, widget)
  # Event Loop Still Alive
  return true

# Use this in your main loop
proc tick*(win: var GUIWindow): bool =
  # Event -> Signal
  handleEvents(win)
  result = handleSignals(win)
  begin(win.ctx) # -- Begin GUI Rendering
  # Update -> Layout -> Render
  for widget in forward(win.root):
    # is Update and/or Layout marked?
    if any(widget, 0x0E):
      # Save Prev Flags
      win.aux = widget.flags
      # Do Layout or Update
      if test(widget, wUpdate):
        update(widget)
      if any(widget, 0x0C):
        layout(widget)
        # Remove layout/dirty flags
        widget.flags = # Unmark layout
          widget.flags and not 0x0C'u16
      # Check Handlers
      checkHandlers(win, widget)
    # Draw and Render Widget
    clear(win.ctx) # Clear Vertex
    draw(widget, addr win.ctx)
    render(win.ctx) # Render VAO
  finish() # -- End GUI Rendering
  # Present to X11/EGL Window
  discard eglSwapBuffers(win.eglDsp, win.eglSur)
  # TODO: FPS Strategy
  sleep(16)
