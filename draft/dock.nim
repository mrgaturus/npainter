from nogui/pack import icons
from nogui/builder import child
from nogui/ux/layouts import level
from nogui/ux/widgets/button import UXIconButton, button
import nogui/ux/[prelude, labeling]

# ------------------
# Widget Dock Sticky
# ------------------

type
  UXDockSide* = enum
    dockTop
    dockLeft
    dockRight
    dockBottom
    # No Docking
    dockAlone
  # Callback Moving
  DockMove = object
    x, y: int32
  DockPacket = object
    side: UXDockSide
    x, y: int32

proc checkTop(a, b: GUIRect, thr: int32): bool =
  if abs(a.y - b.y - b.h) < thr:
    let
      ax0 = a.x
      ax1 = a.x + a.w
      # Sticky Area
      x0 = b.x
      x1 = x0 + b.w
      # X Distance Check
      check0 = ax0 >= x0 and ax0 <= x1
      check1 = ax1 >= x0 and ax1 <= x1
    # Check if is sticky to top side
    result = check0 and check1

proc checkLeft(a, b: GUIRect, thr: int32): bool =
  if abs(a.x - b.x - b.w) < thr:
    let
      ay0 = a.y
      ay1 = a.y + a.h
      # Sticky Area
      y0 = b.y
      y1 = y0 + b.h
      # X Distance Check
      check0 = ay0 >= y0 and ay0 <= y1
      check1 = ay1 >= y0 and ay1 <= y1
    # Check if is sticky to top side
    result = check0 and check1

proc sticky(a, b: GUIWidget): DockPacket =
  let
    a0 = a.rect
    b0 = b.rect
    # Sticky Threshold
    thr = getApp().font.asc shr 1
  # Calculate Where is
  let side = 
    if checkTop(a0, b0, thr): dockTop
    elif checkLeft(a0, b0, thr): dockLeft
    # Check Opposite Dock Sides
    elif checkTop(b0, a0, thr): dockBottom
    elif checkLeft(b0, a0, thr): dockRight
    # No Sticky
    else: dockAlone
  # Calculate Sticky Position
  let (x, y) =
    case side
    of dockTop: (a0.x, b0.y + b0.h)
    of dockLeft: (b0.x + b0.w, a0.y)
    of dockBottom: (a0.x, b0.y - a0.h)
    of dockRight: (b0.x - a0.w, a0.y)
    else: (a0.x, a0.y)
  # Return Sticky Info
  DockPacket(side: side, x: x, y: y)

# ------------------
# Widget Dock Header
# ------------------

icons 16:
  collapse := "collapse.svg"
  context := "context.svg"

widget UXDockHeader:
  attributes:
    title: string
    icon: CTXIconID
    lm: GUILabelMetrics
    # Moving Callback
    onmove: GUICallbackEX[DockMove]
    {.cursor.}: [bndock, bnctx]: UXIconButton
    # Click Pivot
    pivot: DockMove

  new dockhead(title: string, icon = CTXIconEmpty):
    result.title = title
    result.icon = icon

  proc actions(ondock, onctx: GUICallback) =
    let 
      bndock = button(iconCollapse, ondock)
      bnctx = button(iconContext, onctx)
    # Button Helpers
    self.add:
      level().child:
        bndock
        bnctx
    # Store Buttons
    self.bndock = bndock
    self.bnctx = bnctx

  method update =
    discard

  method layout =
    discard

  method draw(ctx: ptr CTXRender) =
    discard

  method event(state: ptr GUIState) =
    discard

# ----------------
# Widget Dock Body
# ----------------

type
  UXDockBody* = object
    widget* {.cursor.}: GUIWidget
    onctx*: GUICallback
  # Avoid Heavy GC
  UXDockCursor = distinct pointer

proc dockbody*(w: GUIWidget, onctx = GUICallback): UXDockBody =
  result.widget = w
  result.onctx = onctx

# ---------------------
# Widget Dock Container
# ---------------------

widget UXDock:
  attributes:
    {.cursor.}:
      head: UXDockHeader
      widget: GUIWidget
    # Sticky Window Region
    {.public.}:
      region: ptr GUIRect
    # Dock Sticky Properties
    screen: set[UXDockSide]
    [top, left, right, bottom]: seq[UXDockCursor]

  # -- Dock Layout --
  method update =
    discard

  method layout =
    discard

  # -- Dock Interaction --
  callback cbMove(p: DockMove):
    discard

  callback cbResize(p: DockMove):
    discard

  method event(ctx: ptr GUIState) =
    discard

  # -- Dock Drawing --
  method draw(ctx: ptr CTXRender) =
    discard

  # -- Dock Creation --
  proc init(title: string, icon: CTXIconID, body: UXDockBody) =
    let w {.cursor.} = body.widget
    # Create Dock Title
    let head = dockhead(title)
    head.onmove = self.cbMove
    head.actions(body.onctx, body.onctx)
    # Add Widgets
    self.add head
    self.add w
    # Define as Frame
    self.flags = wMouse
    self.kind = wgFrame
    # Set Widgets
    self.head = head
    self.widget = w

  new dock(title: string, body: UXDockBody):
    result.init(title, CTXIconEmpty, body)

  new dock(title: string, icon: CTXIconID, body: UXDockBody):
    result.init(title, icon, body)
