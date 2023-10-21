import nogui/ux/prelude
import nogui/builder
# Import Dock and Group
import dock, group, snap

# -----------------
# Dock Session Hint
# -----------------

widget UXDockHint:
  new dockhint():
    # Show As Tooltip
    result.kind = wgTooltip
  
  proc highlight(r: GUIRect) =
    self.open()
    # Locate Hightlight
    let m = addr self.metrics
    m.x = int16 r.x
    m.y = int16 r.y
    m.w = int16 r.w
    m.h = int16 r.h
    # Mark as Dirty
    self.set(wDirty)

  method draw(ctx: ptr CTXRender) =
    const mask = 0x7FFFFFFF
    let colors = addr getApp().colors
    ctx.color colors.text and mask
    ctx.fill rect(self.rect)
    ctx.color colors.item and mask
    ctx.line rect(self.rect), 2

# ------------------------
# Dock Session Dock Finder
# ------------------------

# FUTURE DIRECTION: 
# make docks/groups childrens of session widget
iterator docks0awful(pivot: UXDock): UXDock =
  let vtable = pivot.vtable
  var w {.cursor.} = cast[GUIWidget](pivot)
  # Walk to Last Frame
  while not isNil(w.next):
    w = w.next
  # Iterate Backwards only Docks
  while not isNil(w):
    if w.vtable == vtable and w != pivot:
      yield cast[UXDock](w)
    w = w.prev

proc findDock(pivot: UXDock, p: DockMove): UXDock =
  result = pivot
  for w in docks0awful(pivot):
    # Find if is Point Inside
    if w.pointOnArea(p.x, p.y):
      result = w
      break

# ---------------------
# Dock Session Grouping
# ---------------------

proc groupStart(dock: UXDock): UXDockGroup =
  let 
    row = dockrow()
    node = docknode(dock)
    m = addr dock.metrics
  # Create Group And Attach Node
  result = dockgroup(row)
  result.metrics.x = m.x
  result.metrics.y = m.y
  # Attach Node
  row.attach(node)

proc groupDock(dock, to: UXDock, side: DockSide) =
  # Lookup Row And Warp to Node
  let
    row = cast[UXDockRow](to.row)
    node = cast[UXDockNode](to.node)
    n0 = docknode(dock)
  # Decide Where Dock
  case side
  of dockTop: node.prettach(n0)
  of dockDown: node.attach(n0)
  of dockLeft:
    let r0 = dockrow()
    row.prettach(r0)
    r0.attach(n0)
  of dockRight:
    let r0 = dockrow()
    row.attach(r0)
    r0.attach(n0)
  else: discard

# ---------------------
# Dock Session Snapping
# ---------------------

proc clipDock0awful(widget, clip: GUIWidget) =
  let head {.cursor.} = widget.first
  head.metrics.x = widget.metrics.x
  head.metrics.y = widget.metrics.y
  let p = head.clip(clip)
  widget.move(p.x, p.y)

proc snapDock0awful(dock: UXDock, clip: GUIWidget) =
  # Snap With Nearby Docks
  for w in docks0awful(dock):
    let s = snap(dock, w)
    # Apply Nearbies Snaps
    if s.side != dockNothing:
      dock.apply(s)
  # Clip Dock When Moving
  dock.clipDock0awful(clip)

# -----------------------
# Dock Session Supervisor
# -----------------------

controller UXDockSession:
  attributes:
    hint: UXDockHint
    # Clipping Session
    {.public, cursor.}:
      weird: GUIWidget
      # Group Sidebars Sticky
      [left, right]: UXDockGroup

  # -- Dock Session Manipulation --
  proc watch*(dock: UXDock) =
    dock.cbWatch = self.cbWatchDock

  proc watch*(group: UXDockGroup) =
    group.cbWatch = self.cbWatchGroup

  # -- Dock Session Grouping --
  proc groupDock(hold: UXDock, p: DockMove) =
    # Close Hint
    self.hint.close()
    # Find Dock and Group it
    let 
      w {.cursor.} = findDock(hold, p)
      # TODO: allow customize margins
      thr = getApp().font.height shl 1
      side = groupSide(w.rect, p, thr)
    if w == hold or side == dockNothing: return
    # Create A New Group
    if isNil(w.row):
      let g = groupStart(w)
      # Watch Group and Adjust Orient
      g.cbWatch = self.cbWatchGroup
      g.orient0awful(self.weird.rect)
      # TODO: future direction
      g.open()
    # Attach New Group
    groupDock(hold, w, side)

  proc hintDock(hold: UXDock, p: DockMove) =
    var
      side = dockNothing
      rect: GUIRect
    # TODO: allow customize margins
    let thr = getApp().font.height shl 1
    # Find Dock Inside
    let w {.cursor.} = findDock(hold, p)
    if w != hold:
      rect = w.rect
      side = groupSide(rect, p, thr)
      # Break if There are Sides
      if side != dockNothing:
        rect = groupHint(rect, side, thr)
    # Show Hint Widget or Close it
    let hint {.cursor.} = self.hint
    if side != dockNothing:
      hint.highlight(rect)
    else: hint.close()

  callback cbWatchDock(watch: DockWatch):
    let 
      target = cast[UXDock](watch.opaque)
      reason = watch.reason
    # Snap Dock When is Moving or Releasing
    if reason in {dockWatchMove, dockWatchRelease}:
      target.snapDock0awful(self.weird)
    # Process Watch Reason
    case reason
    of dockWatchRelease:
      self.groupDock(target, watch.p)
    of dockWatchMove:
      self.hintDock(target, watch.p)
    else: discard

  # -- Group Session Callbacks --
  proc hintSide(p: DockMove) =
    var 
      rect = self.weird.rect
      check = false
    # TODO: allow customize margins
    let
      thr = getApp().font.height shl 1
      side = groupSide(rect, p, thr)
      hint {.cursor.} = self.hint
    # Show Hint Widget or Close it
    if side == dockLeft: check = isNil(self.left)
    elif side == dockRight: check = isNil(self.right)
    # Show Hint Side
    if check:
      rect = groupHint(rect, side, thr)
      hint.highlight(rect)
    else: hint.close()

  proc snapSide(group: UXDockGroup, p: DockMove) =
    # TODO: allow customize margins
    let 
      thr = getApp().font.height shl 1
      side = groupSide(self.weird.rect, p, thr)
    # Select Which Side Use
    if side == dockLeft and isNil(self.left):
      self.left = group
    elif side == dockRight and isNil(self.right):
      self.right = group
    # Perform An Update
    if side in {dockLeft, dockRight}:
      push(self.cbUpdate)
    # Close Hint
    self.hint.close()

  proc clearSide(group: UXDockGroup) =
    if group == self.left:
      self.left = nil
    elif group == self.right:
      self.right = nil

  callback cbWatchGroup(watch: DockWatch):
    # TODO: see what to do with this
    let 
      target = cast[UXDockGroup](watch.opaque)
      reason = watch.reason
      weird {.cursor.} = self.weird
    # Calculate Orientation
    target.orient0awful(weird.rect)
    # Snap With Clipping
    let p = target.clip(weird)
    target.move(p.x, p.y)
    # Hint Sides
    case reason
    of groupWatchMove:
      self.clearSide(target)
      self.hintSide(watch.p)
    of groupWatchRelease:
      self.snapSide(target, watch.p)
    of groupWatchClose:
      self.clearSide(target)
    else: discard

  # -- Dock Session Updater --
  proc updateOrients() =
    var 
      weird {.cursor.} = self.weird
      check = false
    let clip = weird.rect
    # FUTURE DIRECTION:
    # make docks/groups be childrens
    while not isNil(weird.parent):
      weird = weird.parent
    while not isNil(weird.next):
      weird = weird.next
    # Iterate Groups
    while not isNil(weird):
      if weird of UXDockGroup:
        # Update Group Orientation
        let g = cast[UXDockGroup](weird)
        check = # Check Not Side
          weird != self.left and 
          weird != self.right
        g.orient0awful(clip)
      elif weird of UXDock:
        let d = cast[UXDock](weird)
        check = isNil(d.row)
      else: check = false
      # Clip Position respect region
      if check:
        weird.clipDock0awful(self.weird)
      # Next Weird
      weird = weird.prev

  proc updateSidebars() =
    let 
      clip = addr self.weird.rect
      left {.cursor.} = self.left
      right {.cursor.} = self.right
    # Arrange Left Sidebar
    if not isNil(left):
      let m = addr left.metrics
      m.x = int16 clip.x
      m.y = int16 clip.y
      # Update Metrics
      left.set(wDirty)
    # Arrange Right Sidebar
    if not isNil(right):
      let m = addr right.metrics
      m.x = int16 clip.x + clip.w - m.w
      m.y = int16 clip.y
      # Update Metrics
      right.set(wDirty)

  callback cbUpdate:
    # Update Groups respect Clipping
    self.updateSidebars()
    self.updateOrients()

  # -- Dock Session Constructor --
  new docksession():
    result.hint = dockhint()
