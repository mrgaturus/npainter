import ../widget, ../render
from ../event import 
  GUIState, GUIEvent, GUICallback, pushCallback
from ../config import metrics

type
  GUICheckBox = ref object of GUIWidget
    label: string
    expected: byte
    check: ptr byte

proc newCheckbox*(label: string, expected: byte, check: ptr byte): GUICheckBox =
  new result # Initialize Button
  # Set to Font Size Metrics
  result.minimum(0, metrics.fontSize)
  # Widget Standard Flag
  result.flags = wStandard
  # Radio Button Attributes
  result.label = label
  result.expected = expected
  result.check = check

method draw(self: GUICheckBox, ctx: ptr CTXRender) =
  ctx.color: # Select Color State
    if not self.any(wHoverGrab):
      0xBB000000'u32
    elif self.test(wHoverGrab):
      0x88000000'u32
    else: 0xFF000000'u32
  # Fill Check Background
  ctx.fill rect(
    self.rect.x, self.rect.y,
    self.rect.h, self.rect.h)
  ctx.color(high uint32)
  # If Checked Draw Mark
  if self.check[] == self.expected:
    ctx.fill rect(
      self.rect.x + 4, self.rect.y + 4,
      self.rect.h - 8, self.rect.h - 8)
  # Put Centered Text
  ctx.color(high uint32)
  ctx.text( # Draw Centered Text
    self.rect.x + self.rect.h + 4, 
    self.rect.y - metrics.descender,
    self.label)

method event*(self: GUICheckBox, state: ptr GUIState) =
  if self.test(wEnabled):
    if state.eventType == evMouseRelease and
        self.test(wHover):
      self.check[] = not self.check[]
