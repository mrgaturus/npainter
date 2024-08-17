from nogui/core/tree import inside
import nogui/ux/containers/scroll
import nogui/ux/prelude
import ../../state/layers
# Import Layer Item
import item

# ----------------
# Layer List Sides
# ----------------

proc orderSide(state: ptr GUIState, layer: NLayer): NLayerAttach =
  const modes = [ltAttachPrev, ltAttachFolder, ltAttachNext]
  let user {.cursor.} = cast[GUIWidget](layer.user)
  # Check Layer Kind
  let
    kind = layer.kind
    rect = user.rect
    y = state.my - rect.y
  # Check Layer Sides
  if kind != lkFolder:
    let idx = clamp(y * 2 div rect.h, 0, 1)
    result = modes[idx shl 1]
  # Check Folder Sides
  elif kind == lkFolder:
    let idx = clamp(y * 3 div rect.h, 0, 2)
    result = modes[idx]

proc drawSide(ctx: ptr CTXRender, layer: NLayer, mode: NLayerAttach) =
  let
    app = getApp()
    border = float32(app.space.line)
    user {.cursor.} = cast[UXLayerItem](layer.user)
  # Prepare Fill Rect
  var r = user.rectLayer().rect
  ctx.color(app.colors.darker and 0x3FFFFFFF'u32) 
  ctx.fill(r)
  ctx.color(app.colors.text)
  # Fill Layer Outline
  case mode
  of ltAttachNext:
    r.y0 = r.y1 - border
    ctx.fill(r)
  of ltAttachPrev:
    r.y1 = r.y0 + border
    ctx.fill(r)
  of ltAttachFolder:
    ctx.line(r, border)
  else: discard

# ---------------------
# Layer List Reordering
# ---------------------

widget UXLayerOrder:
  attributes: {.cursor.}:
    layers: CXLayers
    # Layer List Widget
    list: GUIWidget
    scroll: UXScrollOffset
    # Layer Attach
    layer: NLayer
    target: NLayer
    mode: NLayerAttach

  callback cbOrder(data: NLayer):
    self.layer = data[]
    # Change Current Grab
    getWindow().send(wsUnHover)
    self.send(wsForward)
    self.send(wsOpen)

  new layerorder(layers: CXLayers, list: GUIWidget):
    result.kind = wkTooltip
    result.flags = {wMouse}
    # Layer Order List
    result.layers = layers
    result.list = list

  method layout =
    let scroll {.cursor.} = self.list.parent
    self.scroll = cast[UXScrollOffset](scroll)
    self.rect = scroll.rect
    # Ensure it's Actually a Scroll
    assert(scroll of UXScrollOffset)

  method event(state: ptr GUIState) =
    let
      x = state.mx
      y = state.my
      layer = self.layer
      user {.cursor.} = cast[GUIWidget](layer.user)
      list {.cursor.} = self.list
      # Avoid Finding Outside
      check = self.pointOnArea(x, y)
    # Find Current Widget
    privateAccess(UXLayerItem)
    var found {.cursor.} = list.inside(x, y)
    if check and found != list and found != user:
      let layer = cast[UXLayerItem](found).layer
      # Configure Layer Mode
      self.target = layer
      self.mode = state.orderSide(layer)
      return
    # Fallback Values
    self.target = self.layer
    self.mode = ltAttachUnknown

  method handle(reason: GUIHandle) =
    if reason == outGrab:
      self.send(wsClose)

  method draw(ctx: ptr CTXRender) =
    let user {.cursor.} = cast[UXLayerItem](self.layer.user)
    ctx.drawSide(self.target, self.mode)
    # Decide Layer Coloring
    var color: CTXColor
    if self.layer != self.target:
      color = getApp().colors.darker and 0x7FFFFFFF'u32
    # Fill Layer Expected
    ctx.color(color)
    ctx.fill(rect user.rectLayer)

# -----------------
# Layer List Layout
# -----------------

widget UXLayerList:
  attributes:
    {.cursor.}:
      layers: CXLayers
    # Previous Childrens
    order: UXLayerOrder
    stack: GUIWidget 

  new layerlist(layers: CXLayers):
    result.kind = wkLayout
    result.layers = layers
    # Create Layer Ordering Helper
    let order = layerorder(layers, result)
    layers.onorder = order.cbOrder
    result.order = order

  proc clear() =
    self.stack = self.first
    # Clear Layer List
    self.first = nil
    self.last = nil

  proc register(layer: NLayer) =
    var item = cast[UXLayerItem](self.stack)
    # Consume Layer Item From Stack
    if not isNil(item):
      self.stack = item.next
      # Clear Endpoints
      item.next = nil
      item.prev = nil
    # Create New Layer Item
    else: item = layeritem(self.layers)
    item.useLayer(layer)
    self.add(item)

  proc reload*() =
    let root = self.layers.root
    # Clear Layer List
    self.clear()
    # Create Layer List
    var layer = root.first
    while not isNil(layer):
      self.register(layer)
      # Enter/Leave Folder
      if layer.kind == lkFolder:
        if not isNil(layer.first):
          layer = layer.first
          continue
      while isNil(layer.next) and layer != root:
        layer = layer.folder
      # Next Layer
      layer = layer.next
    # Relayout Widget
    wasMoved(self.stack)
    self.send(wsLayout)

  method update =
    var h: int16
    for w in forward(self.first):
      if w.test(wHidden): continue
      h += w.metrics.minH
    # Update Minimun Size
    self.metrics.minH = h

  method layout =
    var y: int16
    let w = self.metrics.w
    # Arrange Each Layer
    for widget in forward(self.first):
      if widget.test(wHidden): continue
      # Locate Layer Item
      let m = addr widget.metrics
      m.y = y
      m.x = 0
      m.w = w
      m.h = m.minH
      # Step Layer Item
      y += m.minH
