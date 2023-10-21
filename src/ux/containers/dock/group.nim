import nogui/builder
import nogui/ux/prelude
import header, snap, dock
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
  DockTarget* = object
    dock {.cursor.}: UXDock
    pivot, metrics: GUIMetrics
    # Backup Dock Callbacks
    cbMove: GUICallbackEX[DockMove]
    cbResize: GUICallbackEX[DockMove]
    # Backup Dock Header Callbacks
    cbFold, cbClose: GUICallback
  # Dock Row Opaque
  DockOpaque = distinct pointer

controller UXDockNode:
  attributes:
    target: DockTarget
    row: DockOpaque
    # Linked List
    next: UXDockNode
    {.cursor.}:
      prev: UXDockNode

  # -- Forward Declaration --
  proc update(opaque: DockOpaque)
  proc attach(opaque: DockOpaque)
  proc detach(opaque: DockOpaque)

  # -- Dock Node Attach at Next --
  proc attach*(node: UXDockNode) =
    attach0(self, node)
    # Set Node Row
    node.row = self.row
    attach(self, self.row)

  proc prettach*(node: UXDockNode) =
    attach0prev(self, node)
    # Set Node Row
    node.row = self.row
    attach(self, self.row)

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
    # Calculate Resize Delta
    let d0 = self.target.dock
    d0.rect = delta(d0.pivot, p.x, p.y)
    # Execute Row Update
    update(self, self.row)

  callback cbFold:
    force(self.target.cbFold)
    update(nil, self.row)

  callback cbClose:
    self.detach()
    force(self.target.cbClose)

  # -- Dock Node Constructor --
  new docknode(dock: UXDock):
    # Create Dock Attach
    result.target = DockTarget(
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
    orient: ptr DockSide
    # Group Notify Callbacks
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
      # Next Node
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
    attach(node, opaque)

  proc attach*(row: UXDockRow) =
    attach0(self, row)
    # Change Row Delta Callback
    row.cbNotify = self.cbNotify
    row.cbDetach = self.cbDetach
    row.orient = self.orient

  proc prettach*(row: UXDockRow) =
    attach0prev(self, row)
    # Change Row Delta Callback
    row.cbNotify = self.cbNotify
    row.cbDetach = self.cbDetach
    row.orient = self.orient

  proc detach*() =
    detach0(self)

# ----------------------------
# Docking Group Metrics Adjust
# ----------------------------

proc adjust0(row: UXDockRow, node: UXDockNode) =
  let
    target = addr node.target
    m = addr row.metrics
    # Dock Width Metric
    w = target.dock.metrics.w
    orient = row.orient[]
  # Apply Dock Metrics
  m.w = max(w, m.minW)
  # Apply Offset With Orient
  if orient == dockLeft:
    # TODO: allow custom margin
    let 
      pad = getApp().font.height shr 3
      first {.cursor.} = row.first
    # Offset Detached or Attached
    if isNil(first): 
      m.x = w - pad
    elif node == first and isNil(node.next):
      m.x = pad - w

proc adjustY(row: UXDockRow, node: UXDockNode) =
  let 
    t0 = addr node.target
    d0 {.cursor.} = t0.dock
    pv0 = addr d0.pivot
    # Metrics Pointers
    r0 = addr d0.rect
    m0 = addr d0.metrics
    m = addr row.metrics
    # Previous Node  
    prev = node.prev
  # Check Clicked Sides
  var sides = pv0.sides
  let check = dockTop in sides
  # Check Top Side for Prev
  if check and not isNil(prev):
    let
      t1 = addr prev.target
      d1 {.cursor.} = t1.dock
      m1 = addr d1.metrics
    # Define Previous Pivot
    if dockOppositeY notin sides:
      t0.pivot = t1.metrics
      sides.incl dockOppositeY
      # Replace Node Sides
      pv0.sides = sides
    # Apply Y Delta to Height
    if d1.unfolded:
      let h = t0.pivot.h + r0.y
      m1.h = max(m1.minH, int16 h)
  # Apply Height to Node
  elif d0.unfolded:
    let
      pr0 = addr pv0.rect
      h = pr0.h + r0.h
    m0.h = max(m0.minH, int16 h)
    # Move When is First
    if isNil(prev) and check:
      let y = (pr0.y + r0.y) - m0.h + h
      m.y = cast[int16](y - m0.y)

proc adjustX(row: UXDockRow, node: UXDockNode) =
  let
    t0 = addr node.target
    d0 {.cursor.} = t0.dock
    # Pivot Metrics
    pv0 = addr d0.pivot
    pr0 = addr pv0.rect
    pv1 = addr t0.pivot
    # Metrics Pointers
    r0 = addr d0.rect
    mm = addr row.metrics
    # Linked List
    prev {.cursor.} = row.prev
    next {.cursor.} = row.next
    # Group Orientation
    orient = row.orient[]
  # Clicked Sides
  var
    m = mm
    sides = pv0.sides
    # Horizontal Calculation
    x0 = t0.metrics.x
    x = pr0.x + r0.x
    w = pr0.w + r0.w
  # Orient and Side Checker
  let check = sides - {dockOppositeX}
  # Redundancy Template
  template adjustXChoose(c: UXDockRow) =
    m = addr c.metrics
    # Define Previous Pivot
    if dockOppositeX notin sides:
      pv1[] = m[]
      sides.incl dockOppositeX
    # TODO: unify event and callback queue
    c.bounds()
  # Adjust Clicked Opposite
  if check + {orient} == {dockRight, dockLeft}:
    if (dockLeft in check) and not isNil(prev):
      adjustXChoose(prev)
      # Calculate Opposite
      x = x0; w = pv1.w - r0.w
    elif (dockRight in check) and not isNil(next):
      adjustXChoose(next)
      # Calculate Opposite
      x = pr0.x + r0.w
      w = pv1.w - r0.w
  # Replace Node Sides
  pv0.sides = sides
  # Calculate Horizontal
  let 
    w0 = max(w, m.minW)
    dw = w0 - w
    dx = x - x0 - dw
  # Apply Horizontal
  m.w = int16 w0
  if x != x0:
    mm.x = int16 dx

# --------------------
# Docking Group Notify
# --------------------

proc update(self: UXDockNode, opaque: DockOpaque) =
  let row {.cursor.} = cast[UXDockRow](opaque)
  # Recalculate Bounds
  row.bounds()
  # Process Node Changes
  if not isNil(self):
    row.adjustY(self)
    row.adjustX(self)
  # Notify Row Changes
  force(row.cbNotify, addr opaque)

proc attach(self: UXDockNode, opaque: DockOpaque) =
  let row {.cursor.} = cast[UXDockRow](opaque)
  # Change First Node
  let prev = row.first.prev
  if not isNil(prev):
    row.first = prev
  # Calculate Row Bounds
  row.bounds()
  row.adjust0(self)
  # Notify Row Changes
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
  row.adjust0(self)
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
    orient: DockSide
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

  proc orient0awful*(clip: GUIRect) =
    self.orient = groupOrient(self.metrics, clip)

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
    # Connect Callbacks and Orient
    first.cbNotify = result.cbNotify
    first.cbDetach = result.cbDetach
    first.orient = addr result.orient
    # Mark as Invalidated
    result.metrics.w = low int16
    result.metrics.h = low int16

  method update =
    let
      m = addr self.metrics
      m0 = addr self.head.metrics
      # TODO: allow custom margin
      pad = getApp().font.height shr 3
    # Adjust Initial Offset
    if (m.w and m.h) < 0:
      m.y -= m0.minH
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
      x += row.metrics.w - pad
      # Next Dock Row
      row = row.next
    # Set Container Size
    m.w = x - m.x + pad
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
