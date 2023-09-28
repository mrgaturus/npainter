# TODO: menu button
from nogui/pack import icons
import nogui/ux/[prelude, labeling]
# Import Widget Helpers
from nogui/builder import child
from nogui/ux/layouts import level
from nogui/ux/widgets/menu import UXMenu
from nogui/ux/widgets/button import
  UXButton, UXIconButton, button, opaque
# Allow Private Access
import std/importutils
# Import Docking Snapping
import snap

# ------------------
# Widget Dock Header
# ------------------

icons "dock", 16:
  # Menu Context Button
  context := "context.svg"
  # Collapse Button
  visible := "visible.svg"
  collapse := "collapse.svg"
  # Close Button
  close := "close.svg"

widget UXDockHeader:
  attributes:
    # Header Labeling
    title: string
    icon: CTXIconID
    lm: GUILabelMetrics
    # Context Menu
    menu: UXMenu
    # Header Buttons
    {.cursor.}:
      btnCollapse: UXIconButton
      btnClose: UXIconButton
      btnMenu: UXIconButton
    # Dock Moving Operation
    {.public.}:
      pivot: DockMove
      capture: GUIRect
      # Dock Moving Callback
      onmove: GUICallbackEX[DockMove]

  callback cbMenu:
    let 
      menu {.cursor.} = self.menu
      loc = addr self.btnMenu.rect
    # Open Header Menu
    if not isNil(menu):
      if not menu.test(wVisible):
        menu.open()
        # Move Nearly to Button Menu
        menu.move(loc.x, loc.y + loc.h)
      else: menu.close()

  new dockhead(title: string, icon = CTXIconEmpty):
    result.flags = wMouse
    result.title = title
    result.icon = icon
    # Dummy Callback
    let 
      dummy = GUICallback()
      btnMenu = button(iconContext, result.cbMenu)
      btnCollapse = button(iconVisible, dummy)
      btnClose = button(iconClose, dummy)
    # Add Buttons
    result.add: 
      level().child:
        btnClose.opaque()
        btnCollapse.opaque()
        btnMenu.opaque()
    # Store Buttons
    result.btnMenu = btnMenu
    result.btnCollapse = btnCollapse
    result.btnClose = btnClose

  proc bindButtons*(onclose, oncollapse: GUICallback) =
    privateAccess(UXButton)
    # Bind Header Callbacks
    self.btnCollapse.cb = oncollapse
    self.btnClose.cb = onclose

  proc bindMenu*(menu: UXMenu) {.inline.} =
    menu.kind = wgPopup
    self.menu = menu

  proc notifyCollapse*(check: bool) =
    privateAccess(UXIconButton)
    # Change Icon Collapse
    self.btnCollapse.icon =
      if check: iconCollapse
      else: iconVisible

  method update =
    let
      # Dock Header Metrics
      m = addr self.metrics
      lvl = addr self.first.metrics
      # TODO: allow customize margin
      lm = metricsLabel(self.title, self.icon)
      pad = getApp().font.size
    # TODO: Other Layout for Packed
    lvl.minW -= pad shr 1
    # Calculate Min Size
    m.minW = lm.w + pad + lvl.minW
    m.minH = max(lm.h, lvl.minH)
    # Set Label Metrics
    self.lm = lm

  method layout =
    let
      m = addr self.metrics
      lvl = addr self.first.metrics
    # Arrange Buttons to Right
    lvl.x = m.w - lvl.minW
    lvl.w = lvl.minW
    lvl.h = m.minH

  method draw(ctx: ptr CTXRender) =
    var
      app = getApp()
      colors = app.colors
      p = left(self.lm, self.rect)
      o = app.font.size shr 1
    # Fill Background Color
    if self.any(wHoverGrab):
      ctx.color colors.item and 0x7FFFFFFF'u32
      ctx.fill rect(self.rect)
    ctx.color colors.text
    # Draw Icon And Title
    ctx.icon(self.icon, p.xi + o, p.yi)
    ctx.text(p.xt + o, p.yt, self.title)

  method event(state: ptr GUIState) =
    var p = DockMove(x: state.mx, y: state.my)
    if state.kind == evCursorClick:
      # Capture Pivot Point
      self.pivot = p
      self.capture = self.parent.rect
    elif self.test(wGrab):
      let
        p0 = self.pivot
        r = self.capture
      p.x = (p.x - p0.x) + r.x
      p.y = (p.y - p0.y) + r.y
      push(self.onmove, p)

# ---------------
# Debug Propurses
# ---------------

icons "dock", 16:
  test := "test.svg"

proc headtest*(title: string, x, y, w: int16, menu: UXMenu): UXDockHeader =
  result = dockhead(title, iconTest)
  result.metrics.x = x
  result.metrics.y = y
  result.metrics.w = w
  result.bindMenu(menu)