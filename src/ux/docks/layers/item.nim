from nogui/builder import child
import nogui/pack
# Import Widget Creation
import nogui/ux/prelude
import nogui/ux/widgets/button
import nogui/ux/layouts/[box, level, misc]
import ../../state/layers

# -------------------
# Layer Nesting Level
# -------------------

widget UXLayerLevel:
  attributes:
    level: & int32
    {.cursor.}:
      helper: GUIWidget

  new layerlevel(level: & int32, helper: GUIWidget):
    result.level = level
    result.helper = helper

  method update =
    let 
      w = self.helper
      m = addr self.metrics
      me = addr w.metrics
      # Layer Nesting Level
      l = int16 self.level.peek[]
    # Calculate Level Width
    w.vtable.update(w)
    m.minW = me.minW * l

# ----------------------
# Layer Thumbnail & Text
# ----------------------

widget UXLayerThumb:
  attributes:
    # This is a proof of concept
    size: & int32

  new layerthumb():
    result.flags = {wMouse}

  method update =
    let
      # TODO: allow calculate scaling from app DPI
      s = int16 32 #int16 self.size.peek[]
      m = addr self.metrics
    # Thumbnail Min Size
    m.minW = s
    m.minH = s

  method draw(ctx: ptr CTXRender) =
    ctx.color 0xFFFFFFFF'u32
    ctx.fill rect(self.rect)

widget UXLayerText:
  new layertext():
    discard

  method update =
    let h = getApp().font.height
    self.metrics.minH = h * 2

  method draw(ctx: ptr CTXRender) =
    let
      app = getApp()
      r = addr self.rect
      # Text Coordinates
      x = r.x
      y = r.y - app.font.desc
      # App Metrics & Colors
      h = app.font.height
      col = app.colors.text
    # Draw Layer Info
    ctx.color(col)
    ctx.text(x, y, "Layer 1")
    ctx.color(col and 0x7FFFFFFF)
    ctx.text(x, y + h, "Normal")

# ------------------------
# Layer Widget Composition
# ------------------------

icons "dock/layers", 16:
  visible := "visible.svg"
  props := "props.svg"

widget UXLayerItem:
  attributes:
    # Button Manipulation
    [btnShow, btnProps]: UXButtonCB
    # XXX: proof of concept linking
    {.cursor.}:
      thumb: UXLayerThumb
      layers: CXLayers
      layer: NLayer
    # TODO: link to a layer controller
    {.public.}:
      level: @ int32

  callback cbVisible:
    discard

  callback cbProps:
    discard

  new layeritem(layers: CXLayers, layer: NLayer, lvl: int32):
    let
      thumb = layerthumb()
      btnShow = button(iconVisible, result.cbVisible)
      btnProps = button(iconProps, result.cbProps)
    # Store Layer Attributes
    result.flags = {wMouse}
    result.layers = layers
    result.layer = layer
    # Create Layer Layout
    result.add:
      horizontal().child:
        # Showing Button
        min: level().child:
          layerlevel(result.level, btnShow)
          btnShow.clear()
        # Widget Info
        margin(4):
          horizontal().child:
            min: thumb
            layertext()
    # Button Props
    result.add btnProps.clear()
    # Store Buttons
    result.btnShow = btnShow
    result.btnProps = btnProps
    result.level = value(lvl)
    # XXX: this is a proof of concept
    result.thumb = thumb

  method update =
    let
      l = addr self.first.metrics
      p = addr self.last.metrics
      m = addr self.metrics
    # Calculate Accmulated Size
    m.minW = l.minW + p.minW
    m.minH = max(l.minH, p.minH)

  method layout =
    let
      l = addr self.first.metrics
      p = addr self.last.metrics
      m = addr self.metrics
    # Locate Layering
    l.x = 0
    l.y = 0
    l.w = m.w - p.minW
    l.h = m.minH
    # Locate Properties Button
    p.y = 0
    p.x = m.w - p.minW
    p.w = p.minW
    p.h = m.minH

  method event(state: ptr GUIState) =
    # Change Layer when Clicked
    if state.kind == evCursorClick:
      self.layers.select(self.layer)

  method draw(ctx: ptr CTXRender) =
    var r = self.rect
    let r0 = addr self.btnShow.rect
    # Adjust Rect to Button Position
    r.x = r0.x
    # Draw Rect
    if self.layer == self.layers.selected:
      ctx.color self.itemColor()
    else: ctx.color self.clearColor()
    ctx.fill rect(r)
