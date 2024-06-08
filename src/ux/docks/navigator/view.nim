import nogui/ux/prelude

# -----------------
# Dummy Canvas View
# -----------------

widget UXNavigatorView:
  new navigatorview():
    discard

  method draw(ctx: ptr CTXRender) =
    ctx.color getApp().colors.darker
    ctx.fill rect(self.rect)
