from nogui/builder import controller, child
from tools import iconLogo
import nogui/ux/prelude
import nogui/ux/widgets/menu
import nogui/ux/widgets/button

widget UXNoClick:
  new noclick(w: GUIWidget):
    result.add w
    w.flags = {wHidden}

  method draw(ctx: ptr CTXRender) =
    let w {.cursor.} = self.first
    w.vtable.draw(w, ctx)

  method update =
    self.metrics = self.first.metrics

  method layout =
    self.first.metrics = self.metrics

# --------------------
# Main Menu Controller
# --------------------

controller NCMainMenu:
  callback dummy:
    echo "not implemented yet"

  new ncMainMenu():
    discard

  proc menuFile: UXMenu =
    let dummy = self.dummy
    echo dummy.repr
    menu("File").child:
      menuitem("New ..", self.dummy)
      menuitem("New From Clipboard", dummy)
      menuitem("Close", dummy)
      # -- Opening --
      menuseparator()
      menuitem("Open ..", dummy)
      menuitem("Import ..", dummy)
      # TODO: calculate recent files
      menu("Recent Files").child:
        menuitem("fileA.npi", dummy)
        menuitem("fileB.npi", dummy)
        menuseparator()
        menuitem("Clear Recents", dummy)
      # -- Saving --
      menuseparator()
      menuitem("Save", dummy)
      menuitem("Save As ..", dummy)
      menuitem("Export ..", dummy)
      # -- Program Stuff --
      menuseparator("NPainter")
      menuitem("Settings ..", dummy)
      menuitem("About ..", dummy)
      menuitem("Exit", dummy)

  proc menuEdit: UXMenu =
    let dummy = self.dummy
    menu("Edit").child:
      menuitem("Undo", dummy)
      menuitem("Redo", dummy)
      # -- Clipboard --
      menuseparator()
      menuitem("Copy", dummy)
      menuitem("Cut", dummy)
      menuitem("Paste", dummy)
      # -- Transform Tools --
      menuseparator("Transform Tools")
      menuitem("Perspective", dummy)
      menuitem("Mesh", dummy)
      menuitem("Liquify", dummy)

  proc menuCanvas: UXMenu =
    let dummy = self.dummy
    menu("Canvas").child:
      menuitem("Change Dimensions ..", dummy)
      menuitem("Scale Canvas ..", dummy)
      menuitem("Crop to Selection", dummy)
      # -- Basic Transform --
      menuseparator("Basic Transform")
      menuitem("Rotate Left", dummy)
      menuitem("Rotate Right", dummy)
      menuitem("Flip Horizontal", dummy)
      menuitem("Flip Vertical", dummy)
      # -- Canvas Style --
      menuseparator("Style")
      menu("Background Color").child:
        menuitem("White Color", dummy)
        menuitem("Other Color ..", dummy)
        menuseparator()
        menuitem("Transparent Light", dummy)
        menuitem("Transparent Dark", dummy)

  proc menuLayer: UXMenu =
    let dummy = self.dummy
    menu("Layer").child:
      menuitem("Add Layer", dummy)
      menuitem("Add Folder", dummy)
      menuitem("Add Mask", dummy)
      menuitem("Add from Canvas", dummy)
      # -- Operations --
      menuseparator("Operations")
      menuitem("Merge Down", dummy)
      menuitem("Rasterize", dummy)
      menuseparator()
      menuitem("Duplicate", dummy)
      menuitem("Delete", dummy)
      menuitem("Clear", dummy)
      menuitem("Color Fill", dummy)
      menuseparator()
      menuitem("Raise", dummy)
      menuitem("Lower", dummy)
      menuitem("Properties ..", dummy)
      # -- Basic Transform --
      menuseparator("Basic Transform")
      menuitem("Rotate Left", dummy)
      menuitem("Rotate Right", dummy)
      menuitem("Flip Horizontal", dummy)
      menuitem("Flip Vertical", dummy)

  proc menuSelection: UXMenu =
    let dummy = self.dummy
    menu("Selection").child:
      menuitem("All", dummy)
      menuitem("Deselect", dummy)
      menuitem("Invert", dummy)
      menuitem("Extract", dummy)
      menuseparator()
      menuitem("Selection from Opacity", dummy)
      menuitem("Selection from Brightness", dummy)
      # -- Morphology --
      menuseparator("Morphology")
      menuitem("Erode ..", dummy)
      menuitem("Dilate ..", dummy)
      menuitem("Flatten ..", dummy)
      # -- Border --
      menuseparator("Border")
      menuitem("Outline ..", dummy)
      menuitem("Silhouette ..", dummy)

  proc menuFilters: UXMenu =
    let dummy = self.dummy
    menu("Filters").child:
      menuitem("Brightness & Contrast", dummy)
      menuitem("Hue & Saturation", dummy)
      menuitem("Grayscale", dummy)
      menuitem("Invert", dummy)
      menuitem("Sepia", dummy)
      # -- More Filters --
      menuseparator()
      menu("Adjustment").child: menuitem("Work in progress", dummy)
      menu("Blur").child: menuitem("Work in progress", dummy)
      menu("Artistic").child: menuitem("Work in progress", dummy)
      menu("Distort").child: menuitem("Work in progress", dummy)

  proc menuWindow: UXMenu =
    menu("Window").child:
      menuitem("Work in progress", self.dummy)

  proc menuLogo: UXNoClick =
    result = noclick button(iconLogo, self.dummy).clear()

  proc createMenu*(): UXMenuBar =
    menubar().child:
      self.menuLogo()
      self.menuFile()
      self.menuEdit()
      self.menuCanvas()
      self.menuLayer()
      self.menuSelection()
      self.menuFilters()
      self.menuWindow()
