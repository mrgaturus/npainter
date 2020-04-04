from x11/keysym import
  XK_Backspace, XK_Left, XK_Right,
  XK_Return, XK_Escape,
  XK_Delete, XK_Home, XK_End
# -----------------------
import ../widget, ../render, ../../utf8
from ../config import metrics
from ../atlas import textWidth, textIndex
from ../event import 
  GUIState, GUIEvent, pushSignal,
  UTF8Nothing, UTF8Keysym
from ../window import 
  WindowID, msgFocusIM, msgUnfocusIM

type
  GUITextBox = ref object of GUIWidget
    text: string
    i, wi, wo: int32

proc newTextBox*(text: var string): GUITextBox =
  new result # Initialize TextBox
  # Widget Standard Flag
  result.flags = wStandard
  # Set Minimun Size Like a Button
  result.minimum(0, 
    metrics.fontSize - metrics.descender)
  # Widget Attributes
  shallowCopy(result.text, text)

method draw(self: GUITextBox, ctx: ptr CTXRender) =
  # Fill TextBox Background
  ctx.color(0xFF000000'u32)
  ctx.fill rect(self.rect)
  # Draw Textbox Status
  if self.any(wHover or wFocus):
    if self.test(wFocus):
      # Focused Outline Color
      ctx.color(high uint32)
      # Draw Cursor
      ctx.fill rect(
        self.rect.x + self.wi + 4,
        self.rect.y - metrics.descender,
        1, metrics.ascender)
    else: # Hover Outline Color
      ctx.color(0xAAFFFFFF'u32)
    # Draw Outline Status
    ctx.line rect(self.rect), 1
  # Set Color To White
  ctx.color(high uint32)
  # Draw Current Text
  ctx.text( # Offset X
    self.rect.x - self.wo + 4,
    self.rect.y - metrics.descender, 
    rect(self.rect), self.text)

method event(self: GUITextBox, state: ptr GUIState) =
  if state.eventType == evKeyDown:
    case state.key
    of XK_BackSpace: backspace(self.text, self.i)
    of XK_Delete: delete(self.text, self.i)
    of XK_Right: forward(self.text, self.i)
    of XK_Left: reverse(self.text, self.i)
    of XK_Home: # Begin of Text
      self.i = low(self.text).int32
      self.wi = 0; self.wo = 0
      return # Don't Recalculate
    of XK_End: # End of Text
      self.i = len(self.text).int32
      self.wi = textWidth(self.text)
      # Calculate Offset
      if self.wi > self.rect.w - 8: # Multiple of 24
        self.wo = (self.wi - self.rect.w + 32) div 24 * 24
      self.wi -= self.wo
      return # Don't Recalculate
    of XK_Return, XK_Escape: 
      self.clear(wFocus)
    else: # Add UTF8 Char
      case state.utf8state
      of UTF8Nothing, UTF8Keysym: discard
      else: insert(self.text, state.utf8str, self.i)
  elif state.eventType == evMouseClick:
    # Get Cursor Position
    self.i = textIndex(self.text, 
      state.mx - self.rect.x + self.wo - 4)
    # Focus Textbox
    self.set(wFocus)
  # Recalculate Cursor Width and Offset
  if state.eventType < evMouseRelease:
    self.wi = textWidth(self.text, self.i)
    # Forward or Reverse Offset index
    if self.wi - self.wo > self.rect.w - 8: 
      self.wo += 24
    elif self.wi < self.wo: 
      self.wo -= 24
    # Calculate Offset Width
    self.wi -= self.wo

method handle(widget: GUITextBox, kind: GUIHandle) =
  case kind # Un/Focus X11 Input Method
  of inFocus: pushSignal(WindowID, msgFocusIM)
  of outFocus: pushSignal(WindowID, msgUnfocusIM)
  else: discard
