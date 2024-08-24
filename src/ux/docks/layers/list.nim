from math import sqrt
# Import nogui Widgets
from nogui/core/tree import inside
import nogui/ux/containers/scroll
import nogui/ux/values/scroller
import nogui/ux/prelude
import ../../state/layers
# Import Layer Item
import item

# ----------------
# Layer List Sides
# ----------------

proc orderScroll(state: ptr GUIState, rect: GUIRect): float32 =
  let
    h = rect.h
    y = state.my - rect.y
  # Calculate Scroll Direction
  if y < 0:
    result = float32(0 - y)
    result = -sqrt(result)
  elif y > h:
    result = float32(y - h)
    result = sqrt(result)
  # Twice Scroll Direction
  result += result

proc orderSide(state: ptr GUIState, layer: NLayer): NLayerAttach =
  const modes = [ltAttachPrev, ltAttachFolder, ltAttachFolder, ltAttachNext]
  let user {.cursor.} = cast[GUIWidget](layer.user)
  # Check Layer Kind
  let
    kind = layer.kind
    rect = user.rect
    y = state.my - rect.y
  # Check Layer Sides
  if kind != lkFolder:
    let idx = clamp(y * 2 div rect.h, 0, 1)
    result = modes[idx * 3]
  # Check Folder Sides
  elif kind == lkFolder:
    let
      check = int32(lpFolded notin layer.props.flags)
      idx = clamp(y * 4 div rect.h, 0, 3 - check)
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

  callback cbScroll:
    let
      state = getApp().state
      delta = state.orderScroll(self.rect)
      # Move Delta Position
      o = react(self.scroll.oy)
      pos = o[].position + delta
    # Update Delta Position
    o[].position(pos)
    # Renew Scrolling Manipulation Timer
    if self.flags * {wGrab, wHover} == {wGrab}:
      timeout(self.cbScroll, 0)

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
      layer0 = self.layer
      list {.cursor.} = self.list
      check = self.pointOnArea(x, y)
    # Find Current Widget
    privateAccess(UXLayerItem)
    var found {.cursor.} = list.inside(x, y)
    # Find Layer Ordering Side
    if found == list:
      found = list.last
    if check and not isNil(found):
      let
        layer = cast[UXLayerItem](found).layer
        mode = state.orderSide(layer)
      # Check if is Valid Attachment
      if layer0.attachCheck(layer, mode):
        self.target = layer
        self.mode = mode
        return
    # Fallback Values
    self.target = layer0
    self.mode = ltAttachUnknown

  proc commit() =
    var order = NLayerOrder(
      layer: self.layer,
      target: self.target,
      mode: self.mode
    )
    # Commit Layer Ordering
    if order.mode != ltAttachUnknown:
      force(self.layers.cbOrderLayer, addr order)
    # Scrolling Manipulation Timer
    timestop(self.cbScroll)

  method handle(reason: GUIHandle) =
    case reason
    of outGrab:
      self.send(wsClose)
      self.commit()
    # Scroll if not Hovered
    of outHover, inFrame:
      if not self.test(wHover):
        timeout(self.cbScroll, 0)
    else: discard

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
