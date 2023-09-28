from nogui/ux/widgets/menu import UXMenu
import nogui/ux/prelude
import ./dock/[header, snap]

widget UXDock:
  attributes:
    {.cursor.}:
      head: UXDockHeader
      widget: GUIWidget

  # -- Dock Callbacks --
  callback cbMove(p: DockMove):
    self.move(p.x, p.y)

  callback cbResize(p: DockSnap):
    discard

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
      pad = getApp().font.asc shr 1
      pad0 = pad shr 1
      #pad = 0'i16
    # Calculate Min Size X
    m0.x = pad0; m0.w = m.w - pad
    m1.x = pad0; m1.w = m.w - pad
    # Calculate Min Size Y
    m0.y = pad0
    m0.h = m0.minH
    m1.y = m0.h + pad0
    m1.h = m.h - m0.h - pad

  method event(state: ptr GUIState) =
    discard

  method draw(ctx: ptr CTXRender) =
    let 
      rect = rect self.rect
      colors = addr getApp().colors
      # TODO: allow custom margin
      pad = getApp().font.asc shr 2
    ctx.color colors.panel and 0xCDFFFFFF'u32
    ctx.fill rect
    #ctx.color colors.item
    #ctx.line rect, float32 pad