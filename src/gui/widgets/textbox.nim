from x11/keysym import
  XK_Backspace, XK_Left, XK_Right,
  XK_Return, XK_Escape,
  XK_Delete, XK_Home, XK_End
# -----------------------
import ../widget, ../render, ../../utf8
from ../config import metrics, theme
from ../atlas import width, index
from ../event import
  UTF8Nothing, UTF8Keysym,
  GUIState, GUIEvent, pushSignal, 
  WindowSignal, msgOpenIM, msgCloseIM

type
  GUITextBox = ref object of GUIWidget
    input: ptr UTF8Input
    wi, wo: int32

proc newTextBox*(input: ptr UTF8Input): GUITextBox =
  new result # Initialize TextBox
  # Widget Standard Flag
  result.flags = wKeyboard
  # Set Minimun Size Like a Button
  result.minimum(0, 
    metrics.fontSize - metrics.descender)
  # Widget Attributes
  result.input = input

method draw(self: GUITextBox, ctx: ptr CTXRender) =
  if self.input.changed: # Recalculate Text Scroll and Cursor
    self.wi = width(self.input.text, self.input.cursor)
    if self.wi - self.wo > self.rect.w - 8: # Multiple of 24
      self.wo = (self.wi - self.rect.w + 32) div 24 * 24
    elif self.wi < self.wo: # Multiple of 24
      self.wo = self.wi div 24 * 24
    self.wi -= self.wo
    # Unmark Input as Changed
    self.input.changed = false
  # Fill TextBox Background
  ctx.color(theme.bgWidget)
  ctx.fill rect(self.rect)
  # Draw Textbox Status
  if self.any(wHover or wFocus):
    if self.test(wFocus):
      # Focused Outline Color
      ctx.color(theme.text)
      # Draw Cursor
      ctx.fill rect(
        self.rect.x + self.wi + 4,
        self.rect.y - metrics.descender,
        1, metrics.ascender)
    else: # Hover Outline Color
      ctx.color(theme.hoverWidget)
    # Draw Outline Status
    ctx.line rect(self.rect), 1
  # Set Color To White
  ctx.color(theme.text)
  # Draw Current Text
  ctx.text( # Offset X and Clip
    self.rect.x - self.wo + 4,
    self.rect.y - metrics.descender, 
    rect(self.rect), self.input.text)

method event(self: GUITextBox, state: ptr GUIState) =
  if state.kind == evKeyDown:
    case state.key
    of XK_BackSpace: backspace(self.input)
    of XK_Delete: delete(self.input)
    of XK_Right: forward(self.input)
    of XK_Left: reverse(self.input)
    of XK_Home: # Begin of Text
      self.input.cursor = 0
    of XK_End: # End of Text
      self.input.cursor =
        len(self.input.text).int32
    of XK_Return, XK_Escape: 
      self.clear(wFocus)
    else: # Add UTF8 Char
      case state.utf8state
      of UTF8Nothing, UTF8Keysym: discard
      else: insert(self.input, 
        state.utf8str, state.utf8size)
  elif state.kind == evMouseClick:
    # Get Cursor Position
    self.input.cursor = index(self.input.text,
      state.mx - self.rect.x + self.wo - 4)
    # Focus Textbox
    self.set(wFocus)
  # Mark Text Input as Dirty
  if state.kind < evMouseRelease:
    self.input.changed = true

method handle(widget: GUITextBox, kind: GUIHandle) =
  case kind # Un/Focus X11 Input Method
  of inFocus: pushSignal(msgOpenIM)
  of outFocus: pushSignal(msgCloseIM)
  else: discard
