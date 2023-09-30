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

  # -- Dock Callbacks --
  callback cbMove(p: DockMove):
    self.move(p.x, p.y)

  callback cbResize(p: DockMove):
    let
      p0 = self.pivot
      dx = p.x - p0.x
      dy = p.y - p0.y
    # Apply Resize to Dock
    self.apply resize(p0, dx, dy)

  # -- Dock Constructor --
  new dock(title: string, icon: CTXIconID, w: GUIWidget):
    result.kind = wgFrame
    result.flags = wMouse or wKeyboard
    # Create Dock Head
    let head = dockhead(title, icon)
    head.onmove = result.cbMove
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
      pad0 = getApp().font.asc and not 3
      pad1 = pad0 shr 1
      pad2 = pad0 shr 2
    # Header Metrics
    m0.x = pad2
    m0.w = m.w - pad1
    m0.y = pad2
    m0.h = m0.minH
    # Body Metrics
    m1.x = pad1
    m1.w = m.w - pad0
    m1.y = m0.h + pad1
    m1.h = m.h - m0.h - pad0

  method event(state: ptr GUIState) =
    let
      x = state.mx
      y = state.my
    if state.kind == evCursorClick:
      # TODO: allow custom margin
      let pad = getApp().font.asc and not 3
      self.pivot = resizePivot(self.rect, x, y, pad)
    elif self.test(wGrab):
      let p = DockMove(x: x, y: y)
      push(self.cbResize, p)

  method draw(ctx: ptr CTXRender) =
    let 
      rect = rect self.rect
      colors = addr getApp().colors
      # TODO: allow custom margin
    ctx.color colors.panel and 0xC0FFFFFF'u32
    ctx.fill rect
