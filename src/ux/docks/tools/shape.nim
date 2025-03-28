import nogui/ux/prelude
import nogui/builder
# Import A Dock
import nogui/pack
import nogui/ux/widgets/
  [label, slider, check, radio, combo, menu]
import nogui/ux/layouts/[box, form, misc]
import nogui/ux/containers/[dock, scroll]
# Import Shape Data
import ../../state/shape
import ../../state/layers
import ../layers/item

icons "tools", 16:
  lasso := "lasso.svg"
  select := "select.svg"
  shapes := "shapes.svg"

icons "dock/shape", 16:
  maskBlit := "mask_blit.svg"
  maskUnion := "mask_union.svg"
  maskExclude := "mask_exclude.svg"
  maskIntersect := "mask_intersect.svg"
  ruleNonZero := "rule_nonzero.svg"
  ruleOddEven := "rule_oddeven.svg"
  modeErase := "mode_erase.svg"
  # Polygon Shape Mode
  shapeRectangle := "shape_rectangle.svg"
  shapeCircle := "shape_circle.svg"
  shapeConvex := "shape_convex.svg"
  shapeStar := "shape_star.svg"
  shapeFreeform := "shape_freeform.svg"
  shapeLasso := "shape_lasso.svg"
  # Polygon Shape Pivot
  pivotCenter := "pivot_center.svg"
  pivotSquare := "pivot_square.svg"
  pivotRotate := "pivot_rotate.svg"

proc separator(): UXLabel =
  label("", hoLeft, veMiddle)

proc comboitem(mode: NBlendMode): UXComboItem =
  comboitem($blendname[mode], ord mode)

# --------------------
# Selection Lasso Dock
# --------------------

controller CXLassoDock:
  attributes:
    shape: CXShape
    rule: ComboModel
    # Usable Dock
    {.public.}:
      dock: UXDockContent

  proc createWidget: GUIWidget =
    let shape {.cursor.} = self.shape
    let mode = cast[& int32](addr shape.mode)
    # Create Layout Form
    margin(4): form().child:
      field("Rule"): combobox(self.rule)
      separator()
      field("Mode"):
        horizontal().child:
          button(iconMaskBlit, mode, ord ckmaskBlit)
          button(iconMaskUnion, mode, ord ckmaskUnion)
          button(iconMaskExclude, mode, ord ckmaskExclude)
          button(iconMaskIntersect, mode, ord ckmaskIntersect)
      field("Opacity"): slider(shape.opacity)
      field(): checkbox("Anti-Aliasing", shape.antialiasing)

  proc createDock() =
    self.rule = combomodel(): menu("lasso#rule").child:
      comboitem("Non Zero", iconRuleNonZero, ord ckruleNonZero)
      comboitem("Odd Even", iconRuleOddEven, ord ckruleOddEven)
    # Create Dock Widget
    let w = scrollview self.createWidget()
    let dock = dockcontent("Lasso Tool", iconLasso, w)
    self.dock = dock

  new cxlassodock(shape: CXShape):
    result.shape = shape
    result.createDock()

# --------------------
# Selection Shape Dock
# --------------------

controller CXSelectionDock:
  attributes:
    shape: CXShape
    rule: ComboModel
    poly: ComboModel
    # Usable Dock
    {.public.}:
      dock: UXDockContent

  proc createWidget: GUIWidget =
    let shape {.cursor.} = self.shape
    let mode = cast[& int32](addr shape.mode)
    # Create Layout Form
    margin(4): form().child:
      field("Rule"): combobox(self.rule)
      field("Shape"): combobox(self.poly)
      separator()
      field(): horizontal().child:
        button("1:1 Ratio", iconPivotSquare, shape.square)
        min: button(iconPivotCenter, shape.center)
        min: button(iconPivotRotate, shape.rotate)
      field("Sides"): slider(shape.sides)
      field("Inset"): dual0float(shape.inset, fmf2"%.2f")
      field("Round"): slider(shape.round)
      field(): horizontal().child:
        radio("Bezier", ord ckcurveBezier, shape.curve)
        radio("Catmull", ord ckcurveCatmull, shape.curve)
      separator()
      field("Mode"):
        horizontal().child:
          button(iconMaskBlit, mode, ord ckmaskBlit)
          button(iconMaskUnion, mode, ord ckmaskUnion)
          button(iconMaskExclude, mode, ord ckmaskExclude)
          button(iconMaskIntersect, mode, ord ckmaskIntersect)
      field("Opacity"): slider(shape.opacity)
      field(): checkbox("Anti-Aliasing", shape.antialiasing)

  proc createDock() =
    self.poly = combomodel(): menu("selection#poly").child:
      comboitem("Rectangle", iconShapeRectangle, ord ckshapeRectangle)
      comboitem("Circle", iconShapeCircle, ord ckshapeCircle)
      comboitem("Convex", iconShapeConvex, ord ckshapeConvex)
      comboitem("Star", iconShapeStar, ord ckshapeStar)
      menuseparator()
      comboitem("Freeform", iconShapeFreeform, ord ckshapeFreeform)
      comboitem("Lasso", iconShapeLasso, ord ckshapeLasso)
    self.rule = combomodel(): menu("selection#rule").child:
      comboitem("Non Zero", iconRuleNonZero, ord ckruleNonZero)
      comboitem("Odd Even", iconRuleOddEven, ord ckruleOddEven)
    # Create Dock Widget
    let w = scrollview self.createWidget()
    let dock = dockcontent("Selection Tool", iconSelect, w)
    self.dock = dock

  new cxselectiondock(shape: CXShape):
    result.shape = shape
    result.createDock()

# ----------------
# Blend Shape Dock
# ----------------

controller CXShapeDock:
  attributes:
    shape: CXShape
    blend: ComboModel
    rule: ComboModel
    poly: ComboModel
    # Usable Dock
    {.public.}:
      dock: UXDockContent

  callback cbUpdateModel:
    let shape {.cursor.} = self.shape
    shape.rule.peek[] = cast[CKPolygonRule](self.rule.selected.value)
    shape.poly.peek[] = cast[CKPolygonShape](self.poly.selected.value)
    shape.blend.peek[] = cast[NBlendMode](self.blend.selected.value)

  proc createWidget: GUIWidget =
    let shape {.cursor.} = self.shape
    let mode = cast[& int32](addr shape.mode)
    # Create Layout Form
    margin(4): form().child:
      field("Rule"): combobox(self.rule)
      field("Shape"): combobox(self.poly)
      separator()
      field(): horizontal().child:
        button("1:1 Ratio", iconPivotSquare, shape.square)
        min: button(iconPivotCenter, shape.center)
        min: button(iconPivotRotate, shape.rotate)
      field("Sides"): slider(shape.sides)
      field("Inset"): dual0float(shape.inset, fmf2"%.2f")
      field("Round"): slider(shape.round)
      field(): horizontal().child:
        radio("Bezier", ord ckcurveBezier, shape.curve)
        radio("Catmull", ord ckcurveCatmull, shape.curve)
      separator()
      field("Mode"):
        horizontal().child:
          button("Blend", iconMaskBlit, mode, ord ckmaskBlit)
          button("Erase", iconModeErase, mode, ord ckmaskExclude)
      field("Blend"): combobox(self.blend)
      field("Opacity"): slider(shape.opacity)
      field(): checkbox("Anti-Aliasing", shape.antialiasing)

  proc createDock() =
    self.blend = combomodel(): menu("shapes#mode").child:
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
    self.poly = combomodel(): menu("shapes#poly").child:
      comboitem("Rectangle", iconShapeRectangle, ord ckshapeRectangle)
      comboitem("Circle", iconShapeCircle, ord ckshapeCircle)
      comboitem("Convex", iconShapeConvex, ord ckshapeConvex)
      comboitem("Star", iconShapeStar, ord ckshapeStar)
      menuseparator()
      comboitem("Freeform", iconShapeFreeform, ord ckshapeFreeform)
      comboitem("Lasso", iconShapeLasso, ord ckshapeLasso)
    self.rule = combomodel(): menu("shapes#rule").child:
      comboitem("Non Zero", iconRuleNonZero, ord ckruleNonZero)
      comboitem("Odd Even", iconRuleOddEven, ord ckruleOddEven)
    # Create Dock Widget
    self.poly.onchange = self.cbUpdateModel
    self.rule.onchange = self.cbUpdateModel
    self.blend.onchange = self.cbUpdateModel
    let w = scrollview self.createWidget()
    let dock = dockcontent("Shape Tool", iconShapes, w)
    self.dock = dock

  new cxshapedock(shape: CXShape):
    result.shape = shape
    result.createDock()
