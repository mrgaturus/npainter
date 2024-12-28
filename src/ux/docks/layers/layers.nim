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
    layers: CXLayers
    list: UXLayerList
    # Combobox Modes
    modeMask: ComboModel
    modeColor: ComboModel
    modeCombo: UXComboBox
    itemNormal: UXComboItem
    itemPass: UXComboItem
    # Usable Dock
    {.public.}:
      dock: UXDockContent

  callback cbUpdate:
    let layer = self.layers.target
    let mode = layer.props.mode
    # Detach Passthrough
    let pass = self.itemPass
    if not isNil(pass.prev):
      pass.detach()
      wasMoved(pass.prev)
    # Select Current Model
    let model {.cursor.} =
      if layer.kind != lkMask:
        self.modeColor
      else: self.modeMask
    if layer.kind == lkFolder:
      attachNext(self.itemNormal, pass)
    # Select Without Callback
    wasMoved(model.onchange)
    model.select(ord mode)
    model.onchange = self.cbChangeMode
    model(self.modeCombo, model)
    send(self.modeCombo, wsLayout)

  callback cbChangeMode:
    let layer = self.layers.target
    let model {.cursor.} =
      if layer.kind != lkMask:
        self.modeColor
      else: self.modeMask
    # Change Current Blend Mode
    let m = react(self.layers.mode)
    m[] = NBlendMode(model.selected.value)

  callback cbStructure:
    self.list.reload()

  proc createCombo() =
    self.itemNormal = comboitem(bmNormal)
    self.itemPass = comboitem(bmPassthrough)
    self.modeMask =
      combomodel(): menu("").child:
        comboitem(bmMask)
        comboitem(bmStencil)
    self.modeColor =
      combomodel(): menu("").child:
        self.itemNormal
        self.itemPass
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
    self.modeColor.onchange = self.cbChangeMode
    self.modeMask.onchange = self.cbChangeMode
    self.modeCombo = combobox(self.modeColor)

  proc createWidget: GUIWidget =
    let la = self.layers
    # Create Layer List
    self.list = layerlist(self.layers)
    self.list.reload()
    # Create Layouts
    vertical().child:
      # Layer Quick Properties
      min: margin(4):
        vertical().child:
          form().child:
            field("Blending"): self.modeCombo
            field("Opacity"): slider(la.opacity)
          grid(2, 2).child:
            cell(0, 0): button("Protect Alpha", iconAlpha, la.protect)
            cell(0, 1): button("Clipping", iconClipping, la.clipping)
            cell(1, 0): button("Wand Target", iconWand, la.wand)
            cell(1, 1): button("Lock", iconLock, la.lock)
      # Layer Control
      min: level().child:
        # Layer Creation
        glass: button(iconAddLayer, la.cbCreateLayer)
        glass: button(iconAddMask, la.cbCreateMask)
        glass: button(iconAddFolder, la.cbCreateFolder)
        vseparator()
        # Layer Manipulation
        glass: button(iconDuplicate, la.cbDuplicateLayer)
        glass: button(iconMerge, la.cbMergeLayer)
        glass: button(iconClear, la.cbClearLayer)
        glass: button(iconDelete, la.cbRemoveLayer)
        # Layer Reordering Buttons
        tail: glass: button(iconUp, la.cbRaiseLayer)
        tail: glass: button(iconDown, la.cbLowerLayer)
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
