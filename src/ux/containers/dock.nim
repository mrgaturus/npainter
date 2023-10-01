from nogui/ux/widgets/menu import UXMenu
import nogui/ux/prelude
import ./dock/[header, snap]

widget UXDock:
  attributes:
    {.cursor.}:
      head: UXDockHeader
      widget: GUIWidget
    # Resize Pivot
    pivot: DockResize
    fold: int16

  proc unfolded: bool =
    (self.widget.flags and wHidden) == 0

  proc apply(r: GUIRect) =
    let m = addr self.metrics
    # Clamp Dimensions
    m.w = int16 max(m.minW, r.w)
    m.h = int16 max(m.minH, r.h)
    # Apply Position, Avoid Moving Side
    if r.x != m.x: m.x = int16 r.x - m.w + r.w
    if r.y != m.y: m.y = int16 r.y - m.h + r.h
    # Action Update
    self.set(wDirty)

  # -- Dock Move Callbacks --
  callback cbMove(p: DockMove):
    self.move(p.x, p.y)

  callback cbResize(p: DockMove):
    let
      p0 = self.pivot
      dx = p.x - p0.x
      dy = p.y - p0.y
    # Apply Resize to Dock
    self.apply resize(p0, dx, dy)

  # -- Dock Button Callbacks --
  callback cbFold:
    let 
      w = self.widget
      m = addr self.metrics
      # TODO: allow custom margin
      pad = getApp().font.asc shr 1
    var flags = w.flags
    # Toggle Widget Hidden
    let check = self.unfolded
    if check:
      flags.set(wHidden)
      self.fold = m.h
      # Remove Dimensions
      m.h -= w.metrics.h + pad
    else: # Restore Dimensions
      flags.clear(wHidden)
      m.h = self.fold
    # Change Flags
    w.flags = flags
    # Notify Callback
    notifyFold(self.head, not check)
    self.set(wDirty)

  callback cbClose:
    self.close()

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

  proc bindMenu*(m: UXMenu) {.inline.} =
    bindMenu(self.head, m)

  # -- Widget Methods --
  method update =
    let
      m = addr self.metrics
      m0 = addr self.head.metrics
      m1 = addr self.widget.metrics
      # TODO: allow custom margin
      pad = getApp().font.asc
    # Calculate Min Size
    m.minW = m0.minW + m1.minW + pad
    m.minH = m0.minH + m1.minH + pad

  method layout =
    let
      m = addr self.metrics
      m0 = addr self.head.metrics
      m1 = addr self.widget.metrics
      # TODO: allow custom margin
      pad0 = getApp().font.height and not 3
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
    # Body Metrics
    m1.x = 0
    m1.w = m.w
    m1.y = m0.h
    m1.h = m.h - m1.y
    # Apply Padding
    m0.margin(pad, pad, 0)
    m1.margin(pad, pad, pad)
    m1.y += pad1
    m1.h -= pad1

  method event(state: ptr GUIState) =
    let
      x = state.mx
      y = state.my
    if state.kind == evCursorClick:
      # TODO: allow custom margin
      let pad = getApp().font.asc and not 3
      self.pivot = resizePivot(self.rect, x, y, pad)
    # Send Reside Callback if not folded
    elif self.test(wGrab) and self.unfolded:
      let p = DockMove(x: x, y: y)
      push(self.cbResize, p)

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
