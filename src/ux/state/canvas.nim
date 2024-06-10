import engine
# Import Builder
import nogui/builder
import nogui/core/value
import nogui/ux/values/dual
# Import Widget Builder
import nogui/ux/[prelude, pivot]
from nogui import getApp, getWindow
import ../../wip/canvas/matrix
# Import PI for Angle
from math import 
  log2, pow, `mod`,
  PI, arctan2, floor

# -----------------
# Canvas Controller
# -----------------

controller CXCanvas:
  attributes:
    {.cursor.}:
      engine: NPainterEngine
    # Canvas Properties
    {.public.}:
      [zoom, angle]: @ LinearDual
      [x, y]: @ float32
      # Mirror Buttons
      mirrorX: @ bool
      mirrorY: @ bool

  proc affine: ptr NCanvasAffine {.inline.} =
    self.engine.canvas.affine

  proc update*() =
    let
      m = self.affine
      # Basic Affine Attributes
      zoom = toFloat self.zoom.peek[]
      angle = toFloat self.angle.peek[]
      x = self.x.peek[]
      y = self.y.peek[]
      # We need only care about horizontal mirror
      mirrorX = self.mirrorX.peek[]
      mirrorY = self.mirrorY.peek[]
    # Update Affine Matrix
    m.zoom = pow(2.0, -zoom)
    m.angle = -angle
    m.x = x
    m.y = y
    # Apply Horizontal and Vertical Mirror
    m.mirror = mirrorX xor mirrorY
    if mirrorY: m.angle += PI
    # Update Canvas Transform
    transform(self.engine.canvas)

  # -- Step Dispatchers Buttons --
  proc stepZoom(s: float32) =
    let 
      zoom = peek(self.zoom)
      t = zoom[].toRaw + s
    zoom[].lerp(t)
    self.update()

  proc stepAngle(s: float32) =
    let
      angle = peek(self.angle)
      t = angle[].toRaw + s
    angle[].lerp(t - t.floor)
    self.update()

  proc reset(value: & LinearDual) =
    value.peek[].lerp(0.5)
    self.update()

  # TODO: allow customize step size
  callback cbZoomReset: self.reset(self.zoom)
  callback cbZoomInc: self.stepZoom(0.03125)
  callback cbZoomDec: self.stepZoom(-0.03125)
  # TODO: allow customize step size
  callback cbAngleReset: self.reset(self.angle)
  callback cbAngleInc: self.stepAngle(0.03125)
  callback cbAngleDec: self.stepAngle(-0.03125)

  callback cbMirror:
    let 
      angle = peek(self.angle)
      t = 1.0 - angle[].toRaw
    # Invert Angle
    angle[].lerp(t)
    self.update()

  callback cbUpdate:
    self.update()
    echo "reached canvas view"

  # -- Canvas State Constructor --
  new cxcanvas(engine: NPainterEngine):
    result.engine = engine
    # Configure Transform State
    let cb = result.cbUpdate
    result.zoom = dual(-6, 6)
    result.angle = dual(-PI, PI)
    result.zoom.cb = cb
    result.angle.cb = cb
    # Mirror Updating
    result.mirrorX.cb = result.cbMirror
    result.mirrorY.cb = result.cbMirror

# ---------------
# Canvas Dispatch
# ---------------

widget UXCanvasDispatch:
  attributes:
    affine0: NCanvasAffine
    {.cursor.}:
      canvas: CXCanvas

  new uxcanvasdispatch(canvas: CXCanvas):
    result.canvas = canvas

  # -- Backup Proc --
  proc backup() =
    let c {.cursor.} = self.canvas
    # Backup Affine Transform
    let a0 = addr self.affine0
    a0[] = c.affine[]
    # TODO: move pow(2.0, zoom) to engine side
    a0.zoom = toFloat c.zoom.peek[]
    a0.angle = toFloat c.angle.peek[]

  # -- Dispatch Procs --
  proc move(state: ptr GUIState) =
    let
      c {.cursor.} = self.canvas
      a0 = addr self.affine0
      s0 = addr c.engine.pivot
      x = peek(c.x)
      y = peek(c.y)
      m = c.affine
    # Calculate Movement
    let
      # Apply Inverse Matrix
      p0 = m[].forward(s0.px, s0.py)
      p1 = m[].forward(state.px, state.py)
      # Calculate Deltas
      dx = p1.x - p0.x
      dy = p1.y - p0.y
    # Apply Movement
    x[] = a0.x - dx
    y[] = a0.y - dy

  proc zoom(state: ptr GUIState) =
    let 
      c {.cursor.} = self.canvas
      a0 = addr self.affine0
      s0 = addr c.engine.pivot
      rect = getWindow().rect
      z = peek(c.zoom)
    # Calculate Zoom Amount
    let
      size = cfloat(rect.h)
      dist = s0.py - state.py
      # Delta Scaling
      z0 = a0.zoom
      delta = (dist / size) * 6
      t = z[].toNormal(z0, delta)
    # Apply Zoom
    z[].lerp(t)

  proc rotate(state: ptr GUIState) =
    let 
      c {.cursor.} = self.canvas
      a0 = addr self.affine0
      s0 = addr c.engine.pivot
      rect = getWindow().rect
      a = peek(c.angle)
    # Calculate Rotation
    let
      cx = cfloat(rect.w) * 0.5
      cy = cfloat(rect.h) * 0.5
      # Calculate Deltas
      dx0 = s0.px - cx
      dy0 = s0.py - cy
      dx1 = state.px - cx
      dy1 = state.py - cy
      # Calculate Rotation
      rot0 = arctan2(dy0, dx0)
      rot1 = arctan2(dy1, dx1)
      delta = rot1 - rot0
    # Hardcoded 2 * PI
    const pi2 = 2 * PI
    # Adjust Rotation
    let
      d0 = (delta + pi2) mod pi2
      t = (a0.angle + d0 + PI) / pi2
    # Apply Rotation
    a[].lerp(t - t.floor)

  method event(state: ptr GUIState) =
    let
      c {.cursor.} = self.canvas
      state0 = addr c.engine.pivot
    # Backup Affine When Clicked
    if state.kind == evCursorClick:
      self.backup()
    elif self.test(wGrab):
      let mods = state0.mods
      # Decide Move, Zoom or Rotate
      if mods == {}: move(self, state)
      elif Mod_Shift in mods: zoom(self, state)
      elif Mod_Control in mods: rotate(self, state)
    # Update Canvas View
    relax(c.cbUpdate)

  method handle(reason: GUIHandle) =
    echo "canvas reason: ", reason
