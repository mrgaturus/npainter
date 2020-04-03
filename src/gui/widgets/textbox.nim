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
    i, w: int32

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
        self.rect.x + self.w + 4,
        self.rect.y - metrics.descender,
        1, metrics.ascender)
    else: # Hover Outline Color
      ctx.color(0xAAFFFFFF'u32)
    # Draw Outline Status
    ctx.line rect(self.rect), 1
  # Set Color To White
  ctx.color(high uint32)
  # Draw Current Text
  ctx.text(
    self.rect.x + 4,
    self.rect.y - metrics.descender, 
    self.text)

method event(self: GUITextBox, state: ptr GUIState) =
  if state.eventType == evKeyDown:
    case state.key
    of XK_BackSpace: backspace(self.text, self.i)
    of XK_Delete: delete(self.text, self.i)
    of XK_Right: forward(self.text, self.i)
    of XK_Left: reverse(self.text, self.i)
    of XK_Home: self.i = low(self.text).int32
    of XK_End: self.i = len(self.text).int32
    of XK_Return, XK_Escape: self.clear(wFocus)
    else: # Add UTF8 Char
      case state.utf8state
      of UTF8Nothing, UTF8Keysym: discard
      else: insert(self.text, state.utf8str, self.i)
    # Recalculate Text Width
    self.w = textWidth(self.text, 
      0, self.i) # From 0 to i
  elif state.eventType == evMouseClick:
    # Get Cursor Position
    self.i = textIndex(self.text, 
      state.mx - self.rect.x - 4)
    self.w = textWidth(self.text, 
      0, self.i) # from 0 to i
    # Focus Textbox
    self.set(wFocus)

method handle(widget: GUITextBox, kind: GUIHandle) =
  case kind # Un/Focus X11 Input Method
  of inFocus: pushSignal(WindowID, msgFocusIM)
  of outFocus: pushSignal(WindowID, msgUnfocusIM)
  else: discard
