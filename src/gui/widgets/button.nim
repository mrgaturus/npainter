import ../widget, ../render
from ../event import 
  GUIState, GUIEvent, GUICallback, pushCallback
from ../config import metrics
from ../atlas import textWidth

type
  GUIButton = ref object of GUIWidget
    cb: GUICallback
    label: string
    half: int32

proc newButton*(label: string, cb: GUICallback): GUIButton =
  new result # Initialize Button
  # Set to Font Size Metrics
  result.half = textWidth(label)
  result.minimum(result.half, metrics.fontSize + 8)
  # Button Attributes
  result.flags = wStandard
  result.label = label
  result.cb = cb

method draw(self: GUIButton, ctx: ptr CTXRender) =
  ctx.color: # Select Color State
    if not self.any(wHoverGrab):
      0xBB000000'u32
    elif self.test(wHoverGrab):
      0xFFCCCCCC'u32
    else: 0xFF000000'u32
  # Fill Button Background
  ctx.fill rect(self.rect)
  # Put Centered Text
  ctx.color(high uint32)
  ctx.text( # Draw Centered Text
    self.rect.x + (self.rect.w - self.half) shr 1, 
    self.rect.y + 6, self.label)

method event*(self: GUIButton, state: ptr GUIState) =
  if state.eventType == evMouseRelease and 
      self.test(wHover or wEnabled) and 
      not isNil(self.cb): pushCallback(self.cb)
