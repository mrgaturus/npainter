import nogui/builder
import nogui/ux/prelude
import header, snap, ../dock
# TODO: unify event and callback queue
from nogui/gui/widget import arrange

# ------------------
# Linked List Helper
# ------------------

template attach0(self, node: typed) =
  let next {.cursor.} = self.next
  # Prev to Self Next
  node.next = next
  if not isNil(next):
    next.prev = node
  # Next to Self
  self.next = node
  node.prev = self

template attach0prev(self, node: typed) =
  let prev {.cursor.} = self.prev
  # Prev to Self Next
  node.prev = prev
  if not isNil(prev):
    prev.next = node
  # Next to Self
  self.prev = node
  node.next = self

template detach0(self: typed) =
  let
    next {.cursor.} = self.next
    prev {.cursor.} = self.prev
  # Remove Node From List
  if not isNil(next): next.prev = prev
  if not isNil(prev): prev.next = next

# -- Dock Row Node Walking --
template walk0(self: typed, name, body: untyped) =
  var name {.cursor.} = self.first
  # Iterate Each Node
  while not isNil(name):
    body; name = name.next

# ------------------
# Docking Group Node
# ------------------

type
  DockAttach* = object
    dock {.cursor.}: UXDock
    metrics: GUIMetrics
    # Backup Dock Callbacks
    cbMove: GUICallbackEX[DockMove]
    cbResize: GUICallbackEX[DockMove]
    # Backup Dock Header Callbacks
    cbFold, cbClose: GUICallback
  # Dock Row Opaque
  DockOpaque = distinct pointer

controller UXDockNode:
  attributes:
    target: DockAttach
    row: DockOpaque
    # Linked List
    next: UXDockNode
    {.cursor.}:
      prev: UXDockNode

  # -- Forward Declaration --
  proc update(opaque: DockOpaque)
  proc detach(opaque: DockOpaque)

  # -- Dock Node Attach at Next --
  proc attach*(node: UXDockNode) =
    attach0(self, node)
    # Set Node Row
    node.row = self.row
    update(self, self.row)

  proc prettach*(node: UXDockNode) =
    attach0prev(self, node)
    # Set Node Row
    node.row = self.row
    update(self, self.row)

  proc detach*() =
    detach0(self)
    # Attached Dock
    let
      target = addr self.target
      dock {.cursor.} = target.dock
    # Restore Dock Callbacks
    dock.cbMove = target.cbMove
    dock.cbResize = target.cbResize
    dock.cbFold = target.cbFold
    dock.cbClose = target.cbClose
    # Remove Node and Row Bind
    dock.node = nil
    dock.row = nil
    # Update Buttons
    dock.headerUpdate()
    detach(self, self.row)

  # -- Dock Node Callbacks --
  callback cbMove(p: DockMove):
    self.detach()
    # Force Callback Moving
    force(self.target.cbMove, p)

  callback cbResize(p: DockMove):
    let 
      t0 = addr self.target
      pv0 = addr t0.dock.pivot
      # Cursor Pointers
      row = self.row
      prev = self.prev
    var sides = pv0.sides
    # Syncronize Pivot With Previous
    if (dockTop in sides) and not isNil(prev):
      let
        t1 = addr prev.target
        pv1 = addr t1.dock.pivot
      # Move Prev From Down
      if dockOpposite notin sides:
        sides = sides - {dockTop} + {dockDown}
        # Replace Pivot
        pv1.x = pv0.x
        pv1.y = pv0.y
        pv1.sides = sides
        pv1.rect = t1.dock.rect
        # Avoid Redefine Pivot
        pv0.sides.incl dockOpposite
      # Execute Prev Callback
      if t1.dock.unfolded:
        force(t1.cbResize, p)
        update(prev, row)
    else: # Forward Update
      force(t0.cbResize, p)
      update(self, row)

  callback cbFold:
    force(self.target.cbFold)
    update(self, self.row)

  callback cbClose:
    self.detach()
    force(self.target.cbClose)

  # -- Dock Node Constructor --
  new docknode(dock: UXDock):
    # Create Dock Attach
    result.target = DockAttach(
      dock: dock,
      metrics: dock.metrics,
      # Backup Callbacks
      cbMove: dock.cbMove,
      cbResize: dock.cbResize,
      cbFold: dock.cbFold,
      cbClose: dock.cbClose)
    # Hook Dock Callbacks
    dock.cbMove = result.cbMove
    dock.cbResize = result.cbResize
    dock.cbFold = result.cbFold
    dock.cbClose = result.cbClose
    # Update Buttons
    dock.headerUpdate()

# ------------------
# Docking Group Node
# ------------------

controller UXDockRow:
  attributes:
    first: UXDockNode
    metrics: GUIMetrics
    # Delta Position Callback
    cbNotify: GUICallbackEX[DockOpaque]
    cbDetach: GUICallbackEX[DockOpaque]
    # Linked List
    next: UXDockRow
    {.cursor.}:
      prev: UXDockRow

  new dockrow():
    discard

  # -- Dock Arrange --
  proc bounds =
    var 
      m0: GUIMetrics
      h, minH: int16
    # Iterate Nodes
    self.walk0 node:
      let m = addr node.target.dock.metrics
      # Calculate Width
      m0.w = max(m0.w, m.w)
      m0.minW = max(m0.minW, m.minW)
      # Calculate Height
      h += m.h
      minH += m.minH
    # Apply Minimum Width
    m0.w = max(m0.w, m0.minW)
    m0.h = max(h, minH)
    # Replace Metrics
    self.metrics = m0

  proc arrange(x0, y0: int16) =
    let 
      m0 = addr self.metrics
      w0 = m0.w
      # TODO: allow custom margin
      pad = getApp().font.height shr 3
    var y: int16 = y0
    # Iterate Dock Nodes
    self.walk0 node:
      let
        target = addr node.target
        dock {.cursor.} = target.dock
        m = addr dock.metrics
      # Calculate Metrics
      m.w = w0
      m.x = x0
      m.y = y
      y += m.h - pad
      # Update Dock Group Locations
      dock.node = cast[pointer](node)
      dock.row = cast[pointer](self)
      # Mark As Dirty
      target.metrics = m[]
      dock.set(wDirty)
    # Apply Metrics Position
    m0.x = x0
    m0.y = y0

  # -- Dock Row Attachment --
  proc attach*(node: UXDockNode) =
    # Attach Prev to First Node
    let 
      first {.cursor.} = self.first
      opaque = cast[DockOpaque](self)
    # Replace First Prev
    if not isNil(first):
      first.prev = node
      node.next = first
      node.prev = nil
    # Replace First Node
    self.first = node
    node.row = opaque
    # Notify Node Update
    update(node, opaque)

  proc attach*(row: UXDockRow) =
    attach0(self, row)
    # Change Row Delta Callback
    row.cbNotify = self.cbNotify
    row.cbDetach = self.cbDetach

  proc prettach*(row: UXDockRow) =
    attach0prev(self, row)
    # Change Row Delta Callback
    row.cbNotify = self.cbNotify
    row.cbDetach = self.cbDetach

  proc detach*() =
    detach0(self)

# ------------------------
# Docking Group Row Update
# ------------------------

proc adjust(row: UXDockRow, node: UXDockNode) =
  let
    target = addr node.target
    m = addr row.metrics
    # Target Metrics
    m0 = addr target.metrics
    m1 = addr target.dock.metrics
    # Calculated Width
    w0 = max(m1.w, m.minW)
    dw = w0 - m1.w
    dx = m1.x - m0.x - dw
  # Move Top Corners
  if node == row.first:
    m.y = m1.y - m0.y
  # Apply Min Size
  m1.x -= dw
  m1.w = w0
  # Delta X
  m.x = dx
  m.w = w0

proc update(self: UXDockNode, opaque: DockOpaque) =
  let row {.cursor.} = cast[UXDockRow](opaque)
  # Change First Node
  let prev = row.first.prev
  if not isNil(prev):
    row.first = prev
  # Calculate Row Bounds and Adjust
  row.bounds()
  row.adjust(self)
  # Arrange Row and Notify
  force(row.cbNotify, addr opaque)

proc detach(self: UXDockNode, opaque: DockOpaque) =
  let row {.cursor.} = cast[UXDockRow](opaque)
  # Check Detatch
  var first = row.first
  if self == first:
    first = self.next
    row.first = first
    # Detach if there is nothing
    if isNil(first):
      row.detach()
  # Calculate Row Bounds
  row.bounds()
  # Notify Row Changes
  force(row.cbDetach, addr opaque)

# --------------------
# Docking Group Widget
# --------------------

widget UXDockGroup:
  attributes:
    {.cursor.}:
      head: UXDockHeader
    # Linked List
    first0: UXDockRow
    # Dock Session Manager
    {.public.}:
      cbWatch: GUICallbackEX[DockWatch]

  proc watch(reason: DockReason, p: DockMove) =
    # TODO: make force optional as push
    if valid(self.cbWatch):
      let w = DockWatch(
        reason: reason, p: p, 
        opaque: cast[pointer](self))
      force(self.cbWatch, addr w)

  proc close0awful() =
    self.close()
    # Session Watch Action
    let 
      m = addr self.metrics
      p = DockMove(x: m.x, y: m.y)
    self.watch(groupWatchClose, p)

  # -- Dock Group Callbacks --
  callback cbMove(p: sink DockMove):
    # Re-arrange Groups
    let head {.cursor.} = self.head
    head.move0awful(p)
    # Session Watch Movement
    let reason =
      if head.grab: groupWatchMove
      else: groupWatchRelease
    self.watch(reason, p)

  callback cbNotify(o: DockOpaque):
    let 
      row = cast[UXDockRow](o[])
      m0 = addr row.metrics
      m = addr self.metrics
    # Row Delta Position
    m.x += m0.x
    m.y += m0.y
    # Change First Row
    let prev = self.first0.prev
    if not isNil(prev):
      self.first0 = prev
    # TODO: unify event and callback queue
    self.arrange()

  callback cbDetach(o: DockOpaque):
    let row = cast[UXDockRow](o[])
    var first0 = self.first0
    # Dettach if there is not nodes
    if isNil(row.first) and row == first0:
      first0 = row.next
      # Close Group When no Dock
      if isNil(first0):
        self.close0awful()
        return
      # Replace First
      self.first0 = first0
    # TODO: unify event and callback queue
    force(self.cbNotify, o)
    # Check is There is One Node
    let first1 {.cursor.} = first0.first
    if isNil(first1.next) and isNil(first0.next):
      first1.detach()

  new dockgroup(first: UXDockRow):
    result.kind = wgFrame
    result.flags = wMouse
    # Create Dock Head
    let head = dockhead0awful()
    head.onmove = result.cbMove
    # Add Header and Widget
    result.add head
    result.head = head
    # Set First Row
    result.first0 = first
    # Connect Callbacks
    first.cbNotify = result.cbNotify
    first.cbDetach = result.cbDetach

  method update =
    let
      m = addr self.metrics
      m0 = addr self.head.metrics
    # Adjust Respect Header + Margin
    m.minW = m0.minW
    m.minH = m0.minH
    # Dock Row Pivot
    let y = m.y + m.minH
    var x = m.x
    # Avoid Become a Child
    assert self.kind == wgFrame
    # Arrange Rows
    var row {.cursor.} = self.first0
    while not isNil(row):
      row.arrange(x, y)
      # Next Dock Row
      x += row.metrics.w
      row = row.next
    # Set Container Size
    m.w = x - m.x
    m.h = m.minH

  method layout =
    let
      # TODO: allow customize margin
      pad = getApp().font.height shr 3
      # Dock Group
      m = addr self.metrics
      m0 = addr self.head.metrics
    # Locate Header
    m0.x = pad
    m0.y = 0
    # Scale Header
    m0.w = m.w - (pad shl 1)
    m0.h = m0.minH

  method draw(ctx: ptr CTXRender) =
    let colors = addr getApp().colors
    # Draw Group Header
    ctx.color colors.item and 0x3FFFFFFF'u32
    ctx.fill rect(self.head.rect)
