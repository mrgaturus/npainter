import nogui/ux/prelude
import ../../state/layers
# Import Layer Item
import item

# -----------------
# Layer List Layout
# -----------------

widget UXLayerList:
  attributes:
    {.cursor.}:
      layers: CXLayers
    # Previous Childrens
    stack: GUIWidget

  new layerlist(layers: CXLayers):
    result.kind = wkLayout
    result.layers = layers

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

  # -----------------
  # Useful Methods XD
  # -----------------

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
