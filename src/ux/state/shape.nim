# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2025 Cristian Camilo Ruiz <mrgaturus>
import nogui/ux/values/[linear, dual]
import nogui/ux/prelude
import nogui/ux/pivot
import nogui/builder
# Import Engine State
import ../../wip/canvas/matrix
import ../../wip/mask/proxy
import ../../wip/shape
import engine, color

# ----------------------
# Shape Tool: Controller
# ----------------------

type
  CKMaskMode* = enum
    ckmaskBlit
    ckmaskUnion
    ckmaskExclude
    ckmaskIntersect
  CKFillMode* = enum
    ckcolorBlend
    ckcolorErase
  # Polygon Shapes
  CKPolygonRule* = enum
    ckruleNonZero
    ckruleOddEven
  CKPolygonCurve* = enum
    ckcurveBezier
    ckcurveCatmull
  CKPolygonShape* = enum
    ckshapeRectangle
    ckshapeCircle
    ckshapeConvex
    ckshapeStar
    ckshapeFreeform
    ckshapeLasso

controller CXShape:
  attributes:
    {.cursor.}:
      engine: NPainterEngine
      color: CXColor
    proxy: NPolygonProxy
    # Shape Properties
    {.public.}:
      rule: @ CKPolygonRule
      poly: @ CKPolygonShape
      curve: @ int32
      # Blending Modes
      blend: @ NBlendMode
      mode: @ CKMaskMode
      fill: @ CKFillMode
      # Convex Properties
      sides: @ Linear
      round: @ Linear
      inset: @ LinearDual
      # General Properties
      opacity: @ Linear
      antialiasing: @ bool
      center: @ bool
      square: @ bool
      rotate: @ bool

  proc prepareProxy(): ptr NPolygonProxy =
    let proxy = addr self.proxy
    let image = self.engine.canvas.image
    let pool = getPool()
    # Configure Shape Proxy
    proxy[].configure(addr image.ctx, addr image.status, pool)
    proxy.rule = cast[NPolyRule](self.rule.peek[])
    proxy.blend = self.blend.peek[]
    # Configure Polygon Mode
    let alpha = self.opacity.peek[].toRaw
    var mode = ord self.mode.peek[]
    if self.engine.tool == stShapes:
      mode += ord modeColorBlend
    proxy.mode = cast[NPolyMode](mode)
    proxy.alpha = uint64(alpha * 65535.0)
    proxy.color = self.color.color64()
    proxy.smooth = self.antialiasing.peek[]
    proxy[].prepare(image.target); proxy

  new cxshape(engine: NPainterEngine, color: CXColor):
    result.engine = engine
    result.color = color
    # Configure Shape Values
    result.opacity = linear(0, 100)
    result.round = linear(0, 100)
    result.inset = dual(-1.0, 0, 1.0)
    result.sides = linear(3, 32)
    # XXX: proof of concept values
    result.antialiasing.peek[] = true
    result.opacity.peek[].lerp(1.0)
    result.inset.peek[].lerp(0.75)
    result.sides.peek[].lorp(8)

# ------------------
# Shape Tool: Widget
# ------------------

type
  UXShapeStage = enum
    stagePivot
    stageDrag
    stageRotate
    stageFreeform
    stageLasso
    stageCommit

widget UXShapeDispatch:
  attributes:
    {.cursor.}:
      shape: CXShape
      proxy: ptr NPolygonProxy
      affine: ptr NCanvasAffine
    # Shape Dispatch Internal
    points: seq[NShapePoint]
    pivot: GUIStatePivot
    basic: NShapeBasic
    stage: UXShapeStage
    rod: NShapeRod

  new uxshapedispatch(shape: CXShape):
    result.flags = {wMouse, wKeyboard}
    result.shape = shape

  # -------------------------
  # Shape Dispatch: Rasterize
  # -------------------------

  proc prepare() =
    let basic = addr self.basic
    let shape {.cursor.} = self.shape
    let mode = self.shape.poly.peek[]
    let lod = self.affine.lod.level
    basic.round = shape.round.peek[].toRaw()
    basic.inset = shape.inset.peek[].toFloat()
    basic.sides = shape.sides.peek[].toInt()
    self.rod.square = shape.square.peek[]
    self.rod.center = shape.center.peek[]
    self.rod.angle = self.affine.angle
    self.proxy = shape.prepareProxy()
    self.proxy.lod = lod
    # Configure Shape Curve
    case cast[CKPolygonCurve](shape.curve.peek[])
    of ckcurveBezier: basic.curve = curveBezier
    of ckcurveCatmull: basic.curve = curveCatmull
    # Configure Shape Mode
    case mode
    of ckshapeFreeform:
      setLen(self.points, 2)
      self.stage = stageFreeform
      self.points[0] = self.rod.p0
      self.points[1] = self.rod.p0
    of ckshapeLasso:
      setLen(self.points, 1)
      self.stage = stageLasso
      self.points[0] = self.rod.p0
    else: self.stage = stageDrag

  proc rasterize() =
    let canvas {.cursor.} = self.shape.engine.canvas
    let proxy = self.proxy
    # Prepare Rasterize Points
    for p in self.basic.points:
      proxy[].push(p.x, p.y)
    # Rasterize Shape
    if self.stage == stageCommit:
      self.stage = stagePivot
      proxy[].lod = 0
      proxy[].rasterize()
      proxy[].commit()
    else: proxy[].rasterize()
    canvas.update()

  callback cbRenderBasic:
    let basic = addr self.basic
    if self.stage != stageRotate:
      let poly = self.shape.poly.peek[]; case poly
      of ckshapeRectangle: basic[].rectangle()
      of ckshapeCircle: basic[].circle()
      of ckshapeConvex: basic[].convex()
      of ckshapeStar: basic[].star()
      else: discard
    # Calculate Location
    basic[].calculate()
    self.rasterize()

  callback cbRenderFreeform:
    let basic = addr self.basic
    basic[].rawPoints(self.points)
    self.rasterize()

  callback cbRenderLasso:
    let basic = addr self.basic
    basic.points = self.points
    self.rasterize()

  # ---------------------------
  # Shape Dispatch: Interactive
  # ---------------------------

  proc stage0pivot(state: ptr GUIState) =
    if self.test(wHold):
      getWindow().send(wsUnhold)
    # Check Cursor Click Prepare
    if state.kind == evCursorClick:
      let rod = addr self.rod
      rod.p0.x = state.px
      rod.p0.y = state.py
      self.prepare()
      self.send(wsHold)

  proc stage0drag(state: ptr GUIState) =
    if self.test(wGrab):
      let rod = addr self.rod
      rod.p1.x = state.px
      rod.p1.y = state.py
      # Render Shape
      self.basic.prepare rod[]
      relax(self.cbRenderBasic)
    elif state.kind == evCursorRelease:
      if not self.shape.rotate.peek[]:
        self.stage = stageCommit
        relax(self.cbRenderBasic)
      else: self.stage = stageRotate

  proc stage0rotate(state: ptr GUIState) =
    if state.kind == evCursorRelease:
      self.stage = stageCommit
      relax(self.cbRenderBasic); return
    elif self.test(wGrab): return
    # Rotate Current Shape
    let p = NShapePoint(
      x: state.px, y: state.py)
    self.basic.rotate(p)
    relax(self.cbRenderBasic)

  proc stage0freeform(state: ptr GUIState) =
    let p = NShapePoint(x: state.px, y: state.py)
    if state.kind == evCursorClick:
      if state.key == Button_Left:
        if len(self.points) > 1:
          let p0 = self.points[^2]
          let dist = abs(p.x - p0.x) + abs(p.y - p0.y)
          # Check Freeform Double Click Finalize
          if self.pivot.clicks > 1 and dist < 8.0:
            discard self.points.pop()
            self.stage = stageCommit
        if self.stage != stageCommit:
          self.points.add(p)
      elif state.key == Button_Right:
        let l = len(self.points)
        self.points.setLen(l - 1)
        if l - 1 > 0:
          self.points[^1] = p
        else: self.stage = stageCommit
    # Render Current Shape
    else: self.points[^1] = p
    relax(self.cbRenderFreeform)

  proc stage0lasso(state: ptr GUIState) =
    let p = NShapePoint(x: state.px, y: state.py)
    if state.kind == evCursorRelease:
      self.stage = stageCommit
    # Render Current Lasso
    self.points.add(p)
    relax(self.cbRenderLasso)

  # -----------------------
  # Shape Dispatch: Methods
  # -----------------------

  proc dummyCheck(): bool =
    let tool = self.shape.engine.tool
    tool == stShapes

  method event(state: ptr GUIState) =
    if not self.dummyCheck(): return
    let p = self.affine[].forward(state.px, state.py)
    state.px = p.x; state.py = p.y
    self.pivot.capture(state)
    # Dispatch Shaping
    case self.stage
    of stagePivot: self.stage0pivot(state)
    of stageDrag: self.stage0drag(state)
    of stageRotate: self.stage0rotate(state)
    of stageFreeform: self.stage0freeform(state)
    of stageLasso: self.stage0lasso(state)
    of stageCommit: discard

  method handle(reason: GUIHandle) =
    let affine = self.shape.engine.canvas.affine
    echo "shape reason: ", reason
    let win = getWindow()
    if reason == inHover:
      win.cursor(cursorBasic)
      self.affine = affine
    elif reason == outHover:
      win.cursorReset()
