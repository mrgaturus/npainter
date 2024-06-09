# TODO: client side decoration
# TODO: syncronize min size with native handle
import nogui/ux/layouts/base
import nogui/ux/prelude

# -----------------------
# Window Panel Background
# -----------------------

widget UXMainBG of UXLayoutCell:
  new mainbg(w: GUIWidget):
    result.cell0(w)

  method draw(ctx: ptr CTXRender) =
    ctx.color getApp().colors.panel
    ctx.fill rect(self.rect)

# -----------------------
# Window Frame Definition
# -----------------------

widget UXMainFrame:
  attributes: {.public, cursor.}:
    [title, body]: GUIWidget

  new mainframe(title, body: GUIWidget):
    result.add title
    result.add body
    # Register Title and Body
    result.title = title
    result.body = body

  method draw(ctx: ptr CTXRender) =
    ctx.color getApp().colors.panel
    ctx.fill rect(self.title.rect)

  method event(state: ptr GUIState) =
    # XXX: hacky way to forward event
    if state.kind in {evKeyDown, evKeyUp}:
      let body {.cursor.} = self.body
      body.vtable.event(body, state)

  method layout =
    let
      m = addr self.metrics
      # Main Frame Metrics
      m0 = addr self.title.metrics
      m1 = addr self.body.metrics
      # Content Size
      w = m.w
      h0 = m0.minH
      h1 = m.h - h0
    # Arrange Title
    m0.x = 0; m0.y = 0
    m0.w = w; m0.h = h0
    # Arrange Content
    m1.x = 0; m1.y = h0
    m1.w = w; m1.h = h1

widget UXMainBody:
  attributes: 
    {.public, cursor.}:
      tools: GUIWidget
      body: GUIWidget
  
  new mainbody(tools, body: GUIWidget):
    result.kind = wkLayout
    result.add tools
    result.add body
    # Register Tools and Body
    result.tools = tools
    result.body = body

  method draw(ctx: ptr CTXRender) =
    ctx.color getApp().colors.panel
    ctx.fill rect(self.tools.rect)

  method event(state: ptr GUIState) =
    # XXX: hacky way to forward event
    if state.kind in {evKeyDown, evKeyUp}:
      let body {.cursor.} = self.body
      body.vtable.event(body, state)

  method layout =
    let
      m = addr self.metrics
      # Main Frame Metrics
      m0 = addr self.tools.metrics
      m1 = addr self.body.metrics
      # Content Size
      h = m.h
      w0 = m0.minW
      w1 = m.w - w0
    # Arrange Title
    m0.x = 0; m0.y = 0
    m0.w = w0; m0.h = h
    # Arrange Content
    m1.x = w0; m1.y = 0
    m1.w = w1; m1.h = h
