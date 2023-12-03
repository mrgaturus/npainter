import item, list
# Import Builder
import nogui/pack
import nogui/ux/prelude
import nogui/builder
import nogui/values
# Import Widgets
import nogui/ux/layouts/[box, level, form, misc, grid]
import nogui/ux/widgets/[button, check, slider, combo, menu]
import ../../../containers/[dock, scroll]
import ../../../widgets/[separator, menuscroll]

# -----------
# Layers Dock
# -----------

icons "dock/layers", 16:
  layers := "layers.svg"
  # Layer Flags
  clipping := "clipping.svg"
  alpha := "alpha.svg"
  lock := "lock.svg"
  wand := "wand.svg"
  # Layer Addition
  addLayer := "add_layer.svg"
  addMask := "add_mask.svg"
  addFolder := "add_folder.svg"
  # Layer Manipulation
  delete := "delete.svg"
  duplicate := "layers.svg"
  merge := "merge.svg"
  clear := "clear.svg"
  # Position Manipulation
  up := "up.svg"
  down := "down.svg"

controller CXLayersDock:
  attributes:
    # Dummies Mode
    mode: ComboModel
    opacity: @ Lerp
    # Dummies Flags
    clipping: @ bool
    protect: @ bool
    lock: @ bool
    wand: @ bool
    # Usable Dock
    {.public.}:
      dock: UXDock

  callback cbDummy:
    discard

  proc createCombo() =
    self.mode = 
      combomodel(): menu("").child:
        comboitem("Normal", 0)
        menuseparator("Dark")
        comboitem("Multiply", 1)
        comboitem("Darken", 2)
        comboitem("Color Burn", 3)
        comboitem("Linear Burn", 4)
        comboitem("Darker Color", 5)
        menuseparator("Light")
        comboitem("Screen", 6)
        comboitem("Lighten", 7)
        comboitem("Color Dodge", 8)
        comboitem("Linear Dodge", 9)
        comboitem("Lighter Color", 10)
        menuseparator("Contrast")
        comboitem("Overlay", 11)
        comboitem("Soft Light", 12)
        comboitem("Hard Light", 13)
        comboitem("Vivid Light", 14)
        comboitem("Linear Light", 15)
        comboitem("Pin Light", 16)
        menuseparator("Comprare")
        comboitem("Difference", 17)
        comboitem("Exclusion", 18)
        comboitem("Substract", 19)
        comboitem("Divide", 20)
        menuseparator("Composite")
        comboitem("Hue", 21)
        comboitem("Saturation", 22)
        comboitem("Color", 23)
        comboitem("Luminosity", 24)
    # Scroll Menu Hack
    toScrollMenu(self.mode)

  proc createWidget: GUIWidget =
    let cb = self.cbDummy
    # Create Layouts
    vertical().child:
      # Layer Quick Properties
      min: margin(4):
        vertical().child:
          form().child:
            field("Blending"): combobox(self.mode)
            field("Opacity"): slider(self.opacity)
          grid(2, 2).child:
            cell(0, 0): button("Protect Alpha", iconAlpha, self.protect)
            cell(0, 1): button("Clipping", iconClipping, self.clipping)
            cell(1, 0): button("Wand Target", iconWand, self.wand)
            cell(1, 1): button("Lock", iconLock, self.lock)
      # Layer Control
      min: level().child:
        # Layer Creation
        button(iconAddLayer, cb).opaque()
        button(iconAddMask, cb).opaque()
        button(iconAddFolder, cb).opaque()
        vseparator() # Layer Manipulation
        button(iconDelete, cb).opaque()
        button(iconDuplicate, cb).opaque()
        button(iconMerge, cb).opaque()
        button(iconClear, cb).opaque()
        # Misc Buttons
        tail: button(iconUp, cb).opaque()
        tail: button(iconDown, cb).opaque()
      # Layer Item
      scrollview(): 
        layerlist().child:
          layeritem(0)
          #layeritem(1)
          #layeritem(1)
          #layeritem(2)
          #layeritem(2)
          #layeritem(2)
          #layeritem(1)

  proc createDock() =
    let w = self.createWidget()
    self.dock = dock("Layers", iconLayers, w)

  new cxlayersdock():
    result.opacity = value lerp(0, 100)
    result.createCombo()
    result.createDock()
