import menu, tools, ../../containers/[main, dock]
from nogui/builder import widget, controller, child
import nogui/ux/prelude
import nogui/ux/widgets/menu
import nogui/ux/widgets/color
import nogui/values
from nogui/pack import icons

icons "dock", 16:
  test := "test.svg"

widget UXMainDummy:
  attributes:
    color: uint32

  new dummy(w, h: int16): 
    result.metrics.minW = w
    result.metrics.minH = h
    result.color = 0xFFFFFFFF'u32

  new dummy():
    discard

  method layout =
    for w in forward(self.first):
      let m = addr w.metrics
      m.h = m.minH

  method draw(ctx: ptr CTXRender) =
    ctx.color self.color
    ctx.fill rect(self.rect)

controller NCMainFrame:
  attributes:
    ncmenu: NCMainMenu
    nctools: NCMainTools
    selected: @ int32
    color: HSVColor

  callback dummy: 
    discard

  proc createFrame*: UXMainFrame =
    let
      title = createMenu(self.ncmenu)
      tools = createToolbar(self.nctools)
    # Open Some Docks
    let dock0 = dock("Color", iconTest, colorwheel(addr self.color))
    dock0.move(20, 20)
    dock0.resize(200, 200)
    dock0.open()
    dock0.bindMenu: 
      menu("Color").child:
        menuseparator("HSV Wheel")
        menuoption("Wheel Square", self.selected, 0)
        menuoption("Wheel Triangle", self.selected, 1)
        menuseparator("HSV Bar")
        menuoption("Bar Square", self.selected, 2)
        menuoption("Bar Triangle", self.selected, 3)
    # Open Some Docks
    let dock1 = dock("Color", iconTest, colorcube(addr self.color))
    dock1.move(20, 20)
    dock1.resize(200, 200)
    dock1.open()
    dock1.bindMenu: 
      menu("Color").child:
        menuseparator("HSV Wheel")
        menuoption("Wheel Square", self.selected, 0)
        menuoption("Wheel Triangle", self.selected, 1)
        menuseparator("HSV Bar")
        menuoption("Bar Square", self.selected, 2)
        menuoption("Bar Triangle", self.selected, 3)
    # Return Main Frame
    mainframe title, mainbody(tools, dummy())

  new ncMainWindow():
    result.ncmenu = ncMainMenu()
    result.nctools = ncMainTools()

