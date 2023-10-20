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
    side*: DockSide
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

proc checkTop(a, b: GUIMetrics, thr: int32): bool =
  if abs(a.y - b.y - b.h) < thr:
    let
      ax0 = a.x
      ax1 = a.x + a.w
      # Sticky Area
      x0 = b.x
      x1 = x0 + b.w
      # X Distance Check A
      check0a = ax0 >= x0 and ax0 <= x1
      check1a = ax1 >= x0 and ax1 <= x1
      # X Distance Check B
      check0b = x0 >= ax0 and x0 <= ax1
      check1b = x1 >= ax0 and x1 <= ax1
      # Merge Distance Checks
      check0 = check0a or check0b
      check1 = check1a or check1b
    # Check if is sticky to top side
    result = check0 or check1

proc checkLeft(a, b: GUIMetrics, thr: int32): bool =
  if abs(a.x - b.x - b.w) < thr:
    let
      ay0 = a.y
      ay1 = a.y + a.h
      # Sticky Area
      y0 = b.y
      y1 = y0 + b.h
      # X Distance Check
      check0a = ay0 >= y0 and ay0 <= y1
      check1a = ay1 >= y0 and ay1 <= y1
      # X Distance Check B
      check0b = y0 >= ay0 and y0 <= ay1
      check1b = y1 >= ay0 and y1 <= ay1
      # Merge Distance Checks
      check0 = check0a or check0b
      check1 = check1a or check1b
    # Check if is sticky to top side
    result = check0 or check1

proc cornerX(a, b: GUIMetrics, thr: int32): int16 =
  let 
    d0 = a.x - b.x
    d1 = d0 + a.w - b.w
  # Check Nearly Deltas
  if abs(d0) < thr: b.x
  elif abs(d1) < thr:
    b.x + b.w - a.w
  else: a.x

proc cornerY(a, b: GUIMetrics, thr: int32): int16 =
  let 
    d0 = a.y - b.y
    d1 = d0 + a.h - b.h
  # Check Nearly Deltas
  if abs(d0) < thr: b.y
  elif abs(d1) < thr:
    b.y + b.h - a.h
  else: a.y

proc snap*(a, b: GUIWidget): DockSnap =
  let
    a0 = a.metrics
    b0 = b.metrics
    # TODO: allow custom margin
    h = getApp().font.height
    thr = h shr 1
    pad = h shr 3
  # Calculate Where is
  let side = 
    if checkTop(a0, b0, thr): dockTop
    elif checkLeft(a0, b0, thr): dockLeft
    # Check Opposite Dock Sides
    elif checkTop(b0, a0, thr): dockDown
    elif checkLeft(b0, a0, thr): dockRight
    # No Sticky Found
    else: dockNothing
  # Initial Position
  var
    x = a0.x
    y = a0.y
  # Calculate Sticky Position
  case side
  of dockTop: 
    y = b0.y + b0.h - pad
    x = cornerX(a0, b0, thr)
  of dockDown: 
    y = b0.y - a0.h + pad
    x = cornerX(a0, b0, thr)
  of dockLeft: 
    x = b0.x + b0.w - pad
    y = cornerY(a0, b0, thr)
  of dockRight: 
    x = b0.x - a0.w + pad
    y = cornerY(a0, b0, thr)
  # No Snapping Found
  else: discard
  # Return Sticky Info
  DockSnap(side: side, x: x, y: y)

proc apply*(self: GUIWidget, s: DockSnap) =
  let m = addr self.metrics
  # Move Accourding Position
  m.x = int16 s.x
  m.y = int16 s.y
  # Action Update
  self.set(wDirty)
