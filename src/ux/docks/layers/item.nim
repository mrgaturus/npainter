from nogui/builder import child
import nogui/pack
# Import Widget Creation
import nogui/ux/prelude
import nogui/ux/layouts/[box, level, misc]
import ../../state/layers

# -------------------
# Layer Nesting Level
# -------------------

widget UXLayerLevel:
  attributes:
    layer: NLayer
    {.cursor.}:
      helper: GUIWidget

  new layerlevel(layer: NLayer, helper: GUIWidget):
    result.layer = layer
    result.helper = helper

  method update =
    let
      layer = self.layer
      help {.cursor.} = self.helper
      m = addr self.metrics
      m0 = addr help.metrics
    # Layer Nesting Level
    var l = int16(layer.level) - 1
    if lpClipping in layer.props.flags:
      inc(l)
    # Calculate Level Width
    help.vtable.update(help)
    m.minW = m0.minW * l

  method draw(ctx: ptr CTXRender) =
    let
      layer = self.layer
      w = float32(self.helper.rect.w)
    var r = rect(self.rect)
    # Draw Layer Clipping Mark
    r.x0 = r.x1 - w
    r.x1 = r.x0 + w * 0.5
    if lpClipping in layer.props.flags:
      ctx.color getApp().colors.text
      ctx.fill(r)

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

# --------------------
# Layer Widget Buttons
# --------------------

icons "dock/layers", 16:
  clipping *= "clipping.svg"
  alpha *= "alpha.svg"
  lock *= "lock.svg"
  wand *= "wand.svg"
  # Layer Properties Button
  hidden := "hidden.svg"
  visible := "visible.svg"
  props := "props.svg"

proc metrics0(self: GUIWidget, icon: CTXIconID) =
  let
    app = getApp()
    m = addr self.metrics
    # Icon Metrics
    m0 = icon(app.atlas, uint16 icon)
    pad = app.space.pad
  # Padded Icon Metrics
  m.minW = m0.w + pad
  m.minH = m0.h + pad
  # Store Icon Metrics
  m.maxW = m0.w
  m.maxH = m0.h

widget UXLayerVisible:
  attributes:
    icon: CTXIconID
    layer: NLayer
    # Toggle Callback
    cb: GUICallback

  new layervisible(layer: NLayer):
    result.flags = {wMouse}
    result.layer = layer

  method update =
    var icon = iconVisible
    let flags = self.layer.props.flags
    # Decide Which Icon
    if lpVisible notin flags:
      icon = iconHidden
    elif lpProtectAlpha in flags:
      icon = iconAlpha
    # Calculate Icon Metrics
    self.metrics0(icon)
    self.icon = icon

  method event(state: ptr GUIState) =
    if state.kind == evCursorRelease and self.test(wHover):
      send(self.cb)

  method draw(ctx: ptr CTXRender) =
    let
      m = addr self.metrics
      r = addr self.rect
      x = r.x + (r.w - m.maxW) shr 1
      y = r.y + (r.h - m.maxH) shr 1
    # Draw Visible Icon
    ctx.color getApp().colors.text
    ctx.icon(self.icon, x, y)

widget UXLayerProps:
  attributes:
    icon: CTXIconID
    layer: NLayer
    # Props Callback
    cb: GUICallback

  new layerprops(layer: NLayer):
    result.flags = {wMouse}
    result.layer = layer

  method update =
    let flags = self.layer.props.flags
    # Decide Which Icon
    var icon = iconProps
    if lpLock in flags:
      icon = iconLock
    # Calculate Icon Metrics
    self.metrics0(icon)
    self.icon = icon

  method event(state: ptr GUIState) =
    if state.kind == evCursorRelease and self.test(wHover):
      send(self.cb)

  method draw(ctx: ptr CTXRender) =
    let
      m = addr self.metrics
      r = addr self.rect
    var
      x = r.x + (r.w - m.maxW) shr 1
      y = r.y + (r.h - m.maxH) shr 1
    # Draw Properties Icon
    ctx.color getApp().colors.text
    ctx.icon(self.icon, x, y)
    # Draw Wand Target Icon
    if lpTarget in self.layer.props.flags:
      ctx.icon(iconWand, x - r.w, y)

# ------------------------
# Layer Widget Composition
# ------------------------

widget UXLayerItem:
  attributes: {.cursor.}:
    layers: CXLayers
    layer: NLayer
    # Layer Item Buttons
    btnShow: UXLayerVisible
    btnProps: UXLayerProps
    # Layer Item Content
    content: GUIWidget
    thumb: UXLayerThumb

  callback cbVisible:
    let props = addr self.layer.props
    var flags = props.flags
    # Toggle Visiblity
    if lpVisible in flags:
      flags.excl(lpVisible)
    else: flags.incl(lpVisible)
    # Replace Flags
    props.flags = flags
    # Relayout Layer
    self.send(wsLayout)
    send(self.layers.cbRender)

  callback cbProps:
    self.send(wsLayout)
    send(self.layers.cbRender)

  new layeritem(layers: CXLayers, layer: NLayer):
    let
      thumb = layerthumb()
      btnShow = layervisible(layer)
      btnProps = layerprops(layer)
    # Store Layer Attributes
    result.flags = {wMouse}
    result.layers = layers
    result.layer = layer
    # Bind Widget to Layer User
    layer.user = cast[NLayerUser](result)
    # Create Layer Content
    let content =
      horizontal().child:
        # Showing Button
        min: level().child:
          layerlevel(layer, btnShow)
          btnShow
        # Widget Info
        margin():
          horizontal().child:
            min: thumb
            layertext()
    # Button Callbacks
    btnShow.cb = result.cbVisible
    btnProps.cb = result.cbProps
    # Configure Content
    result.add content
    result.add btnProps
    # Store Layer Widgets
    result.btnShow = btnShow
    result.btnProps = btnProps
    result.content = content
    result.thumb = thumb

  method update =
    let
      l = addr self.content.metrics
      p = addr self.btnProps.metrics
      m = addr self.metrics
    # Calculate Accmulated Size
    m.minW = l.minW + p.minW
    m.minH = max(l.minH, p.minH)

  method layout =
    let
      l = addr self.content.metrics
      p = addr self.btnProps.metrics
      m = addr self.metrics
    # Locate Layering
    l.x = 0
    l.y = 0
    l.w = m.w
    l.h = m.minH
    # Locate Properties Button
    p.y = 0
    p.x = m.w - p.minW
    p.w = p.minW
    p.h = m.minH

  method event(state: ptr GUIState) =
    let
      btnShow {.cursor.} = self.btnShow
      btnProps {.cursor.} = self.btnProps
      # Cursor Position
      x = state.mx
      y = state.my
    # Redirect Event to Some Button
    if btnShow.pointOnArea(x, y):
      btnShow.send(wsRedirect)
    elif btnProps.pointOnArea(x, y):
      btnProps.send(wsRedirect)
    # Change Layer when Clicked
    elif state.kind == evCursorClick:
      self.layers.select(self.layer)

  method draw(ctx: ptr CTXRender) =
    let
      layer = self.layer
      ox = self.btnShow.rect.x
    # Adjust Rect to Button Position
    var r = self.rect
    r.w -= ox - r.x
    r.x = ox
    # Draw Selected Rect
    if layer == self.layers.selected:
      ctx.color self.itemColor()
    else: ctx.color self.clearColor()
    ctx.fill rect(r)
