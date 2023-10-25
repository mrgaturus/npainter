import nogui/ux/prelude
import nogui/builder
# Import Shared Values
import nogui/gui/value
# Import A Dock
import nogui/ux/widgets/[color, menu]
import ../../../containers/dock
# Import Color
import ../../color
import base

# -----------------
# Simple Color Dock
# -----------------

controller CXColorDock:
  attributes:
    c: CXColor
    # Color Wheels
    wheel: UXColorWheel
    wheel0tri: UXColorWheel0Triangle
    cube: UXColorCube
    cube0tri: UXColorCube
    # Color Dock Body
    base: UXColorBase
    # Selected Picker
    option: @ int32
    {.cursor.}:
      select: GUIWidget
    # Dock Handle
    {.public.}:
      dock: UXDock

  # -- Color Pickers --
  proc selectPicker =
    let 
      option = peek(self.option)[]
      select = self.select
    # Select Picker Accouring Option
    let found = case option:
    of 0: self.wheel
    of 1: self.wheel0tri
    of 2: self.cube
    of 3: self.cube0tri
    else: self.wheel
    # Replace Selected With Current
    if found != select:
      let b = self.base
      b.body = found
      b.set(wDirty)

  proc createPickers =
    let c = addr self.c.color
    # Initialize Color Widgets
    self.wheel = colorwheel(c)
    self.wheel0tri = colorwheel0triangle(c)
    self.cube = colorcube(c)
    self.cube0tri = colorcube0triangle(c)
    # Create Color Picker Selection
    self.option = value(int32 1, self.cbPicker)

  # -- Dock Creation --
  callback cbPicker:
    self.selectPicker()

  proc createMenu: UXMenu =
    let option = addr self.option
    # Create Menu Option
    menu("dock#color").child:
      menuseparator("HSV Wheel")
      menuoption("Wheel Square", option, 0)
      menuoption("Wheel Triangle", option, 1)
      menuseparator("HSV Bar")
      menuoption("Bar Square", option, 2)
      menuoption("Bar Triangle", option, 3)

  proc createDock =
    # Create Dock and Define Menu
    let
      base = colorbase(self.c)
      dock = dock("Color", iconDockColor, base)
    dock.bindMenu self.createMenu()
    # Set Current Dock
    self.dock = dock
    self.base = base

  new cxcolordock(color: CXColor):
    result.c = color
    # Initialize Dock Widgets
    result.createDock()
    result.createPickers()
    result.selectPicker()
