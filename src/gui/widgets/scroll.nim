import ../widget, ../render
from ../../c_math import
  Value, distance, lerp,
  interval, toFloat, toInt
from ../event import 
  GUIState, GUIEvent
from ../config import metrics

type
  GUIScroll* = ref object of GUIWidget
    value: ptr Value
    gp, gd: float32
    vertical: bool

proc newScroll*(value: ptr Value, v = false): GUIScroll =
  new result # Initialize Slider
  # Widget Standard Flag
  result.flags = wStandard
  # Set Minimun Size
  result.minimum( # The Same as Font Size
    metrics.fontSize, metrics.fontSize)
  # Set Widget Attributes
  result.value = value
  result.vertical = v

method draw(self: GUIScroll, ctx: ptr CTXRender) =
  var rect = rect(self.rect)
  # Fill Background
  ctx.color(0xFF000000'u32)
  ctx.fill(rect)
  block: # Fill Scroll Bar
    var side, scroll: float32
    if self.vertical:
      side = float32(self.rect.h)
      scroll = max(side / interval(self.value[]), 10)
      rect.y += # Move Scroll to distance
        (side - scroll) * distance(self.value[])
      rect.yh = rect.y + scroll
    else: # Horizontal
      side = float32(self.rect.w)
      scroll = max(side / interval(self.value[]), 10)
      rect.x += # Move Scroll to distance
        (side - scroll) * distance(self.value[])
      rect.xw = rect.x + scroll
  ctx.color(0xFF555555'u32)
  ctx.fill(rect)

method event*(self: GUIScroll, state: ptr GUIState) =
  if state.eventType == evMouseClick:
    self.gp = float32:
      if self.vertical:
        state.my
      else: state.mx
    self.gd = distance(self.value[])
  elif self.test(wGrab):
    var pos, side: float32
    if self.vertical:
      pos = float32(state.my)
      side = float32(self.rect.h)
    else: # Horizontal
      pos = float32(state.mx)
      side = float32(self.rect.w)
    side -= # Dont Let Scroll Be Too Small
      max(side / interval(self.value[]), 10)
    # Set Value
    self.value[].lerp clamp(
      (pos - self.gp) / side + 
        self.gd, 0, 1), false
