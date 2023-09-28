from nogui/ux/prelude import
  GUIRect, GUIWidget, getApp

# --------------------
# Widget Dock Snapping
# --------------------

type
  UXDockSide* = enum
    dockTop
    dockLeft
    dockRight
    dockBottom
    # No Docking
    dockAlone
  # Callback Moving
  DockMove* = object
    x*, y*: int32
  DockSnap* = object
    side*: UXDockSide
    x*, y*: int32

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

proc snap*(a, b: GUIWidget): DockSnap =
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
  DockSnap(side: side, x: x, y: y)
