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
  
  proc hint(x, y, w, h: int16) =
    self.open()
    # Locate Hightlight
    let m = addr self.metrics
    m.x = x; m.y = y
    m.w = w; m.h = h
    # Mark as Dirty
    self.set(wDirty)

  method draw(ctx: ptr CTXRender) =
    discard

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

  # -- Dock Session Finders --
  proc findSnap(w: GUIWidget): GUIWidget =
    discard

  proc findDock(p: DockMove): UXDock =
    discard

  # -- Dock Session Callbacks --
  callback cbWatchDock(watch: DockWatch):
    let target = cast[UXDock](watch.opaque)
    echo watch.reason, ": ", watch.p

  callback cbWatchGroup(watch: DockWatch):
    let target = cast[UXDockGroup](watch.opaque)
    echo watch.reason, ": ", watch.p

  # -- Dock Session Manipulation --
  proc add*(dock: UXDock) =
    dock.cbWatch = self.cbWatchDock
    self.docks.add(dock)

  proc add*(group: UXDockGroup) =
    group.cbWatch = self.cbWatchGroup
    self.groups.add(group)

  proc update*(metrics: GUIMetrics) =
    discard

  # -- Dock Session Constructor --
  new docksession():
    result.hint = dockhint()
