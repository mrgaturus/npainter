import menu, tools, ../../containers/[main, dock, dock/group]
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

  proc dummyDock(w: GUIWidget, open = true): UXDock =
    result = dock("Color", iconTest, w)
    result.move(20, 20)
    result.resize(200, 200)
    if open: result.open()
    # Add Dummy Menu
    result.bindMenu:
      menu("Color").child:
        menuseparator("HSV Wheel")
        menuoption("Wheel Square", self.selected, 0)
        menuoption("Wheel Triangle", self.selected, 1)
        menuseparator("HSV Bar")
        menuoption("Bar Square", self.selected, 2)
        menuoption("Bar Triangle", self.selected, 3)

  proc createFrame*: UXMainFrame =
    let
      title = createMenu(self.ncmenu)
      tools = createToolbar(self.nctools)
      # Open Some Docks
      col = addr self.color
      dock1 = self.dummyDock(colorcube col)
      dock2 = self.dummyDock(colorcube0triangle col)
      dock3 = self.dummyDock(colorwheel0triangle col)
      dock4 {.used.} = self.dummyDock(colorwheel col)
      # Create Frame Group
      row0 = dockrow()
      group = dockgroup(row0)
      row1 = dockrow()
      node0 = docknode(dock1)
      node1 = docknode(dock2)
      node2 = docknode(dock3)
      node3 = docknode(dock4)
    row0.attach(node0)
    node0.attach(node1)
    node1.attach(node2)
    # Second Row Attach
    row1.attach(node3)
    row0.attach(row1)
    # Create Group
    group.move(20, 20)
    group.open()
    # Return Main Frame
    mainframe title, mainbody(tools, dummy())

  new ncMainWindow():
    result.ncmenu = ncMainMenu()
    result.nctools = ncMainTools()

