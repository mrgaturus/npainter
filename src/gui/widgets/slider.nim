import ../widget, ../render
from strutils import 
  formatFloat, ffDecimal
from ../../c_math import
  Value, distance, lerp,
  toFloat, toInt
from ../event import GUIState
from ../config import metrics
from ../atlas import textWidth

type
  GUISlider* = ref object of GUIWidget
    value: ptr Value
    decimals: int8

proc newSlider*(value: ptr Value, decimals = 0i8): GUISlider =
  new result # Initialize Slider
  # Widget Standard Flag
  result.flags = wStandard
  # Set Minimun Size
  result.minimum(0, metrics.fontSize - 
    metrics.descender)
  # Set Widget Attributes
  result.value = value
  result.decimals = decimals

method draw(self: GUISlider, ctx: ptr CTXRender) =
  block: # Draw Slider
    var rect = rect(self.rect)
    # Fill Slider Background
    ctx.color(0xFF000000'u32)
    ctx.fill(rect)
    # Fill Slider Bar
    ctx.color(0xFF555555'u32)
    rect.xw = # Get Slider Width
      rect.x + float32(self.rect.w) * distance(self.value[])
    ctx.fill(rect)
  # Draw Text Information
  let text = 
    if self.decimals > 0:
      formatFloat(self.value[].toFloat, 
        ffDecimal, self.decimals)
    else: $self.value[].toInt
  ctx.color(high uint32)
  ctx.text( # On The Right Side
    self.rect.x + self.rect.w - textWidth(text) - 4, 
    self.rect.y - metrics.descender, text)

method event*(self: GUISlider, state: ptr GUIState) =
  if self.test(wGrab):
    self.value[].lerp clamp(
      (state.mx - self.rect.x) / self.rect.w, 
      0, 1), self.decimals == 0
