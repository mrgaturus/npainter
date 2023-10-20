import nogui/ux/prelude
import nogui/builder
# Import Dock and Group
import group, snap
import ../dock

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

proc snapDock0awful(dock: UXDock) =
  for w in docks0awful(dock):
    let s = snap(dock, w)
    # Apply Nearbies Snaps
    if s.side != dockNothing:
      dock.apply(s)

# -----------------------
# Dock Session Supervisor
# -----------------------

controller UXDockSession:
  attributes:
    hint: UXDockHint
    # Clipping Session
    {.public, cursor.}:
      weird: GUIWidget

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

  # -- Dock Session Callbacks --
  callback cbWatchDock(watch: DockWatch):
    let 
      target = cast[UXDock](watch.opaque)
      reason = watch.reason
    # Snap Dock When is Moving or Releasing
    if reason in {dockWatchMove, dockWatchRelease}:
      target.snapDock0awful()
    # Process Watch Reason
    case watch.reason
    of dockWatchRelease:
      self.groupDock(target, watch.p)
    of dockWatchMove:
      self.hintDock(target, watch.p)
    else: discard

  callback cbWatchGroup(watch: DockWatch):
    # TODO: see what to do with this
    let target = cast[UXDockGroup](watch.opaque)
    # Process Watch Reason
    if watch.reason == groupWatchMove:
      target.orient0awful(self.weird.rect)

  # -- Dock Session Updater --
  callback cbUpdate:
    var weird {.cursor.} = self.weird
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
        g.orient0awful(clip)
      # Next Weird
      weird = weird.prev

  # -- Dock Session Constructor --
  new docksession():
    result.hint = dockhint()
