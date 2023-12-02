import engine
# Import Builder
import nogui/builder
import nogui/gui/value
import nogui/values
# TODO: make affine backup on engine side
import nogui/gui/event
from nogui import getApp, windowSize
import ../../../wip/canvas/matrix
# Import PI for Angle
from math import 
  log2, pow, `mod`,
  PI, arctan2, floor

# -----------------
# Canvas Controller
# -----------------

controller CXCanvas:
  attributes:
    {.public.}:
      [zoom, angle]: @ Lerp2
      [x, y]: @ float32
      # Mirror Buttons
      mirrorX: @ bool
      mirrorY: @ bool
    # TODO: Move this to a dispatch widget
    {.public, cursor.}:
      engine: NPainterEngine
    # TODO: move this to engine side??
    prev: NCanvasAffine

  callback cbClear0proof:
    self.engine.canvas.clear()

  proc affine: ptr NCanvasAffine {.inline.} =
    self.engine.canvas.affine()

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
    # Update Canvas
    update(self.engine.canvas)

  # -- Backup Proc --
  proc backup(e: ptr AuxState) =
    # Backup Affine Transform
    self.prev = self.affine[]
    # TODO: move pow(2.0, zoom) to engine side
    self.prev.zoom = toFloat self.zoom.peek[]
    self.prev.angle = toFloat self.angle.peek[]

  # -- Dispatch Procs --
  proc move(e: ptr AuxState) =
    let
      m = self.affine
      prev = addr self.prev
      x = peek(self.x)
      y = peek(self.y)
    # Calculate Movement
    let
      # Apply Inverse Matrix
      p0 = m[].forward(e.x0, e.y0)
      p1 = m[].forward(e.x, e.y)
      # Calculate Deltas
      dx = p1.x - p0.x
      dy = p1.y - p0.y
    # Apply Movement
    x[] = prev.x - dx
    y[] = prev.y - dy

  proc zoom(e: ptr AuxState) =
    let 
      prev = addr self.prev
      bound = getApp().windowSize
      z = peek(self.zoom)
    # Calculate Zoom Amount
    let
      size = cfloat(bound.h)
      dist = e.y0 - e.y
      # Delta Scaling
      z0 = prev.zoom
      delta = (dist / size) * 6
      t = z[].toNormal(z0, delta)
    # Apply Zoom
    z[].lerp(t)

  proc rotate(e: ptr AuxState) =
    let 
      prev = addr self.prev
      bound = getApp().windowSize
      a = peek(self.angle)
    # Calculate Rotation
    let
      cx = cfloat(bound.w) * 0.5
      cy = cfloat(bound.h) * 0.5
      # Calculate Deltas
      dx0 = e.x0 - cx
      dy0 = e.y0 - cy
      dx1 = e.x - cx
      dy1 = e.y - cy
      # Calculate Rotation
      rot0 = arctan2(dy0, dx0)
      rot1 = arctan2(dy1, dx1)
      delta = rot1 - rot0
    # Hardcoded 2 * PI
    const pi2 = 2 * PI
    # Adjust Rotation
    let
      d0 = (delta + pi2) mod pi2
      t = (prev.angle + d0 + PI) / pi2
    # Apply Rotation
    a[].lerp(t - t.floor)

  callback cbDispatch(e: AuxState):
    if e.first:
      self.backup(e)
    elif (e.flags and wGrab) == wGrab:
      case e.mods
      of ShiftMod: zoom(self, e)
      of CtrlMod: rotate(self, e)
      else: move(self, e)
    # Update Canvas
    self.update()

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

  proc reset(value: & Lerp2) =
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

  # -- Canvas State Constructor --
  new cxcanvas():
    result.zoom = value(lerp2(-5, 5), result.cbUpdate)
    result.angle = value(lerp2(-PI, PI), result.cbUpdate)
    # Mirror Updating
    result.mirrorX.head.cb = result.cbMirror
    result.mirrorY.head.cb = result.cbMirror
