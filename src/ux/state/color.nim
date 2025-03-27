import nogui/core/value
import nogui/ux/prelude
import nogui/builder
# Import and Export HSV Color
import nogui/ux/values/chroma
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
    send(self.onchange)

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

  proc color64*: uint64 =
    # TODO: move to nogui/values/chroma
    let hsv = peek(self.color)
    let rgb = hsv[].toRGB()
    let # TODO: move this to values
      r = uint64(rgb.r * 65535.0)
      g = uint64(rgb.g * 65535.0)
      b = uint64(rgb.b * 65535.0)
    # Pack Color Channels to 32bit
    r or (g shl 16) or (b shl 32) or (0xFFFF'u64 shl 48)

  # -- Color Controller Creation --
  new cxcolor():
    # TODO: make color settings saving
    let p = addr result.color0
    result.color = value(p, result.cbChange)
