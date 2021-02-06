import times
import libs/gl
import libs/ft2
import gui/[window, widget, render, event, signal, timer]
from gui/widgets/button import newButton
from gui/widgets/check import newCheckbox
from gui/widgets/radio import newRadio
from gui/widgets/textbox import newTextBox
from gui/widgets/slider import newSlider
from gui/widgets/scroll import newScroll
from gui/widgets/color import newColorBar
import gui/widgets/label
from gui/atlas import width
from gui/config import metrics, theme
from omath import Value, interval, lerp, RGBColor
from assets import icons
from utf8 import UTF8Input, `text=`

icons 16:
  iconBrush = "brush.svg"
  iconClear = "clear.svg"
  iconClose = "close.svg"
  iconReset = "reset.svg"

# -------------------
# TEST TOOLTIP WIDGET
# -------------------

type
  GUITooltip = ref object of GUIWidget

method draw(tp: GUITooltip, ctx: ptr CTXRender) =
  ctx.color theme.bgWidget
  ctx.fill rect(tp.rect.x, tp.rect.y, 
    "TEST TOOLTIP".width, metrics.fontSize)
  ctx.color theme.text
  ctx.text(tp.rect.x, tp.rect.y, "TEST TOOLTIP")

method timer(tp: GUITooltip) =
  if tp.test(wVisible):
    tp.close()
  else: tp.open()

# ------------------------
# TEST MENU WIDGET PROTOTYPE
# ------------------------

type
  GUIMenuKind = enum
    mkMenu, mkAction
  GUIMenuItem = object
    name: string
    width: int32
    case kind: GUIMenuKind:
    of mkMenu:
      menu: GUIMenu
    of mkAction:
      cb: GUICallback
  GUIMenu = ref object of GUIWidget
    hover, submenu: int32
    bar: GUIMenuBar
    items: seq[GUIMenuItem]
  GUIMenuTile = object
    name: string
    width: int32
    menu: GUIMenu
  GUIMenuBar = ref object of GUIWidget
    grab: bool
    hover: int32
    items: seq[GUIMenuTile]

# -- Both Menus --
proc add(self: GUIMenuBar, name: string, menu: GUIMenu) =
  menu.bar = self # Set Menu
  menu.kind = wgPopup
  self.items.add GUIMenuTile(
    name: name, menu: menu)

proc add(self: GUIMenu, name: string, menu: GUIMenu) =
  if menu != self: # Avoid Cycle
    menu.kind = wgMenu
    self.items.add GUIMenuItem(
      name: name, menu: menu, kind: mkMenu)

proc add(self: GUIMenu, name: string, cb: GUICallback) =
  self.items.add GUIMenuItem( # Add Callback
    name: name, cb: cb, kind: mkAction)

# -- Standard Menu
proc newMenu(): GUIMenu =
  new result # Alloc
  # Define Atributes
  result.flags = wMouse
  result.hover = -1
  result.submenu = -1

method layout(self: GUIMenu) =
  var # Max Width/Height
    mw, mh: int32
  for item in mitems(self.items):
    mw = max(mw, item.name.width)
    mh += metrics.fontSize
  # Set Dimensions
  self.rect.w = # Reserve Space
    mw + (metrics.fontSize shl 1)
  self.rect.h = mh + 4

method draw(self: GUIMenu, ctx: ptr CTXRender) =
  var 
    offset = self.rect.y + 2
    index: int32
  let x = self.rect.x + (metrics.fontSize)
  # Draw Background
  ctx.color theme.bgContainer
  ctx.fill rect(self.rect)
  ctx.color theme.text
  # Draw Each Menu
  for item in mitems(self.items):
    if self.hover == index:
      ctx.color theme.hoverWidget
      var r = rect(self.rect)
      r.y = offset.float32
      r.yh = r.y + float32(metrics.fontSize)
      ctx.fill(r)
      ctx.color theme.text
    ctx.text(x, offset - metrics.descender, item.name)
    offset += metrics.fontSize
    inc(index) # Next Index
  ctx.color theme.bgWidget
  ctx.line rect(self.rect), 1

method event(self: GUIMenu, state: ptr GUIState) =
  case state.kind
  of evCursorClick, evCursorMove:
    if self.test(wHover):
      var # Search Hovered Item
        index: int32
        cursor = self.rect.y + 2
      for item in mitems(self.items):
        let space = cursor + metrics.fontSize
        if state.my > cursor and state.my < space:
          case item.kind
          of mkMenu: # Submenu
            if state.kind == evCursorMove and index != self.submenu:
              if self.submenu >= 0 and self.items[self.submenu].kind == mkMenu:
                close(self.items[self.submenu].menu)
              # Open new Submenu
              open(item.menu)
              item.menu.move(self.rect.x + self.rect.w - 1, cursor - 2)
              self.submenu = index
          of mkAction: # Callback
            if state.kind == evCursorClick:
              pushCallback(item.cb)
              self.close()
              if not isNil(self.bar):
                self.bar.grab = false
          # Menu Item Found
          self.hover = index; return
        # Next Menu
        cursor = space
        inc(index)
    elif not isNil(self.bar) and # Use Menu Bar
    pointOnArea(self.bar, state.mx, state.my):
      self.bar.event(state)
    elif state.kind == evCursorClick:
      self.close() # Close Menu
      if not isNil(self.bar):
        self.bar.grab = false
    self.hover = -1 # Remove Current Hover
  else: discard

method handle(self: GUIMenu, kind: GUIHandle) =
  case kind
  of outFrame: # Close Submenu y Close is requested
    if self.submenu >= 0 and self.items[self.submenu].kind == mkMenu:
      close(self.items[self.submenu].menu)
    self.submenu = -1
  else: discard

# -- Menu Bar
proc newMenuBar(): GUIMenuBar =
  new result # Alloc
  # Define Atributes
  result.flags = wMouse
  result.hover = -1
  result.minimum(0, metrics.fontSize)

method layout(self: GUIMenuBar) =
  # Get Text Widths
  for menu in mitems(self.items):
    menu.width = menu.name.width

method draw(self: GUIMenuBar, ctx: ptr CTXRender) =
  # Draw Background
  ctx.color theme.bgWidget
  ctx.fill rect(self.rect)
  # Draw Each Menu
  var # Iterator
    index: int32
    cursor: int32 = self.rect.x
    r: CTXRect
  r.y = float32(self.rect.y)
  r.yh = r.y + float32(self.hint.h)
  # Set Text Color
  ctx.color theme.text
  for item in mitems(self.items):
    if self.hover == index:
      # Set Hover Color
      ctx.color theme.hoverWidget
      # Define Rect
      r.x = cursor.float32
      r.xw = r.x + 4 +
        float32(item.width)
      # Fill Rect
      ctx.fill(r)
      # Return Text Color
      ctx.color theme.text
    cursor += 2
    ctx.text(cursor, 
      self.rect.y + 2, item.name)
    cursor += item.width + 2
    inc(index) # Current Index

method event(self: GUIMenuBar, state: ptr GUIState) =
  case state.kind
  of evCursorClick, evCursorMove:
    var # Search Hovered Item
      cursor = self.rect.x
      index: int32
    for item in mitems(self.items):
      let space = cursor + item.width + 4
      if state.mx > cursor and state.mx < space:
        if state.kind == evCursorClick:
          if item.menu.test(wVisible):
            close(item.menu)
            self.grab = false
          else: # Open Popup
            self.grab = true
            open(item.menu)
          item.menu.move(cursor,
            self.rect.y + self.rect.h)
        elif self.grab and self.hover >= 0 and
        index != self.hover:
          # Change Menu To Other
          close(self.items[self.hover].menu)
          open(item.menu)
          item.menu.move(cursor,
            self.rect.y + self.rect.h)
        self.hover = index; break
      # Next Menu
      cursor = space
      inc(index)
  else: discard

# -----------------------
# TEST MISC WIDGETS STUFF
# -----------------------

type
  Counter = object
    clicked, released: int
  GUIBlank = ref object of GUIWidget
    frame: GUIWidget
    texture: GLuint
  GUIFondo = ref object of GUIWidget
    color: uint32

method draw(fondo: GUIFondo, ctx: ptr CTXRender) =
  ctx.color if fondo.test(wHover):
    fondo.color or 0xFF000000'u32
  else: fondo.color
  ctx.fill rect(fondo.rect)

method event(fondo: GUIFondo, state: ptr GUIState) =
  if state.kind == evCursorClick:
    if not fondo.test(wHover):
      fondo.close() # Close

var coso: UTF8Input
proc helloworld*(g, d: pointer) =
  coso.text = "hello world"
  echo "hello world"

# ------------------------
# LOAD TRIANGLE RASTERIZER
# ------------------------

type
  CPUVertex {.packed.} = object
    x, y: int32
  SSEVertex {.packed.} = object
    x, y: float32
  CPUTriangle = array[3, CPUVertex]
  SSETriangle = array[3, SSEVertex]


#{.compile: "painter/triangle.c".}
{.compile: "painter/blend.c".}
{.passC: "-msse4.1".}
proc triangle_draw(buffer: pointer, w, h: int32, v: ptr SSETriangle) = discard
proc triangle_naive(buffer: pointer, w, h: int32, v: ptr CPUTriangle) = discard

# ------------------
# GUI BLANK METHODS
# ------------------

method draw*(widget: GUIBlank, ctx: ptr CTXRender) =
  ctx.color if widget.test(wHover):
    0xFF7f7f7f'u32
  else: 0xFFFFFFFF'u32
  ctx.fill rect(widget.rect)
  ctx.texture(rect widget.rect, widget.texture)

method event*(widget: GUIBlank, state: ptr GUIState) =
  case state.kind
  of evCursorClick:
    if state.key == MiddleButton:
      echo "middle button xdd"
    if not isNil(widget.frame) and test(widget.frame, wVisible):
      close(widget.frame)
    else:
      pushTimer(widget.target, 1000)
      widget.set(wFocus)
  of evCursorRelease:
    # Remove Timer
    echo "w timer removed"
    stopTimer(widget.target)
  of evKeyDown:
    echo "tool kind: ", state.tool
    echo " -- mouse  x: ", state.mx
    echo " -- stylus x: ", state.px
    echo ""
    echo " -- mouse  y: ", state.my
    echo " -- stylus y: ", state.py
    echo ""
    echo " -- pressure: ", state.pressure
    echo ""
  else: discard
  if widget.test(wGrab) and not isNil(widget.frame):
    move(widget.frame, state.mx + 5, state.my + 5)

method timer*(widget: GUIBlank) =
  echo "w timer open frame"
  if widget.frame != nil:
    open(widget.frame)
  # Remove Timer
  stopTimer(widget.target)

method handle*(widget: GUIBlank, kind: GUIHandle) =
  echo "handle done: ", kind.repr
  echo "by: ", cast[uint](widget)

proc blend*(dst, src: uint32): uint32{.importc: "blend_normal".}
proc fill*(buffer: var seq[uint32], x, y, w, h: int32, color: uint32) =
  var i, xi, yi: int32
  yi = y
  while i < h:
    xi = x
    while xi < w:
      let col = buffer[yi * w + xi]
      buffer[yi * w + xi] = blend(col, color)
      inc(xi)
    inc(i); inc(yi)

proc exit(a, b: pointer) =
  pushSignal(msgTerminate)

proc world(a, b: pointer) =
  echo "Hello World"

when isMainModule:
  var counter = Counter(
    clicked: 0, 
    released: 0
  )
  var win = newGUIWindow(1024, 600, addr counter)
  var ft: FT2Library
  var cpu_raster: GLuint
  var cpu_pixels: seq[uint32]
  var bolo, bala: bool
  var equisde: byte
  var val: Value
  var val2: Value
  var col = RGBColor(r: 50 / 255, g: 50 / 255, b: 50 / 255)
  val2.interval(0, 100)
  val.interval(0, 5)
  val.lerp(0.5, true)
  
  # Generate CPU Raster
  cpu_pixels.setLen(512 * 256)
  glGenTextures(1, addr cpu_raster)
  glBindTexture(GL_TEXTURE_2D, cpu_raster)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, cast[GLint](GL_LINEAR))
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, cast[GLint](GL_NEAREST))
  glTexImage2D(GL_TEXTURE_2D, 0, cast[GLint](GL_RGBA8), 512, 256, 
    0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
  glBindTexture(GL_TEXTURE_2D, 0)

  # Initialize Freetype2
  if ft2_init(addr ft) != 0:
    echo "ERROR: failed initialize FT2"
  # Create a new Window
  let root = new GUIFondo
  block: # Create Menu Bar
    var bar = newMenuBar()
    var menu: GUIMenu
    # Create a Menu
    menu = newMenu()
    menu.add("Hello World", world)
    menu.add("Exit A", exit)
    bar.add("File", menu)
    # Create Other Menu
    menu = newMenu()
    menu.add("Hello World", world)
    menu.add("Exit B", exit)
    bar.add("Other", menu)
    block: # SubMenu
      var sub = newMenu()
      sub.add("Hello Inside", world)
      sub.add("Kill Program", exit)
      menu.add("The Game", sub)
    # Add Menu Bar to Root Widget
    bar.geometry(20, 160, 200, bar.hint.h)
    root.add(bar)
  block: # Create Widgets
    # Create two blanks
    var
      sub, blank: GUIBlank
      con: GUIFondo
    # Initialize Root
    root.color = 0xFF323232'u32
    # --- Blank #1 ---
    blank = new GUIBlank
    blank.geometry(300,150,512,256)
    blank.texture = cpu_raster
    root.add(blank)
    # --- Blank #2 ---
    blank = new GUIBlank
    blank.flags = wMouse
    blank.geometry(20,20,100,100)
    blank.texture = cpu_raster
    block: # Menu Blank #2
      con = new GUIFondo
      con.flags = wMouse
      con.color = 0xAA637a90'u32
      con.rect.w = 200
      con.rect.h = 100
      # Sub-Blank #1
      sub = new GUIBlank
      sub.geometry(10,10,20,20)
      con.add(sub)
      # Sub-Blank #2
      sub = new GUIBlank
      sub.flags = wMouse
      sub.geometry(40,10,20,20)
      block: # Sub Menu #1
        let subcon = new GUIFondo
        subcon.flags = wMouse
        subcon.color = 0x72bdb88f'u32
        subcon.rect.w = 300
        subcon.rect.h = 80
        # Sub-sub blank 1#
        var subsub = new GUIBlank
        subsub.geometry(10,10,80,20)
        subcon.add(subsub)
        # Sub-sub blank 2#
        subsub = new GUIBlank
        subsub.geometry(10,40,80,20)
        subcon.add(subsub)
        # Add Sub to Sub
        block: # Sub Menu #1
          let fondo = new GUIFondo
          fondo.color = 0x64000000'u32
          fondo.geometry(90, 50, 300, 80)
          # Sub-sub blank 1#
          var s = new GUIBlank
          s.geometry(10,10,20,20)
          fondo.add(s)
          # Sub-sub blank 2#
          s = new GUIBlank
          s.geometry(10,40,20,20)
          fondo.add(s)
          # Add Fondo to sub
          subcon.add(fondo)
        # Add to Sub
        subcon.kind = wgPopup
        sub.frame = subcon
      con.add(sub)
      # Add Blank 2
      con.kind = wgFrame
      blank.frame = con
    root.add(blank)
    # Add a GUI Button
    let button = newButton("Test Button CB", helloworld)
    button.geometry(20, 200, 200, button.hint.h)
    block: # Add Checkboxes
      var check = newCheckbox("Check B", addr bolo)
      check.geometry(20, 250, 100, check.hint.h)
      root.add(check)
      check = newCheckbox("Check A", addr bala)
      check.geometry(120, 250, 100, check.hint.h)
      root.add(check)
    block: # Add Radio Buttons
      var radio = newRadio("Radio B", 1, addr equisde)
      radio.geometry(20, 300, 100, radio.hint.h)
      root.add(radio)
      radio = newRadio("Radio A", 2, addr equisde)
      radio.geometry(120, 300, 100, radio.hint.h)
      root.add(radio)
    block: # Add TextBox
      var textbox = newTextBox(addr coso)
      textbox.geometry(20, 350, 200, textbox.hint.h)
      root.add(textbox)
    block: # Add Slider
      var slider = newSlider(addr val)
      slider.geometry(20, 400, 200, slider.hint.h)
      root.add(slider)
    block: # Add Scroll
      var scroll = newScroll(addr val)
      scroll.geometry(20, 450, 200, scroll.hint.h)
      root.add(scroll)
    block: # Add Scroll
      var scroll = newScroll(addr val, true)
      scroll.geometry(20, 480, scroll.hint.h, 200)
      root.add(scroll)
    block: # Add Scroll
      var color = newColorBar(addr col)
      color.geometry(50, 500, color.hint.w * 2, color.hint.h * 2)
      root.add(color)
      color = newColorBar(addr col)
      color.geometry(300, 500, color.hint.w * 2, color.hint.h * 2)
      root.add(color)
    block: # Add Labels
      var label: GUILabel
      let rect = GUIRect(
        x: 550, y: 500, w: 400, h: 300)
      # Right Align
      label = newLabel("TEST TEXT", hoRight, veTop)
      label.rect = rect; label.hint = rect; root.add(label)
      label = newLabel("TEST TEXT", hoRight, veMiddle)
      label.rect = rect; label.hint = rect; root.add(label)
      label = newLabel("TEST TEXT", hoRight, veBottom)
      label.rect = rect; label.hint = rect; root.add(label)
      # Middle Align
      label = newLabel("TEST TEXT", hoMiddle, veTop)
      label.rect = rect; label.hint = rect; root.add(label)
      label = newLabel("TEST TEXT", hoMiddle, veMiddle)
      label.rect = rect; label.hint = rect; root.add(label)
      label = newLabel("TEST TEXT", hoMiddle, veBottom)
      label.rect = rect; label.hint = rect; root.add(label)
      # Left Align
      label = newLabel("TEST TEXT", hoLeft, veTop)
      label.rect = rect; label.hint = rect; root.add(label)
      label = newLabel("TEST TEXT", hoLeft, veMiddle)
      label.rect = rect; label.hint = rect; root.add(label)
      label = newLabel("TEST TEXT", hoLeft, veBottom)
      label.rect = rect; label.hint = rect; root.add(label)
    root.add(button)
  # Create a random tooltip
  var tooltip = new GUITooltip
  tooltip.kind = wgTooltip
  tooltip.rect.x = 40
  tooltip.rect.y = 180
  
  # Draw a triangle
  var tri: CPUTriangle
  var sse: SSETriangle
  block:
    var vert: CPUVertex
    vert.x = 0; vert.y = 0; tri[0] = vert
    vert.x = 512; vert.y = 0; tri[1] = vert
    vert.x = 256; vert.y = 256; tri[2] = vert
  block:
    var vert: SSEVertex
    vert.x = 0; vert.y = 0; sse[0] = vert
    vert.x = 512; vert.y = 0; sse[1] = vert
    vert.x = 256; vert.y = 256; sse[2] = vert
  var start, middle, finish: Time
  start = getTime()
  triangle_draw(addr cpu_pixels[0], 512, 256, addr sse)
  middle = getTime()
  triangle_naive(addr cpu_pixels[0], 512, 256, addr tri)
  finish = getTime()
  #echo "sse: ", middle - start, "\nnaive: ", finish - middle
  fill(cpu_pixels, 0, 0, 512, 256, 0x1100FF00'u32)
  # Put it to raster
  glBindTexture(GL_TEXTURE_2D, cpu_raster)
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 512, 256, 
    GL_RGBA, GL_UNSIGNED_BYTE, addr cpu_pixels[0])
  glPixelStorei(GL_UNPACK_ALIGNMENT, 4)
  glBindTexture(GL_TEXTURE_2D, 0)
  # Open Window
  if win.open(root):
    pushTimer(tooltip.target, 1000)
    while true:
      win.handleEvents() # Input
      if win.handleSignals(): break
      win.handleTimers() # Timers
      # Render Main Program
      glClearColor(0.5, 0.5, 0.5, 1.0)
      glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
      # Render GUI
      win.render()
  # Close Window
  win.close()
