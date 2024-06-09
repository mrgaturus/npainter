import nogui/builder
import nogui/core/widget
import nogui/ux/layouts/[base, box, misc]
import nogui/ux/widgets/[button, combo, menu, label]
# Import Icons Macro
import nogui/pack

# ------------------------
# Brush Section Controller
# ------------------------

icons "dock", 16:
  fold0 := "visible.svg"
  fold1 := "fold.svg"

controller CXBrushSection:
  attributes:
    index: int32
    model: ComboModel
    views: seq[GUIWidget]
    # Button And Combobox
    {.cursor.}:
      button: UXButtonCB
      combo: UXComboBox
      view: GUIWidget
    # Public Section
    {.public.}:
      section: GUIWidget
      onchange: GUICallback

  proc register*(w: GUIWidget) =
    self.views.add margin(4, w)

  proc registerEmpty*() =
    # Use Section for Empty Check
    self.views.add(self.section)

  proc update*() =
    privateAccess(UXButtonBase)
    # Update Button Icon
    self.button.icon =
      if isNil(self.view): 
        iconFold0
      else: iconFold1

  # -- View Chooser --
  proc selectView(index: int32) =
    if index < len(self.views):
      let 
        v {.cursor.} = self.view
        w {.cursor.} = self.views[index]
        s {.cursor.} = self.section
      # Replace View if not section
      if not isNil(v) and w != v:
        if w == s and v != s:
          v.detach()
        elif v == s: s.add w
        else: v.replace(w)
        # Replace View
        self.view = w
        s.parent.send(wsLayout)
      # Replace Index
      self.index = index
      self.update()

  # XXX: this is for proof of concept
  #      meanwhile proper brush dialogs
  #      are done
  proc selectProof*(index: int32) =
    if index == self.index: return
    # Replace Selected Index
    self.model.select(index)
    self.selectView(index)

  # -- Section Callbacks --
  callback cbChange:
    let idx = self.model.selected.value
    self.selectView(int32 idx)
    # Run Change Callback
    force(self.onchange)

  callback cbFold:
    let 
      w = self.views[self.index]
      s {.cursor.} = self.section
    # Prepare View to be Toggled
    var v {.cursor.} = self.view
    # Toggle View
    if isNil(v):
      if w != s: 
        s.add(w)
      v = w
    else: # Remove View
      if v != s: 
        v.detach()
      v = nil
    # Update View
    self.view = v
    s.parent.send(wsLayout)
    self.update()

  # -- Section Constructors --
  proc createSection =
    let 
      button = button(iconFold0, self.cbFold)
      combo = combobox(self.model).clear()
    # Set Attributes
    self.button = button
    self.combo = combo
    # Create Section Layout
    self.section =
      vertical().child:
        min: horizontal().child:
          min: button.clear()
          combo

  new cxbrushsection(menu: UXMenu):
    let model = combomodel(menu)
    model.onchange = result.cbChange
    result.model = model
    # Create Section
    result.createSection()

  new cxbrushsection():
    discard

# ---------------------
# Brush Section Simpler
# ---------------------

widget UXButtonCover:
  new uxbuttoncover(w: GUIWidget, cb: GUICallback):
    result.add button("", cb).clear()
    result.add w

  method update =
    let 
      m = addr self.metrics
      m0 = addr self.first.metrics
    # Inherit First Min Size
    m.minW = m0.minW
    m.minH = m0.minH

  method layout =
    let
      m = addr self.metrics
      m0 = addr self.first.metrics
      m1 = addr self.last.metrics
    # Locate Both First and Last
    m0.w = m.w; m0.h = m.h
    m1.w = m.w; m1.h = m.h

proc cxbrushsection*(label: string, w: GUIWidget): CXBrushSection =
  result = cxbrushsection()
  let
    cb = result.cbFold
    button = button(iconFold0, cb)
  # Create Header
  let header =
    horizontal().child:
      min: button.clear()
      label(label, hoLeft, veMiddle)
  # Create Section Template
  result.button = button
  result.section =
    vertical().child:
      min: uxbuttoncover(header, cb)
  # Register Unique Widget
  result.register(w)

# Export Menu
export menu, combo
