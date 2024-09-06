import item, list
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

proc comboitem(mode: NBlendMode): UXComboItem =
  comboitem($blendname[mode], ord mode)

# -----------
# Layers Dock
# -----------

icons "dock/layers", 16:
  layers := "layers.svg"
  # Layer Button Addition
  addLayer := "add_layer.svg"
  addMask := "add_mask.svg"
  addFolder := "add_folder.svg"
  # Layer Button Manipulation
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

  callback cbStructure:
    self.list.reload()

  callback cbDummy:
    discard

  proc createCombo() =
    self.mode = 
      combomodel(): menu("").child:
        comboitem(bmNormal)
        menuseparator("Dark")
        comboitem(bmMultiply)
        comboitem(bmDarken)
        comboitem(bmColorBurn)
        comboitem(bmLinearBurn)
        comboitem(bmDarkerColor)
        menuseparator("Light")
        comboitem(bmScreen)
        comboitem(bmLighten)
        comboitem(bmColorDodge)
        comboitem(bmLinearDodge)
        comboitem(bmLighterColor)
        menuseparator("Contrast")
        comboitem(bmOverlay)
        comboitem(bmSoftLight)
        comboitem(bmHardLight)
        comboitem(bmVividLight)
        comboitem(bmLinearLight)
        comboitem(bmPinLight)
        menuseparator("Comprare")
        comboitem(bmDifference)
        comboitem(bmExclusion)
        comboitem(bmSubstract)
        comboitem(bmDivide)
        menuseparator("Composite")
        comboitem(bmHue)
        comboitem(bmSaturation)
        comboitem(bmColor)
        comboitem(bmLuminosity)
    # Change Blending Callback
    self.mode.onchange = self.cbChangeMode

  proc createWidget: GUIWidget =
    let
      cb = self.cbDummy
      la = self.layers
    # Create Layer List
    self.list = layerlist(self.layers)
    self.list.reload()
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
        button(iconAddFolder, la.cbCreateFolder).clear()
        vseparator() # Layer Manipulation
        button(iconDuplicate, la.cbDuplicateLayer).clear()
        button(iconMerge, cb).clear()
        button(iconClear, la.cbClearLayer).clear()
        button(iconDelete, la.cbRemoveLayer).clear()
        # Layer Reordering Buttons
        tail: button(iconUp, la.cbRaiseLayer).clear()
        tail: button(iconDown, la.cbLowerLayer).clear()
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
    # Configure Layer Controller Callbacks
    result.layers.onselect = result.cbUpdate
    result.layers.onstructure = result.cbStructure
