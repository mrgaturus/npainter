import list
# Import Builder
import nogui/pack
import nogui/ux/prelude
import nogui/builder
# Import Widgets
import nogui/ux/layouts/[box, level, form, misc, grid]
import nogui/ux/widgets/[button, check, slider, combo, menu]
import nogui/ux/containers/[dock, scroll]
import nogui/ux/separator
# Import Layer State
import ../../state/layers

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
    # Combomodel
    layers: CXLayers
    list: UXLayerList
    mode: ComboModel
    # Usable Dock
    {.public.}:
      dock: UXDockContent

  callback cbUpdate:
    let m = peek(self.layers.mode)[]
    self.mode.select(ord m)

  callback cbChangeMode:
    let m = react(self.layers.mode)
    m[] = NBlendMode(self.mode.selected.value)
    echo "Selected Value:", self.mode.selected.value

  callback cbStructure:
    self.list.reloadProofLayerList()

  callback cbDummy:
    discard

  proc createCombo() =
    self.mode = 
      combomodel(): menu("").child:
        comboitem("Normal", ord bmNormal)
        menuseparator("Dark")
        comboitem("Multiply", ord bmMultiply)
        comboitem("Darken", ord bmDarken)
        comboitem("Color Burn", ord bmColorBurn)
        comboitem("Linear Burn", ord bmLinearBurn)
        comboitem("Darker Color", ord bmDarkerColor)
        menuseparator("Light")
        comboitem("Screen", ord bmScreen)
        comboitem("Lighten", ord bmLighten)
        comboitem("Color Dodge", ord bmColorDodge)
        comboitem("Linear Dodge", ord bmLinearDodge)
        comboitem("Lighter Color", ord bmLighterColor)
        menuseparator("Contrast")
        comboitem("Overlay", ord bmOverlay)
        comboitem("Soft Light", ord bmSoftLight)
        comboitem("Hard Light", ord bmHardLight)
        comboitem("Vivid Light", ord bmVividLight)
        comboitem("Linear Light", ord bmLinearLight)
        comboitem("Pin Light", ord bmPinLight)
        menuseparator("Comprare")
        comboitem("Difference", ord bmDifference)
        comboitem("Exclusion", ord bmExclusion)
        comboitem("Substract", ord bmSubstract)
        comboitem("Divide", ord bmDivide)
        menuseparator("Composite")
        comboitem("Hue", ord bmHue)
        comboitem("Saturation", ord bmSaturation)
        comboitem("Color", ord bmColor)
        comboitem("Luminosity", ord bmLuminosity)
    # Change Blending Callback
    self.mode.onchange = self.cbChangeMode

  proc createWidget: GUIWidget =
    let
      cb = self.cbDummy
      la = self.layers
    # Create Layer List
    self.list = layerlist(self.layers)
    self.list.reloadProofLayerList()
    # Create Layouts
    vertical().child:
      # Layer Quick Properties
      min: margin(4):
        vertical().child:
          form().child:
            field("Blending"): combobox(self.mode)
            field("Opacity"): slider(la.opacity)
          grid(2, 2).child:
            cell(0, 0): button("Protect Alpha", iconAlpha, la.protect)
            cell(0, 1): button("Clipping", iconClipping, la.clipping)
            cell(1, 0): button("Wand Target", iconWand, la.wand)
            cell(1, 1): button("Lock", iconLock, la.lock)
      # Layer Control
      min: level().child:
        # Layer Creation
        button(iconAddLayer, la.cbCreateLayer).clear()
        button(iconAddMask, cb).clear()
        button(iconAddFolder, cb).clear()
        vseparator() # Layer Manipulation
        button(iconDelete, la.cbRemoveLayer).clear()
        button(iconDuplicate, cb).clear()
        button(iconMerge, cb).clear()
        button(iconClear, la.cbClearLayer).clear()
        # Misc Buttons
        tail: button(iconUp, cb).clear()
        tail: button(iconDown, cb).clear()
      # Layer Item
      scrollview():
        self.list

  proc createDock() =
    let w = self.createWidget()
    self.dock = dockcontent("Layers", iconLayers, w)

  new cxlayersdock(layers: CXLayers):
    result.layers = layers
    # Create Docks
    result.createCombo()
    result.createDock()
    # Configure Callbacks
    result.layers.onselect = result.cbUpdate
    result.layers.onstructure = result.cbStructure
