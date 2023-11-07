import nogui/gui/value
import nogui/ux/prelude
import nogui/builder
# Import and Export HSV Color
from nogui/values import 
  RGBColor, HSVColor, toRGB, toPacked
export RGBColor, HSVColor

# -----------------------
# Common Color Controller
# -----------------------

controller CXColor:
  attributes: {.public.}:
    [color0, color1]: HSVColor
    # Widget Shared
    color: @ HSVColor
    eraser: @ bool
    # Callback Change
    onchange: GUICallback

  # -- Value Callback --
  callback cbChange:
    # Remove Eraser
    self.eraser.peek[] = false
    force(self.onchange)

  callback cbChangeForce:
    force(self.onchange)

  # -- Simple Manipulation --
  proc swap* =
    let
      p = peek(self.color)
      eraser = peek(self.eraser)
    # Color Pointers
    var p0 = addr self.color0
    let p1 = addr self.color1
    # Swap Colors and Set Selected Color
    if p == p0: p0 = p1
    self.color = value(p0, self.cbChange)
    # Disable Eraser
    eraser[] = false
    # Execute Changed Callback
    push(self.onchange)

  # -- Eraser Manipulation --
  proc setEraser*(value: bool) =
    let t = react(self.eraser)
    # Change Value
    t[] = value

  proc checkEraser*: bool =
    self.eraser.peek[]

  # -- Color Lookup --
  proc colorRGB*: RGBColor =
    self.color.peek[].toRGB

  proc colorHSV*: HSVColor =
    self.color.peek[]

  proc color32*: uint32 =
    let hsv = peek(self.color)
    hsv[].toRGB.toPacked

  # -- Color Controller Creation --
  new cxcolor():
    # TODO: make color settings saving
    let p = addr result.color0
    result.color = value(p, result.cbChange)
