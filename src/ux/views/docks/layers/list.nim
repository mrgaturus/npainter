import nogui/ux/prelude
import ../../state/layers
import item
# XXX: this is a proof of concept

# -----------------
# Layer List Layout
# -----------------

widget UXLayerList:
  attributes: {.cursor.}:
    layers: CXLayers

  new layerlist(layers: CXLayers):
    result.layers = layers

  proc clear() =
    # XXX: this is awful
    # ARC / ORC torture XD
    for w in forward(self.first):
      w.parent = nil
    self.first = nil
    self.last = nil

  proc reloadProofLayerList* =
    let
      root = self.layers.root
      layers = self.layers
    self.clear()
    # Create Layer items
    var layer = root.first
    while not isNil(layer):
      self.add layeritem(layers, layer, 0)
      layer = layer.next
    # Set Layer Dirty
    self.set(wDirty)
    echo "Reloaded"

  # -----------------
  # Useful Methods XD
  # -----------------

  method update =
    var h: int16
    for w in forward(self.first):
      h += w.metrics.minH
    # Change Min Size
    self.metrics.minH = h

  method layout =
    var y: int16
    let w = self.metrics.w
    # Arrange Each Layer
    for widget in forward(self.first):
      let m = addr widget.metrics
      m.y = y
      m.x = 0
      m.w = w
      m.h = m.minH
      # Next Y
      y += m.minH
