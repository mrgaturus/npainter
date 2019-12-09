import libs/gl
import gui/window, gui/context
from gui/container import GUILayout

proc region(tex: ptr CTXFrame, rect: ptr GUIRect) =
  let verts = [
    float32 rect.x, float32 rect.y,
    float32(rect.x + rect.w), float32 rect.y,
    float32 rect.x, float32(rect.y + rect.h),
    float32(rect.x + rect.w), float32(rect.y + rect.h)
  ]
  region(tex, unsafeAddr verts[0])

when isMainModule:
  var 
    win = newGUIWindow(1280, 720, new GUILayout)
    running = win.exec()
    # pixel: tuple[r,g,b,a: byte]
    # Rects
    rect1 = GUIRect(x: 20, y: 20, w: 200, h: 100)
    rect2 = GUIRect(x: 20, y: 130, w: 100, h: 200)
    rect3 = GUIRect(x: 400, y: 130, w: 500, h: 300)
    rect4 = GUIRect(x: 20, y: 20, w: 40, h: 40)
    rect5 = GUIRect(x: 80, y: 20, w: 40, h: 40)
    color1 = GUIColor(r: 0.5, g: 0.0, b: 0.5, a: 1.0)
    color2 = GUIColor(r: 0.0, g: 0.5, b: 0.0, a: 1.0)
    frame = win.ctx.createFrame()
  
  win.ctx.createRegion(addr rect1)
  win.ctx.createRegion(addr rect2)
  frame.resize(rect3.w, rect3.h)
  frame.region(addr rect3)
  frame.visible = true

  win.ctx.makeCurrent(nil)
  addr(win.ctx).clip(addr rect1)
  addr(win.ctx).color(addr color1)
  addr(win.ctx).clear()
  
  addr(win.ctx).clip(addr rect2)
  addr(win.ctx).color(addr color2)
  addr(win.ctx).clear()

  win.ctx.makeCurrent(frame)
  addr(win.ctx).color(addr color2)
  addr(win.ctx).clear()

  addr(win.ctx).color(addr color1)
  addr(win.ctx).clip(addr rect4)
  addr(win.ctx).clear()

  addr(win.ctx).color(addr color1)
  addr(win.ctx).clip(addr rect5)
  addr(win.ctx).clear()
  glBindFramebuffer(GL_FRAMEBUFFER, 0)

  while running:
    win.handleEvents()
    running = win.handleTick()
    
    glClearColor(0.5, 0.5, 0.5, 1.0)
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

    win.render()

  win.exit()

discard """

let
  # Rectangle Element & Texture Coordinates
  rectCORDS1 = [
    20'f32, 20'f32,
    40'f32, 20'f32,
    20'f32, 40'f32,
    40'f32, 40'f32
  ]
  rectCORDS2 = [
    80'f32, 20'f32,
    100'f32, 20'f32,
    80'f32, 40'f32,
    100'f32, 40'f32
  ]
  rectCORDS3 = [
    120'f32, 20'f32,
    140'f32, 20'f32,
    120'f32, 40'f32,
    140'f32, 40'f32
  ]

  texCORDS = [
    0'f32, 0'f32,
    1'f32, 0'f32,
    0'f32, 1'f32,
    1'f32, 1'f32
  ]

var
  # GL State
  vao, vbo: GLuint
  # GL GUI Program
  program: GLuint
  uCol, uPro: GLuint

when isMainModule:
  var 
    win = newGUIWindow(1024, 600)
    running = win.exec()

  glGenVertexArrays(1, vao.addr)
  glBindVertexArray(vao)
  #glGenBuffers(1, ebo.addr)
  #glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo)
  #glBufferData(GL_ELEMENT_ARRAY_BUFFER, 6 * uint32.sizeof, rectEBO[0].unsafeAddr, GL_STATIC_DRAW)

  glGenBuffers(1, vbo.addr)
  glBindBuffer(GL_ARRAY_BUFFER, vbo)
  glBufferData(GL_ARRAY_BUFFER, 16 * float32.sizeof, nil, GL_STREAM_DRAW)
  # LAYOUT: VVVVCCCC
  #glBufferSubData(GL_ARRAY_BUFFER, 0, 8 * float32.sizeof, rectC[0].unsafeAddr)
  #glBufferSubData(GL_ARRAY_BUFFER, 8, 8 * float32.sizeof, rectCORDS[0].unsafeAddr)

  glVertexAttribPointer(0, 2, cGL_FLOAT, false, 2 * float32.sizeof, cast[pointer](0))
  glVertexAttribPointer(1, 2, cGL_FLOAT, false, 2 * float32.sizeof, cast[pointer](8))
  glBufferSubData(GL_ARRAY_BUFFER, 8, 8 * float32.sizeof, texCORDS[0].unsafeAddr)

  glEnableVertexAttribArray(0)
  glEnableVertexAttribArray(1)
  glViewport(0, 0, 1024, 600)

  var rect1: GUIRect
  var color1: GUIColor

  while running:
    # GUI
    win.handleEvents()
    running = win.handleFrame()
    # Render Painter
    win.ctx.makeCurrent(addr win.rect, nil)
    glClearColor(0.5, 0.5, 0.5, 1.0)
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

    glBindVertexArray(vao)
    glBufferSubData(GL_ARRAY_BUFFER, 0, 8 * float32.sizeof, rectCORDS1[0].unsafeAddr)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
    glBufferSubData(GL_ARRAY_BUFFER, 0, 8 * float32.sizeof, rectCORDS2[0].unsafeAddr)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)
    glBufferSubData(GL_ARRAY_BUFFER, 0, 8 * float32.sizeof, rectCORDS3[0].unsafeAddr)
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

    rect1.x = 50
    rect1.y = 50
    rect1.w = 100
    rect1.h = 100
    addr(win.ctx).push(addr rect1, nil)
    glClear(GL_COLOR_BUFFER_BIT)
  
    rect1.x = 30
    rect1.y = 30
    rect1.w = 80
    rect1.h = 80
    color1 = GUIColor(r: 1.0, g: 0.5, b: 0.5, a: 1.0)
    addr(win.ctx).push(addr rect1, addr color1)
    glClear(GL_COLOR_BUFFER_BIT)

    rect1.x = 80
    rect1.y = 80
    rect1.w = 125
    rect1.h = 125
    color1 = GUIColor(r: 1.0, g: 1.0, b: 0.5, a: 1.0)
    addr(win.ctx).clip(addr rect1)
    addr(win.ctx).color(addr color1)
    glClear(GL_COLOR_BUFFER_BIT)

    # GL Draw
    win.render()

  # Dispose Window
  win.exit()
"""