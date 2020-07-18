import times
import libs/gl
import libs/ft2
import gui/[window, widget, render, event, timer]
from gui/widgets/button import newButton
from gui/widgets/check import newCheckbox
from gui/widgets/radio import newRadio
from gui/widgets/textbox import newTextBox
from gui/widgets/slider import newSlider
from gui/widgets/scroll import newScroll
from gui/widgets/color import newColorBar
from omath import Value, interval, lerp, RGBColor
from assets import icons
from utf8 import UTF8Input, `text=`

icons 16:
  iconBrush = "brush.svg"
  iconClear = "clear.svg"
  iconClose = "close.svg"
  iconReset = "reset.svg"

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
  if state.eventType == evMouseClick:
    if fondo.test(wStacked) and 
    not fondo.test(wHover):
      fondo.clear(wFramed)

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


{.compile: "painter/triangle.c".}
{.compile: "painter/blend.c".}
{.passC: "-msse4.1".}
proc triangle_draw(buffer: pointer, w, h: int32, v: ptr SSETriangle) {.importc: "triangle_draw".}
proc triangle_naive(buffer: pointer, w, h: int32, v: ptr CPUTriangle) {.importc: "triangle_draw_naive".}

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
  #echo "cursor mx: ", state.mx, " cursor my: ", state.my
  if state.eventType == evMouseClick:
    if not isNil(widget.frame) and test(widget.frame, wFramed):
      widget.frame.set(wFramed)
    else:
      pushTimer(widget.target, 1000)
      widget.set(wFocus)
  elif state.eventType == evMouseRelease:
    # Remove Timer
    stopTimer(widget.target)
  if widget.test(wGrab) and not isNil(widget.frame):
    move(widget.frame, state.mx + 5, state.my + 5)

method update*(widget: GUIBlank) =
  echo "reached"
  if widget.frame != nil:
    widget.frame.set(wFramed)
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
  block: # Create Widgets
    # Create two blanks
    var
      sub, blank: GUIBlank
      con: GUIFondo
    # Initialize Root
    root.color = 0xFF323232'u32
    root.flags = wStandard or wOpaque
    # --- Blank #1 ---
    blank = new GUIBlank
    blank.flags = wStandard
    blank.geometry(300,150,512,256)
    blank.texture = cpu_raster
    root.add(blank)
    # --- Blank #2 ---
    blank = new GUIBlank
    blank.flags = wStandard
    blank.geometry(20,20,100,100)
    blank.texture = cpu_raster
    block: # Menu Blank #2
      con = new GUIFondo
      con.color = 0xAA637a90'u32
      con.flags = wPopup
      con.rect.w = 200
      con.rect.h = 100
      # Sub-Blank #1
      sub = new GUIBlank
      sub.flags = wStandard
      sub.geometry(10,10,20,20)
      con.add(sub)
      # Sub-Blank #2
      sub = new GUIBlank
      sub.flags = wStandard
      sub.geometry(40,10,20,20)
      block: # Sub Menu #1
        let subcon = new GUIFondo
        subcon.color = 0xFFbdb88f'u32
        subcon.flags = wStandard
        subcon.rect.w = 300
        subcon.rect.h = 80
        # Sub-sub blank 1#
        var subsub = new GUIBlank
        subsub.flags = wStandard
        subsub.geometry(10,10,180,20)
        subcon.add(subsub)
        # Sub-sub blank 2#
        subsub = new GUIBlank
        subsub.flags = wStandard
        subsub.geometry(10,40,180,20)
        subcon.add(subsub)
        # Add to Sub
        sub.frame = subcon
      con.add(sub)
      # Add Blank 2
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
    root.add(button)
    # Creates new Window
  
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
  echo "sse: ", middle - start, "\nnaive: ", finish - middle
  fill(cpu_pixels, 0, 0, 512, 256, 0x1100FF00'u32)
  # Put it to raster
  glBindTexture(GL_TEXTURE_2D, cpu_raster)
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 512, 256, 
    GL_RGBA, GL_UNSIGNED_BYTE, addr cpu_pixels[0])
  glPixelStorei(GL_UNPACK_ALIGNMENT, 4)
  glBindTexture(GL_TEXTURE_2D, 0)
  # Open Window
  if win.show(root):
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
  win.dispose()
