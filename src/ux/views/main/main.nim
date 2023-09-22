import menu, tools, ../../containers/main
from nogui/builder import widget, controller, child

widget UXMainDummy:
  new dummy(): 
    discard

controller NCMainFrame:
  attributes:
    ncmenu: NCMainMenu
    nctools: NCMainTools

  proc createFrame*: UXMainFrame =
    let
      title = createMenu(self.ncmenu)
      tools = createToolbar(self.nctools)
    mainframe title, mainbody(tools, dummy())

  new ncMainWindow():
    result.ncmenu = ncMainMenu()
    result.nctools = ncMainTools()

