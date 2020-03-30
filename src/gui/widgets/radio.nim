import ../widget, ../render
from ../event import 
  GUIState, GUIEvent
from ../config import metrics

type
  GUIRadio = ref object of GUIWidget
    label: string
    expected: byte
    check: ptr byte

proc newRadio*(label: string, expected: byte, check: ptr byte): GUIRadio =
  new result # Initialize Button
  # Set to Font Size Metrics
  result.minimum(0, metrics.fontSize)
  # Widget Standard Flag
  result.flags = wStandard
  # Radio Button Attributes
  result.label = label
  result.expected = expected
  result.check = check

method draw(self: GUIRadio, ctx: ptr CTXRender) =
  ctx.color: # Select Color State
    if not self.any(wHoverGrab):
      0xBB000000'u32
    elif self.test(wHoverGrab):
      0x88000000'u32
    else: 0xFF000000'u32
  # Fill Radio Background
  ctx.circle point(
    self.rect.x, self.rect.y),
    float32(self.rect.h shr 1)
  ctx.color(high uint32)
  # If Checked Draw Circle Mark
  if self.check[] == self.expected:
    ctx.circle point(
      self.rect.x + 4, self.rect.y + 4),
      float32(self.rect.h shr 1 - 4)
  # Draw Text Next To Circle
  ctx.text( # Centered Vertically
    self.rect.x + self.rect.h + 4, 
    self.rect.y - metrics.descender,
    self.label)

method event*(self: GUIRadio, state: ptr GUIState) =
  if self.test(wEnabled):
    if state.eventType == evMouseRelease and
        self.test(wHover):
      self.check[] = self.expected
