# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2025 Cristian Camilo Ruiz <mrgaturus>
import nogui/ux/values/[linear, dual]
import nogui/ux/prelude
import nogui/builder
# Import Engine State
import ../../wip/canvas/matrix
import ../../wip/[image, image/layer, image/context]
import ../../wip/mask/polygon
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
    ckfillBlend
    ckfillErase
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

  new cxshape(engine: NPainterEngine, color: CXColor):
    result.engine = engine
    result.color = color
    # Configure Shape Values
    result.opacity = linear(0, 100)
    result.round = linear(0, 100)
    result.inset = dual(-1.0, 0, 1.0)
    result.sides = linear(0, 32)
    # XXX: proof of concept values
    result.antialiasing.peek[] = true
    result.opacity.peek[].lerp(1.0)
    result.inset.peek[].lerp(0.75)
    result.sides.peek[].lorp(8)

# ------------------
# Shape Tool: Widget
# ------------------

widget UXShapeDispatch:
  attributes: {.cursor.}:
    shape: CXShape

  new uxshapedispatch(shape: CXShape):
    result.shape = shape

  method event(state: ptr GUIState) =
    discard

  method handle(reason: GUIHandle) =
    echo "shape reason: ", reason
    let win = getWindow()
    if reason == inHover:
      win.cursor(cursorBasic)
    elif reason == outHover:
      win.cursorReset()
