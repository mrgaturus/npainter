import ../widget, ../render
from ../../c_math import
  Value, distance, lerp,
  interval, toFloat, toInt
import ../../c_math
from ../event import 
  GUIState, GUIEvent
from ../config import metrics

type
  GUIScroll* = ref object of GUIWidget
    value: ptr Value
    gp, gd: float32

proc newScroll*(value: ptr Value): GUIScroll =
  new result # Initialize Slider
  # Widget Standard Flag
  result.flags = wStandard
  # Set Minimun Size
  result.minimum(0, metrics.fontSize - 
    metrics.descender)
  # Set Widget Attributes
  result.value = value

method draw(self: GUIScroll, ctx: ptr CTXRender) =
  var rect = rect(self.rect)
  # Fill Background
  ctx.color(0xFF000000'u32)
  ctx.fill(rect)
  block: # Fill Scroll Bar
    let # Calculate Scroll Width
      w = float32(self.rect.w)
      scroll = max(w / interval(self.value[]), 10)
    rect.x += # Move Scroll to distance
      (w - scroll) * distance(self.value[])
    rect.xw = rect.x + scroll
  ctx.color(0xFF555555'u32)
  ctx.fill(rect)

method event*(self: GUIScroll, state: ptr GUIState) =
  if state.eventType == evMouseClick:
    self.gp = float32(state.mx)
    self.gd = distance(self.value[])
  elif self.test(wGrab):
    let pos = float32(state.mx)
    # Get Dragable Width
    var w = float32(self.rect.w)
    w -= max(w / interval(self.value[]), 10)
    # Set Value
    self.value[].lerp clamp(
      (pos - self.gp) / w + 
        self.gd, 0, 1), false
