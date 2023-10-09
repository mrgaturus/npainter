import nogui/builder
import nogui/ux/prelude
import header, snap, ../dock

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
    dock* {.cursor.}: UXDock
    metrics: GUIMetrics
    # Backup Dock Callbacks
    cbMove*: GUICallbackEX[DockMove]
    cbResize*: GUICallbackEX[DockMove]
  # Docking Row Opaque
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

  # -- Dock Node Attach at Next --
  proc attach*(node: UXDockNode) =
    attach0(self, node)
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

  # -- Dock Node Callbacks --
  callback cbMove(p: DockMove):
    self.detach()
    update(self, self.row)
    # Move After Dettach
    force(self.target.cbMove, p)

  callback cbResize(p: DockMove):
    force(self.target.cbResize, p)
    update(self, self.row)

  # -- Dock Node Constructor --
  new docknode(dock: UXDock):
    # Create Dock Attach
    result.target = DockAttach(
      dock: dock,
      cbMove: dock.cbMove,
      cbResize: dock.cbResize)
    # Hook Dock Callbacks
    dock.cbMove = result.cbMove
    dock.cbResize = result.cbResize

# ------------------
# Docking Group Node
# ------------------

controller UXDockRow:
  attributes:
    first: UXDockNode
    metrics: GUIMetrics
    # Delta Position Callback
    cbDelta: GUICallbackEX[DockOpaque]
    # Linked List
    next: UXDockRow
    {.cursor.}:
      prev: UXDockRow

  new dockrow():
    discard

  # -- Dock Arrange --
  proc bounds(w: int16) =
    var m0: GUIMetrics
    # Iterate Nodes
    self.walk0 node:
      let m = addr node.target.dock.metrics
      # Calculate Minimun
      m0.minW = max(m0.minW, m.minW)
      m0.minH = max(m0.minH, m.minH)
      # Calculate Size
      m0.h = max(m0.h, m.h)
    # Apply Minimum Width
    m0.w = max(w, m0.minW)
    # Replace Metrics
    self.metrics = m0

  proc arrange(x0, y0: int16) =
    let 
      m0 = addr self.metrics
      w0 = m0.w
    var y: int16 = y0
    # Iterate Dock Nodes
    self.walk0 node:
      let
        target = addr node.target
        dock {.cursor.} = target.dock
        m = addr dock.metrics
      # Calculate Size
      m.w = w0
      m.h = max(m.h, m.minH)
      # Calculate Position
      m.x = x0
      m.y = y
      y += m.h
      # TODO: make those as a children
      target.metrics = m[]
      target.dock.set(wDirty)
    # Apply Metrics Position
    m0.x = x0
    m0.y = y0

  # -- Dock Row Attachment --
  proc attach*(node: UXDockNode) =
    # Attach Prev to First Node
    let first {.cursor.} = self.first
    # Replace First Prev
    if not isNil(first):
      first.prev = node
      node.next = first
      node.prev = nil
    # Replace First Node
    self.first = node
    node.row = cast[DockOpaque](self)

  proc attach*(row: UXDockRow) =
    attach0(self, row)
    # Change Row Delta
    row.cbDelta = self.cbDelta

  proc detach*() =
    detach0(self)

# ------------------------
# Docking Group Row Update
# ------------------------

proc adjustY(row: UXDockRow, target: ptr DockAttach) =
  discard

proc adjustX(row: UXDockRow, target: ptr DockAttach) =
  let
    m = addr row.metrics
    # Target Metrics
    m0 = addr target.metrics
    m1 = addr target.dock.metrics
    # Calculated Width
    w0 = max(m.w, m1.w)
    dw = w0 - m1.w
    dx = m1.x - m0.x - dw
  # Apply Min Size
  m1.x -= dw
  m1.w = w0
  # Delta X
  m.x = dx

proc update(self: UXDockNode, opaque: DockOpaque) =
  let 
    target = addr self.target
    row {.cursor.} = cast[UXDockRow](opaque)
  # Calculate Row Bounds
  row.bounds(target.dock.metrics.w)
  # Adjust X and Y Positions
  row.adjustX(target)
  row.adjustY(target)
  # Arrange Row and Notify
  push(row.cbDelta, opaque)

# --------------------
# Docking Group Widget
# --------------------

widget UXDockGroup:
  attributes:
    {.cursor.}:
      head: UXDockHeader
    # Linked List
    first0: UXDockRow

  # -- Dock Group Callbacks --
  callback cbMove(p: DockMove):
    # Re-arrange Groups
    self.move(p.x, p.y)

  callback cbDelta(o: DockOpaque):
    let 
      row = cast[UXDockRow](o).metrics
      m = addr self.metrics
    # Apply Row Delta Position
    m.x += row.x
    m.y += row.y
    # Re-arrange Groups
    self.set(wDirty)

  new dockgroup(first: UXDockRow):
    result.kind = wgFrame
    result.flags = wMouse
    # Create Dock Head
    let head = dockhead("", CTXIconEmpty)
    head.onmove = result.cbMove
    # Add Header and Widget
    result.add head
    result.head = head
    # Set First Row
    result.first0 = first
    first.cbDelta = result.cbDelta

  method update =
    let
      m = addr self.metrics
      m0 = addr self.head.metrics
      # TODO: allow customize margin
      margin = getApp().font.height shr 3
    # Adjust Respect Header + Margin
    m.minW = m0.minW + (margin shl 1)
    m.minH = m0.minH
    # Dock Row Pivot
    let y = m.y + m.minH
    var x = m.x + margin
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
    m.w = x - m.x + margin
    m.h = m.minH

  method layout =
    let
      # TODO: allow customize margin
      margin = getApp().font.height shr 3
      # Dock Group
      m = addr self.metrics
      m0 = addr self.head.metrics
    # Locate Header
    m0.x = margin
    m0.y = 0
    # Scale Header
    m0.w = m.w - (margin shl 1)
    m0.h = m0.minH
    echo m[]
