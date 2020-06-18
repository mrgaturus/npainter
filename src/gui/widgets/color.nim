# TODO: Replace by a color wheel

import ../widget, ../render
from ../../omath import
  RGBColor, rgb, rgb8,
  HSVColor, hsv
from ../event import 
  GUIState, GUIEvent

type
  GRABColorBar = enum
    gNothing, gBar, gSquare
  GUIColorBar = ref object of GUIWidget
    color: ptr RGBColor
    # Cache Colors and Hue
    pColor: RGBColor
    hColor: GUIColor
    pHSV: HSVColor
    # Mouse Grab Status
    status: GRABColorBar

const # Not Alpha Colors
  CARET = uint32 0x88FFFFFF
  BLACK = uint32 0xFF000000
  WHITE = high uint32
let hueSix = # Hue Six Breakpoints
  [0xFF0000FF'u32, 0xFF00FFFF'u32, 
   0xFF00FF00'u32, 0xFFFFFF00'u32,
   0xFFFF0000'u32, 0xFFFF00FF'u32]

proc newColorBar*(color: ptr RGBColor): GUIColorBar =
  new result # Alloc Color Wheel
  result.flags = wStandard
  # 100x100 minimun size
  result.minimum(100, 100)
  # Widget Attributes
  result.color = color
  # Allways Invalidate Color
  if color[] == result.pColor:
    result.pColor.r = 1

method draw(self: GUIColorBar, ctx: ptr CTXRender) =
  var rect = rect(self.rect)
  # 1 -- Check if HSV needs update
  if self.color[] != self.pColor:
    # Change Prev Color
    self.pColor = self.color[]
    # Change Prev HSV
    var nHSV: HSVColor
    nHSV.rgb(self.pColor)
    if nHSV.s == 0: # Hue
      nHSV.h = self.pHSV.h
    self.pHSV = nHSV
    # Change Hue RGBA
    nHSV.s = 1; nHSV.v = 1
    self.hColor = block:
      var hRGB: RGBColor
      hRGB.hsv(nHSV)
      hRGB.rgb8()
  # 2 -- Draw Saturation / Hue Quad
  ctx.addVerts(8, 12); rect.xw -= 25
  # White/Color Gradient
  vertexCOL(0, rect.x, rect.y, WHITE)
  vertexCOL(1, rect.xw, rect.y, self.hColor)
  vertexCOL(2, rect.x, rect.yh, WHITE)
  vertexCOL(3, rect.xw, rect.yh, self.hColor)
  triangle(0, 0,1,2); triangle(3, 1,2,3)
  # Black/Color Gradient
  vertexCOL(4, rect.x, rect.y, 0)
  vertexCOL(5, rect.xw, rect.y, 0)
  vertexCOL(6, rect.x, rect.yh, BLACK)
  vertexCOL(7, rect.xw, rect.yh, BLACK)
  triangle(6, 4,5,6); triangle(9, 5,6,7)
  # 3 -- Draw Color Bar
  ctx.addVerts(14, 36)
  # Move to X to Bar
  rect.xw += 25
  rect.x = rect.xw - 20
  # Prepare Y coord
  rect.yh = rect.y
  block: # Draw Hue Gradient
    let h = # Six Parts
      self.rect.h / 6
    var # Iterator
      i, j, k: int32
      hue: uint32
    while i < 7:
      if i + 1 < 7: # Quad Elements
        triangle(k, j, j + 1, j + 2)
        triangle(k + 3, j + 1, j + 2, j + 3)
        # Hue Color
        hue = hueSix[i]
      else: hue = hueSix[0]
      # Bar Vertexs Segment
      vertexCOL(j, rect.x, rect.yh, hue)
      vertexCOL(j + 1, rect.xw, rect.yh, hue)
      rect.yh += h # Next Y
      # Next Hue Quad
      i += 1; j += 2; k += 6
    rect.yh -= h
  # 4 -- Draw Cursors
  block: # Hue Cursor
    let y = rect.y + 
      (rect.yh - rect.y) * self.pHSV.h
    # Clip Cursor Dimensions
    if y - 3 > rect.y: rect.y = y - 3
    if y + 3 < rect.yh: rect.yh = y + 3
    # Draw Cursor
    ctx.color(CARET); ctx.fill(rect)
    ctx.color(BLACK); ctx.line(rect, 1)
  # Saturation/Value Cursor
  rect = rect(self.rect); block:
    rect.xw -= 25
    let # X/Y Position
      x = rect.x + (rect.xw - rect.x) * self.pHSV.s
      y = rect.y + (rect.yh - rect.y) * (1 - self.pHSV.v)
    # Clip Cursor Dimensions
    if x - 5 > rect.x: rect.x = x - 5
    if x + 5 < rect.xw: rect.xw = x + 5
    if y - 5 > rect.y: rect.y = y - 5
    if y + 5 < rect.yh: rect.yh = y + 5
    # Draw Cursor
    ctx.color(CARET); ctx.fill(rect)
    ctx.color(BLACK); ctx.line(rect, 1)

method event(self: GUIColorBar, state: ptr GUIState) =
  if state.eventType == evMouseClick:
    let delta = state.mx - self.rect.x
    self.status =
      if delta < self.rect.w - 25: gSquare
      elif delta > self.rect.w - 20: gBar
      else: gNothing # Grab to Dead Zone
  elif self.test(wGrab):
    let h = clamp(
      (state.my - self.rect.y) / 
      self.rect.h, 0, 1)
    case self.status:
    of gSquare:
      self.pHSV.s = clamp(
        (state.mx - self.rect.x) / 
        (self.rect.w - 25), 0, 1)
      self.pHSV.v = 1 - h
      # Change Color
      self.pColor.hsv(self.pHSV)
      self.color[] = self.pColor
    of gBar:
      var nHSV = self.pHSV
      nHSV.h = h
      # Change Color
      self.pHSV = nHSV
      self.pColor.hsv(self.pHSV)
      self.color[] = self.pColor
      # Change Hue Color
      nHSV.s = 1; nHSV.v = 1
      self.hColor = block:
        var hRGB: RGBColor
        hRGB.hsv(nHSV)
        hRGB.rgb8()
    of gNothing: discard