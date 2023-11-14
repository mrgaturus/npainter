import nogui/ux/prelude

# -----------------
# Layer List Layout
# -----------------

widget UXLayerList:
  new layerlist():
    discard

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
