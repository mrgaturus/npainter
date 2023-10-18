import nogui/gui/widget
from nogui/ux/prelude import GUIRect, getApp

type
  DockSide* = enum
    dockTop
    dockDown
    dockLeft
    dockRight
    # Dock Orient
    dockOppositeX
    dockOppositeY
    # No Sides
    dockNothing
  DockSides* = set[DockSide]
  # Callback Moving
  DockMove* = object
    x*, y*: int32
  DockSnap* = object
    sides*: DockSides
    x*, y*: int32
  # Callback Resize
  DockResize* = object
    sides*: DockSides
    # Pivot Capture
    rect*: GUIRect
    x*, y*: int32
  # Callback Watching
  DockReason* = enum
    dockWatchMove
    dockWatchResize
    dockWatchClose
    dockWatchRelease
    # Grouping Reasons
    groupWatchMove
    groupWatchClose
    groupWatchRelease
  DockWatch* = object
    reason*: DockReason
    p*: DockMove
    # Watch Target
    opaque*: pointer

# ------------------
# Widget Dock Resize
# ------------------

proc resizePivot*(r: GUIRect, x, y, thr: int32): DockResize =
  let
    x0 = x - r.x
    y0 = y - r.y
  var sides: DockSides
  # Check Horizontal Sides
  if x0 >= r.w - thr: sides.incl dockRight
  elif x0 < thr: sides.incl dockLeft
  # Check Vertical Sides
  if y0 >= r.h - thr: sides.incl dockDown
  elif y0 < thr: sides.incl dockTop
  # Create New Pivot
  DockResize(
    x: x, y: y,
    rect: r,
    sides: sides)

proc delta*(pivot: DockResize, x, y: int32): GUIRect =
  let 
    sides = pivot.sides
    dx = x - pivot.x
    dy = y - pivot.y
  # Down-Right Expanding
  if dockDown in sides: 
    result.h = dy
  if dockRight in sides: 
    result.w = dx
  # Top-Left Expanding
  if dockTop in sides:
    result.y = dy
    result.h = -dy
  if dockLeft in sides:
    result.x = dx
    result.w = -dx

proc resize*(pivot: DockResize, x, y: int32): GUIRect =
  result = pivot.rect
  let 
    sides = pivot.sides
    dx = x - pivot.x
    dy = y - pivot.y
  # Down-Right Expanding
  if dockDown in sides: 
    result.h += dy
  if dockRight in sides: 
    result.w += dx
  # Top-Left Expanding
  if dockTop in sides:
    result.y += dy
    result.h -= dy
  if dockLeft in sides:
    result.x += dx
    result.w -= dx

proc apply*(self: GUIWidget, r: GUIRect) =
  let m = addr self.metrics
  # Clamp Dimensions
  m.w = int16 max(m.minW, r.w)
  m.h = int16 max(m.minH, r.h)
  # Apply Position, Avoid Moving Side
  if r.x != m.x: m.x = int16 r.x - m.w + r.w
  if r.y != m.y: m.y = int16 r.y - m.h + r.h
  # Action Update
  self.set(wDirty)

# --------------------
# Widget Dock Grouping
# --------------------

proc groupSide*(r: GUIRect, p: DockMove, thr: int32): DockSide =
  # Move Point As Relative
  let
    x = p.x - r.x
    y = p.y - r.y
  # Check Inside Rectangle
  if x >= 0 and y >= 0 and x < r.w and y < r.h:
    # Check Horizontal Sides
    if x >= 0 and x <= thr: dockLeft
    elif x >= r.w - thr and x < r.w: dockRight
    # Check Vertical Sides
    elif y >= 0 and y <= thr: dockTop
    elif y >= r.h - thr and y < r.h: dockDown
    # Otherwise Nothing
    else: dockNothing
  else: dockNothing

proc groupHint*(r: GUIRect, side: DockSide, thr: int32): GUIRect =
  result = r
  case side
  of dockLeft:
    result.w = thr
  of dockRight:
    result.x += r.w - thr
    result.w = thr
  of dockTop:
    result.h = thr
  of dockDown:
    result.y += result.h - thr
    result.h = thr
  else: discard

proc groupOrient*(m: GUIMetrics, clip: GUIRect): DockSide =
  let
    x0 = m.x
    x1 = x0 + m.w
    # Calculate Distances
    dx0 = x0 - clip.x
    dx1 = clip.x + clip.w - x1
  # Check Which is Near to a Side
  if dx1 < dx0: dockLeft
  else: dockRight

# --------------------
# Widget Dock Snapping
# --------------------

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
    elif checkTop(b0, a0, thr): dockDown
    elif checkLeft(b0, a0, thr): dockRight
    # No Sticky Found
    else: dockNothing
  # Calculate Sticky Position
  let (x, y) =
    case side
    of dockTop: (a0.x, b0.y + b0.h)
    of dockLeft: (b0.x + b0.w, a0.y)
    of dockDown: (a0.x, b0.y - a0.h)
    of dockRight: (b0.x - a0.w, a0.y)
    else: (a0.x, a0.y)
  # Return Sticky Info
  DockSnap(sides: {side}, x: x, y: y)
