from nogui/ux/widgets/menu import UXMenu
import nogui/ux/prelude
import header, snap
# TODO: get rid of this quick dirty cursor when c native plaform is done
from nogui import setCursor, clearCursor
# TODO: fold with wHidden and modify w in layout

widget UXDock:
  attributes:
    {.cursor.}:
      head: UXDockHeader
      widget: GUIWidget
    # Cache Font
    cache: cstring
    # Dock Manipulation
    {.public.}:
      serial: int32
      [node, row]: pointer
      pivot: DockResize
      # Dock Session Watcher
      cbWatch: GUICallbackEX[DockWatch]

  proc watch(reason: DockReason, p: DockMove) =
    # TODO: make force optional as push
    # TODO: remove point when unify queue and events
    if valid(self.cbWatch):
      let w = DockWatch(
        reason: reason, p: p, 
        opaque: cast[pointer](self))
      force(self.cbWatch, addr w)

  proc unfolded*: bool {.inline.} =
    (self.widget.flags and wHidden) == 0

  # -- Dock Move Callbacks --
  callback cbMove(p: sink DockMove):
    self.pivot.sides = {dockNothing}
    # Move Dock Awfully
    let head {.cursor.} = self.head
    head.move0awful(p)
    # Session Watch Movement
    let reason =
      if head.grab: dockWatchMove
      else: dockWatchRelease
    # Watch About Move
    self.watch(reason, p)

  callback cbResize(p: sink DockMove):
    if self.unfolded:
      # Apply Resize and Watch Resize
      self.apply resize(self.pivot, p.x, p.y)
      self.watch(dockWatchResize, p)

  # -- Dock Button Callbacks --
  callback cbFold:
    let 
      w = self.widget
      m = addr self.metrics
      # TODO: allow custom margin
      pad = getApp().font.height shr 2
    var flags = w.flags
    # Toggle Widget Hidden
    let 
      check = self.unfolded
      size = w.metrics.h + pad
    if check: # Remove Dimensions
      flags.set(wHidden)
      m.h -= size
    else: # Restore Dimensions
      flags.clear(wHidden)
      m.h += size
    # Change Flags
    w.flags = flags
    # Notify Callback
    notifyFold(self.head, not check)
    self.set(wDirty)

  callback cbClose:
    self.close()
    # Session Watch Action
    let 
      m = addr self.metrics
      p = DockMove(x: m.x, y: m.y)
    self.watch(dockWatchClose, p)

  # -- Dock Constructor --
  new dock(title: string, icon: CTXIconID, w: GUIWidget):
    result.kind = wgFrame
    result.flags = wMouse or wKeyboard
    # Create Dock Head
    let head = dockhead(title, icon)
    head.onmove = result.cbMove
    head.bindButtons(result.cbClose, result.cbFold)
    # Add Header and Widget
    result.add head
    result.add w
    # Set Head And Widget
    result.head = head
    result.widget = w

  proc headerUpdate* =
    let head {.cursor.} = self.head
    head.onmove = self.cbMove
    head.bindButtons(self.cbClose, self.cbFold)

  proc bindMenu*(m: UXMenu) {.inline.} =
    bindMenu(self.head, m)

  # -- Widget Methods --
  method update =
    let
      m = addr self.metrics
      m0 = addr self.head.metrics
      m1 = addr self.widget.metrics
      # TODO: allow custom margin
      pad = getApp().font.height
    # Calculate Min Size
    m.minW = max(m0.minW, m1.minW) + pad
    m.minH = m0.minH + m1.minH + pad

  method layout =
    let
      m = addr self.metrics
      m0 = addr self.head.metrics
      m1 = addr self.widget.metrics
      # TODO: allow custom margin
      pad0 = getApp().font.height
      pad1 = pad0 shr 2
      pad2 = pad0 shr 3
      pad = pad1 + pad2
    # Margin Calculation Helper
    proc margin(m2: ptr GUIMetrics, o, ow, oh: int16) =
      m2.x += o
      m2.y += o
      m2.w -= ow + ow
      m2.h -= oh + oh
    # Header Metrics
    m0.x = 0
    m0.y = 0
    m0.w = m.w
    m0.h = m0.minH
    m0.margin(pad, pad, 0)
    # Body Metrics
    if self.unfolded:
      m1.x = 0
      m1.w = m.w
      m1.y = m0.h
      m1.h = m.h - m1.y
      # Apply Padding
      m1.margin(pad, pad, pad)
      m1.y += pad1
      m1.h -= pad1

  proc decideCursor(sides: DockSides): cstring =
    if sides == {}: nil
    elif sides < {dockLeft, dockRight}: "size_hor"
    # Check Verticals
    elif dockTop in sides:
      if dockLeft in sides: "size_fdiag"
      elif dockRight in sides: "size_bdiag"
      else: "size_ver"
    elif dockDown in sides:
      if dockLeft in sides: "size_bdiag"
      elif dockRight in sides: "size_fdiag"
      else: "size_ver"
    else: nil

  method event(state: ptr GUIState) =
    let
      x = state.mx
      y = state.my
      kind = state.kind
      app = getApp()
    if kind == evCursorClick:
      # TODO: allow custom margin
      let pad = getApp().font.height and not 3
      self.pivot = resizePivot(self.rect, x, y, pad)
    # Send Reside Callback
    elif self.test(wGrab):
      let p = DockMove(x: x, y: y)
      # TODO: don't force callback when
      #       unify queue and event is done
      force(self.cbResize, addr p)
    # Clear Pivot Sides
    elif kind == evCursorRelease:
      self.pivot.sides = {}
    # Check Cursor, Quick and Dirty
    if (self.flags and wHoverGrab) == wHover:
      # TODO: allow custom margin
      let 
        pad = getApp().font.height and not 3
        p = resizePivot(self.rect, x, y, pad)
        name = self.decideCursor(p.sides)
      # Change Cursor Theme
      if name != self.cache:
        if not isNil(name):
          app.setCursor(name)
        else: app.clearCursor()
      self.cache = name

  method draw(ctx: ptr CTXRender) =
    let 
      colors = addr getApp().colors
      # TODO: allow custom margin
      pad0 = getApp().font.height shr 3
      pad1 = pad0 shl 1
    # Calculate Background Rect
    var rect = self.rect
    rect.x += pad0
    rect.y += pad0
    rect.w -= pad1
    rect.h -= pad1
    # Draw Background Rect
    ctx.color colors.panel and 0xC0FFFFFF'u32
    ctx.fill rect(rect)

  method handle(kind: GUIHandle) =
    # Clear X11 Cursor
    if kind == outHover:
      getApp().clearCursor()
      self.cache = nil

# ---------------------------------------
# XXX: hacky way to replace a dock
#      all node awful stuff will be
#      removed after reworking nogui core
# ---------------------------------------
import group

proc replace0awful*(dock, to: UXDock) =
  # Replace Widget
  replace(dock.widget, to.widget)
  # Change Widget
  dock.widget = to.widget
  dock.serial = to.serial
  # Replace Header Data
  privateAccess(UXDockHeader)
  let 
    head {.cursor.} = dock.head
    head0 {.cursor.} = to.head
  head.title = head0.title
  head.icon = head0.icon
  # Update Widget Node if there is one
  let node = dock.node
  if not isNil(node):
    cast[UXDockNode](node).update()
  else: dock.set(wDirty)
