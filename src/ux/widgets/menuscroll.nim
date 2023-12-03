from nogui import windowSize
# TODO: create proper implementation at nogui
import nogui/ux/widgets/[menu, combo]
import nogui/ux/prelude
import ../containers/scroll

# ---------------------
# Menu Scrollbar Widget
# XXX: proof of concept
# ---------------------

widget UXMenuScroll of UXMenu:
  attributes:
    {.cursor.}:
      menu: UXMenu
      scroll: UXScrollView
      onextra: GUICallback
    {.public.}:
      shift: int16

  callback cbCloseHook:
    self.close()
    privateAccess(UXMenu)
    # Remove Selected
    self.selected = nil
    push(self.onextra)

  new menuscroll(menu: UXMenu):
    let scroll = scrollview(menu)
    scroll.noMargin = true
    # Set Menu and Hook Top Menu
    privateAccess(UXMenu)
    result.menu = menu
    menu.top = result
    menu.cbClose = result.cbCloseHook
    # Set Scrollview
    result.scroll = scroll
    result.add scroll
    # Set Default Flags
    result.flags = wMouse
    result.kind = wgPopup

  method update =
    let 
      m = addr self.metrics
      ms = addr self.scroll.metrics
      mm = addr self.menu.metrics
      # Window Height Size
      app = getApp()
      h = int16 app.windowSize.h
      font = addr app.font
      # Menu Location
      y0 = m.y
      y1 = y0 + mm.minH
      shift = self.shift
    # Set Minimun Size as Scroll Size
    m.minW = ms.minW
    m.minH = ms.minH
    # Adjust Y Offset
    if h - y0 > (mm.minH shr shift):
      # Adjust Vertical Size
      let o = min(y1, h)
      m.h = o - y0
    else: # Move to Upper
      let
        size = font.height + font.asc
        o = min(y0 - size, mm.minH)
      m.y = y0 - size - o
      m.h = o

  method layout =
    let
      m = addr self.metrics
      ms = addr self.scroll.metrics
      mm = addr self.menu.metrics
    # Adjust Scroll View
    ms.x = 0
    ms.y = 0
    # Set As Min Size
    ms.w = m.w
    ms.h = m.h
    mm.minW = m.w

# ---------------------------
# Menu Scrollbar to Comboitem
# XXX: proof of concept
# ---------------------------

proc toScrollMenu*(model: ComboModel, shift = 2) =
  privateAccess(ComboModel)
  let
    hacky = addr model.menu
    mscroll = menuscroll(model.menu)
  # Extra Hooks For ComboModel
  mscroll.shift = int16 shift
  mscroll.onextra = model.onchange
  hacky[] = mscroll
