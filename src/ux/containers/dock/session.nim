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
  # Create Group And Attach Node
  result = dockgroup(row)
  row.attach(node)
  # Move To Widget
  let m = addr dock.rect
  result.move(m.x, m.y)

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

# -----------------------
# Dock Session Supervisor
# -----------------------

controller UXDockSession:
  attributes:
    hint: UXDockHint
    metrics: GUIMetrics
    # Opened Docks
    docks: seq[UXDock]
    groups: seq[UXDockGroup]

  # -- Dock Session Manipulation --
  proc add*(dock: UXDock) =
    dock.cbWatch = self.cbWatchDock
    self.docks.add(dock)

  proc add*(group: UXDockGroup) =
    group.cbWatch = self.cbWatchGroup
    self.groups.add(group)

  # -- Dock Session Grouping --
  proc groupDock(hold: UXDock, p: DockMove) =
    # Close Hint
    self.hint.close()
    # Find Dock and Group it
    let 
      w {.cursor.} = findDock(hold, p)
      # TODO: allow customize margins
      thr = getApp().font.height shl 1
      side = groupSide(w.rect, p, 32)
    if w == hold or side == dockNothing: return
    # Create A New Group
    if isNil(w.row):
      let group = groupStart(w)
      group.open()
      self.groups.add(group)
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
    let target = cast[UXDock](watch.opaque)
    case watch.reason
    of dockWatchRelease:
      self.groupDock(target, watch.p)
    of dockWatchMove: 
      self.hintDock(target, watch.p)
    else: discard

  callback cbWatchGroup(watch: DockWatch):
    let target = cast[UXDockGroup](watch.opaque)
    echo watch.reason, ": ", watch.p

  # -- Dock Session Constructor --
  new docksession():
    result.hint = dockhint()
    result.docks = newSeq[UXDock]()
    result.groups = newSeq[UXDockGroup]()

  proc update*(metrics: GUIMetrics) =
    discard