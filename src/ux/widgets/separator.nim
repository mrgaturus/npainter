import nogui/ux/prelude
# -------------------
# TODO: move to nogui
# -------------------

widget UXVSeparator:
  new vseparator():
    let
      metrics = addr getApp().font
      fontsize = metrics.size
      # Minimun Separator Size
      height = (metrics.height + fontsize) shr 1
    result.minimum(height, height)

  method draw(ctx: ptr CTXRender) =
    ctx.color getApp().colors.item and 0x7FFFFFFF
    var rect = rect(self.rect)
    # Locate Separator Line
    rect.x = (rect.x + rect.xw) * 0.5 - 1
    rect.xw = rect.x + 2
    # Create Simple Line
    ctx.fill rect
