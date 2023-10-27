from system/ansi_c import c_sprintf
import nogui/ux/prelude
from nogui/pack import icons
from nogui/values import toRGB
import nogui/ux/widgets/color/base
# Import Color Controller
import ../../color

# ---------------------
# Color Drawing Helpers
# ---------------------

proc clicked(self: GUIWidget, state: ptr GUIState): bool {.inline.} =
  state.kind == evCursorRelease and (self.flags and wHover) == wHover

icons "dock", 16:
  dockColor *= "color.svg"

# ----------------------
# Color Selected Widgets
# ----------------------

widget UXColorSelected:
  attributes:
    {.cursor.}: 
      color: CXColor
    # Selected Pointer
    target: ptr HSVColor

  new colorprimary(color: CXColor):
    result.color = color
    result.flags = wMouse
    # Select Primary Color
    result.target = addr color.color0

  new colorsecondary(color: CXColor):
    result.color = color
    result.flags = wMouse
    # Select Secondary Color
    result.target = addr color.color1

  method update =
    # TODO: scalable hardcoded
    self.minimum(32, 32)

  method event(state: ptr GUIState) =
    # TODO: advanced color dialog
    # Remove Transparent
    if self.clicked(state):
      let c = self.color
      # Set Selected or Remove Eraser
      if self.target != peek(c.color):
        c.swap()
      elif c.checkEraser():
        push(c.cbChange)

  proc color32: uint32 =
    let color = self.target[]
    color.toRGB.toPacked

  method draw(ctx: ptr CTXRender) =
    let
      c = self.color
      color = self.color32
      scheme = addr getApp().colors
      # Filling Rect
      r = rect(self.rect)
    # Fill Current Color
    ctx.color(color)
    ctx.fill(r)
    # Check Eraser
    # TODO: create a scale(px) for hardcoded
    if self.target == peek(c.color) and not c.checkEraser:
      ctx.color scheme.text
      ctx.line r, 2
    elif self.test(wHover):
      ctx.color scheme.focus
      ctx.line r, 2
    else: # Draw Outline
      ctx.color scheme.item
      ctx.line r, 1

# ------------------------
# Color Transparent Widget
# ------------------------

widget UXColorTransparent:
  attributes:
    {.cursor.}:
      color: CXColor

  new colortransparent(color: CXColor):
    result.color = color
    result.flags = wMouse

  method update =
    # TODO: scalable hardcoded
    self.minimum(32, 32)

  method event(state: ptr GUIState) =
    if self.clicked(state):
      self.color.setEraser(true)

  method draw(ctx: ptr CTXRender) =
    let 
      r0 = rect(self.rect)
      rx = (r0.xw - r0.x) * 0.25
      ry = (r0.yh - r0.y) * 0.25
      # Checkboard Colors
      c = addr getApp().colors
      cols = [c.item, c.panel]
    # Scale Rect by 4
    var r = r0
    r.xw = r.x + rx
    r.yh = r.y + ry
    # Split Rect Into 4 Parts
    for i in 0 ..< 4:
      # Reset X Position
      r.x = r0.x
      r.xw = r.x + rx
      for j in 0 ..< 4:
        # Fill Checkboard Color
        let idx = (i and 1) xor (j and 1)
        ctx.color cols[idx]
        ctx.fill r
        # Step X Position
        r.x = r.xw
        r.xw += rx
      # Step Y Position
      r.y = r.yh
      r.yh += ry
    # Fill if Selected
    # TODO: create a scale(px) for hardcoded
    if peek(self.color.eraser)[]:
      ctx.color c.text
      ctx.line r0, 2
    elif self.test(wHover):
      ctx.color c.focus
      ctx.line r0, 2
    else: # Draw Outline
      ctx.color c.item
      ctx.line r0, 1

# ----------------------
# Color Dock Widget Text
# ----------------------

widget UXColorText:
  attributes:
    {.cursor.}:
      color: CXColor
      # Text Buffer
      hsv: bool
      buffer: string

  new colortext(color: CXColor):
    # "C: 255" buffer
    setLen(result.buffer, 8)
    result.color = color
    result.flags = wMouse

  proc display(letter: char, number, scaler: float32) =
    let 
      buffer = cstring self.buffer
      packed = uint8(number * scaler)
    # Write Display Without Allocation
    let count = c_sprintf(buffer, "%c: %u", letter, packed)
    setLen(self.buffer, count)

  proc display: array[3, (char, float32, float32)] =
    let hsv = peek(self.color.color)
    if not self.hsv:
      let rgb = hsv[].toRGB
      result = [
        ('R', rgb.r, 255),
        ('G', rgb.g, 255), 
        ('B', rgb.b, 255)]
    else: # Show HSV
      result = [
        ('H', hsv.h, 100), 
        ('S', hsv.s, 100), 
        ('V', hsv.v, 100)]

  method update =
    let 
      m = addr self.metrics
      # Calculate Sizes
      w = int16 width("G: 255")
      h = getApp().font.height
    # Set Min Size
    m.minW = w
    m.minH = h * 3

  method event(state: ptr GUIState) =
    # Toggle HSV Information
    if self.clicked(state):
      self.hsv = not self.hsv

  method draw(ctx: ptr CTXRender) =
    let
      app = getApp()
      h = app.font.height
      values = self.display
    # Text Position
    let x = self.rect.x
    var y = self.rect.y
    ctx.color(app.colors.text)
    # Show R Channel
    for (l, v, s) in values:
      self.display(l, v, s)
      ctx.text(x, y, self.buffer)
      # Next Line
      y += h

# -----------------
# Color Dock Layout
# -----------------
from nogui/builder import child
import nogui/ux/layouts/[level, box, base, misc]

widget UXColorBase:
  attributes:
    {.cursor.}: c: CXColor
    # Current Color Picker
    body: GUIWidget
    side: GUIWidget

  proc createSide: GUIWidget =
    let c = self.c
    # Create Sidebar
    margin(4):
      vlevel().child:
        vertical().child:
          min: colorprimary(c)
          min: colorsecondary(c)
          min: colortransparent(c)
        # Draw Text at The End
        tail: colortext(c)

  new colorbase(color: CXColor):
    result.c = color
    # Create Widgets
    let
      side = result.createSide()
      body = dummy()
    # Add Color Sides
    result.add: 
      horizontal().child:
        min: side
        body
    # Expose Color Sides
    result.side = side
    result.body = body

  method update =
    # Vertical Min Size
    let 
      w {.cursor.} = self.side
      awful = getApp().font.height
    # TODO: improve this better
    self.metrics.minH = w.metrics.minH + awful

  method layout =
    let 
      w {.cursor.} = self.first
      m0 = addr self.metrics
      m = addr w.metrics
    # Copy Dimensions
    m.w = m0.w
    m.h = m0.h

  proc `body=`*(body: GUIWidget) =
    # Replace Tree and handle
    replace(self.body, body)
    self.body = body

# -----------------
# Color Dock Layout
# -----------------

widget UXColorTest:
  new colortest(color: CXColor):
    let 
      color0 = colorprimary(color)
      color1 = colorsecondary(color)
      alpha = colortransparent(color)
      text = colortext(color)
    # Put on Random Position
    color0.geometry(8, 8, 32, 32)
    color1.geometry(8, 48, 32, 32)
    alpha.geometry(8, 88, 32, 32)
    text.geometry(8, 128, 32, 32)
    # Add Each to Test
    result.add color0
    result.add color1
    result.add alpha
    result.add text


