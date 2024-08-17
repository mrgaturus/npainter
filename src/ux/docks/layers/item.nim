from nogui/core/tree import inside
from nogui/builder import child
import nogui/[pack, format]
# Import Widget Creation
import nogui/ux/prelude
import nogui/ux/layouts/[box, level, misc]
import ../../state/layers

icons "dock/layers", 16:
  clipping *= "clipping.svg"
  alpha *= "alpha.svg"
  lock *= "lock.svg"
  wand *= "wand.svg"
  # Layer Properties Button
  hidden := "hidden.svg"
  visible := "visible.svg"
  props := "props.svg"

icons "dock/layers", 32:
  folder0 := "folder0.svg"
  folder1 := "folder1.svg"

const blendname*: array[NBlendMode, cstring] = [
  bmNormal: "Normal",
  bmPassthrough: "Passthrough",
  # -- Darker --
  bmMultiply: "Multiply",
  bmDarken: "Darken",
  bmColorBurn: "Color Burn",
  bmLinearBurn: "Linear Burn",
  bmDarkerColor: "Darker Color",
  # -- Light --
  bmScreen: "Screen",
  bmLighten: "Lighten",
  bmColorDodge: "Color Dodge",
  bmLinearDodge: "Linear Dodge",
  bmLighterColor: "Lighter Color",
  # -- Contrast --
  bmOverlay: "Overlay",
  bmSoftLight: "Soft Light",
  bmHardLight: "Hard Light",
  bmVividLight: "Vivid Light",
  bmLinearLight: "Linear Light",
  bmPinLight: "Pin Light",
  bmHardMix: "Hard Mix",
  # -- Compare --
  bmDifference: "Difference",
  bmExclusion: "Exclusion",
  bmSubstract: "Substract",
  bmDivide: "Divide",
  # -- Composite --
  bmHue: "Hue",
  bmSaturation: "Saturation",
  bmColor: "Color",
  bmLuminosity: "Luminosity"
]

# -------------------
# Layer Nesting Level
# -------------------

widget UXLayerLevel:
  attributes: {.cursor.}:
    layer: ptr NLayer
    helper: GUIWidget
    # Layer Level Info
    level: NLayerLevel

  new layerlevel(layer: ptr NLayer, helper: GUIWidget):
    result.layer = layer
    result.helper = helper

  method update =
    let
      layer = self.layer[]
      help {.cursor.} = self.helper
      m = addr self.metrics
      m0 = addr help.metrics
      # Calculate Layer Level
      level = layer.level()
    # Layer Nesting Level
    var l = int16(level.depth) - 1
    if lpClipping in layer.props.flags:
      inc(l)
    # Calculate Level Width
    help.vtable.update(help)
    m.minW = m0.minW * l
    # Store Layer Level
    self.level = level

  method draw(ctx: ptr CTXRender) =
    let
      layer = self.layer[]
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
  attributes: {.cursor.}:
    layer: ptr NLayer

  new layerthumb(layer: ptr NLayer):
    result.flags = {wMouse}
    result.layer = layer

  method update =
    let
      # XXX: this is proof of concept
      s = int16 32
      m = addr self.metrics
    # Thumbnail Min Size
    m.minW = s
    m.minH = s

  method draw(ctx: ptr CTXRender) =
    let
      layer = self.layer[]
      r = self.rect
    # TODO: draw thumbnail texture here
    ctx.color 0xFFFFFFFF'u32
    if layer.kind != lkFolder:
      ctx.fill rect(r)
    # Draw Folder Collapsed
    elif lpFolded notin layer.props.flags:
      ctx.icon(iconFolder0, r.x, r.y)
    else: ctx.icon(iconFolder1, r.x, r.y)

widget UXLayerText:
  attributes:
    {.cursor.}:
      layer: ptr NLayer
    # Blending Label
    mode: NBlendMode
    blend: string

  new layertext(layer: ptr NLayer):
    result.layer = layer

  method update =
    let h = getApp().font.height
    self.metrics.minH = h * 2
    # Blending Mode Label
    let props = addr self.layer.props
    if len(self.blend) == 0 or self.mode != props.mode:
      self.blend = $blendname[props.mode]
    # Blending Mode Cache
    self.mode = props.mode

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
      # Layer Opacity
      props = addr self.layer.props
      opacity = int32(props.opacity * 100.0)
    # Draw Layer Name
    ctx.color(col)
    ctx.text(x, y, props.label)
    # Draw Layer Blend
    ctx.color(col and 0x7FFFFFFF)
    if opacity == 100:
      ctx.text(x, y + h, self.blend)
      return
    # Draw Layer Opacity
    let blend = cstring(self.blend)
    app.fmt.format("%s %d%%", blend, opacity)
    ctx.text(x, y + h, app.fmt.peek)

# --------------------
# Layer Widget Buttons
# --------------------

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
    layer: ptr NLayer
    cb: GUICallback
    # Visible Status
    icon: CTXIconID
    [mask, hidden]: bool

  new layervisible(layer: ptr NLayer):
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
    if state.kind == evCursorClick:
      send(self.cb)
    # Propagate Status Change
    elif {wHover, wGrab} * self.flags == {wGrab}:
      let user {.cursor.} = cast[GUIWidget](self.layer.user)
      let item {.cursor.} = inside(user.parent, user.rect.x, state.my)
      # HACK: Ensure UXLayerProps is UXLayerItem.last
      if item != user and item.vtable == user.vtable:
        let layer = cast[UXLayerVisible](item.last).layer
        if self.mask != (lpVisible in layer.props.flags):
          return
        # Prepare Item Callback
        privateAccess(GUICallback)
        var cb = self.cb
        # Hook Callback to Selected
        cb.sender = cast[pointer](item)
        cb.send()

  method handle(reason: GUIHandle) =
    if reason == inGrab:
      let flags = self.layer.props.flags
      self.mask = lpVisible in flags

  method draw(ctx: ptr CTXRender) =
    let
      m = addr self.metrics
      r = addr self.rect
      x = r.x + (r.w - m.maxW) shr 1
      y = r.y + (r.h - m.maxH) shr 1
    # Check Level Visibility
    var color = getApp().colors.text
    if self.hidden:
      color = color and 0x7FFFFFFF'u32
    # Draw Visible Icon
    ctx.color color
    ctx.icon(self.icon, x, y)

widget UXLayerProps:
  attributes:
    layer: ptr NLayer
    cb: GUICallback
    # Props Status
    icon: CTXIconID

  new layerprops(layer: ptr NLayer):
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
      flags = self.layer.props.flags
      selected = self.parent.test(wHold) or self.test(wHover)
      # Widget Metrics
      m = addr self.metrics
      r = addr self.rect
    var
      x = r.x + (r.w - m.maxW) shr 1
      y = r.y + (r.h - m.maxH) shr 1
    # Draw Properties Icon
    ctx.color getApp().colors.text
    if selected or lpLock in flags:
      ctx.icon(self.icon, x, y)
    else: x += r.w
    # Draw Wand Target Icon
    if lpTarget in flags:
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
    laLevel: UXLayerLevel
    laThumb: UXLayerThumb
    laText: UXLayerText
    # Layer Item Layout
    content: GUIWidget

  proc useLayer*(layer: NLayer) =
    layer.user = cast[NLayerUser](self)
    self.layer = layer

  proc rectLayer*: GUIRect =
    result = self.rect
    let ox = self.btnShow.rect.x
    # Adjust Rect to Button Position
    result.w -= ox - result.x
    result.x = ox

  proc toggle(flag: NLayerFlag) =
    let
      layer = self.layer
      props = addr layer.props
    var flags = props.flags
    # Toggle Visiblity
    if flag in flags:
      flags.excl(flag)
    else: flags.incl(flag)
    # Replace Flags
    props.flags = flags

  callback cbVisible:
    let layer = self.layer
    self.toggle(lpVisible)
    # Check Layer as Folder
    var w {.cursor.} = cast[GUIWidget](self)
    if layer.kind == lkFolder:
      w = w.parent
    # Relayout Widget
    w.send(wsLayout)
    send(self.layers.cbRender)

  callback cbProps:
    self.send(wsLayout)
    send(self.layers.cbRender)

  callback cbFold:
    self.toggle(lpFolded)
    self.parent.send(wsLayout)

  new layeritem(layers: CXLayers):
    let
      layer = addr result.layer
      # Layer Widget Buttons
      btnShow = layervisible(layer)
      btnProps = layerprops(layer)
      # Layer Widget Content
      laLevel = layerlevel(layer, btnShow)
      laThumb = layerthumb(layer)
      laText = layertext(layer)
    # Store Layer Attributes
    result.flags = {wMouse}
    result.layers = layers
    # Create Layer Content
    let content =
      horizontal().child:
        min: level().child:
          laLevel
          btnShow
        # Layer Information
        margin: horizontal().child:
          min: laThumb
          laText
    # Store Layer Buttons
    btnShow.cb = result.cbVisible
    btnProps.cb = result.cbProps
    result.btnShow = btnShow
    result.btnProps = btnProps
    # Store Layer Content
    result.laLevel = laLevel
    result.laThumb = laThumb
    result.laText = laText
    # Store Layer Layout
    result.add content
    result.add btnProps
    result.content = content

  method update =
    let
      l = addr self.content.metrics
      p = addr self.btnProps.metrics
      m = addr self.metrics
    # Calculate Accmulated Size
    m.minW = l.minW + p.minW
    m.minH = max(l.minH, p.minH)
    # Check Layer Selected
    let level = self.laLevel.level
    var flags = self.flags - {wHold, wHidden}
    if self.layer == self.layers.selected:
      flags.incl(wHold)
    # Check Level Folded/Hidden
    if level.folded: flags.incl(wHidden)
    self.btnShow.hidden = level.hidden
    # Check Layer Level
    self.flags = flags

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
    # Fold Folder if Thumbnail Clicked
    elif state.kind == evCursorRelease:
      if self.laThumb.pointOnArea(x, y):
        if self.layer.kind == lkFolder:
          send(self.cbFold)

  method handle(reason: GUIHandle) =
    if reason == outHover: # Start Reordering
      if wGrab in (self.flags - self.btnShow.flags):
        force(self.layers.onorder, addr self.layer)

  method draw(ctx: ptr CTXRender) =
    let r = self.rectLayer()
    # Draw Selected Rect
    let colors = addr getApp().colors
    if self.test(wHold):
      ctx.color colors.focus
      ctx.fill rect(r)
    elif self.test(wHover):
      ctx.color colors.item
      ctx.fill rect(r)
