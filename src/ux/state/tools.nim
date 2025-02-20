import nogui/ux/prelude
import nogui/builder
# Import Engine State
import ../../wip/canvas/matrix
import ../../wip/[image, image/layer, image/context]
import ../../wip/mask/polygon
import nogui/ux/values/linear
import engine, color

# -----------------------
# Bucket Tool: Controller
# -----------------------

type
  CKBucketMode* = enum
    bcmAlphaMin
    bcmAlphaDiff
    bcmColorDiff
    bcmColorSimilar
  CKBucketTarget* = enum
    bctCanvas
    bctLayer
    bctWandTarget

controller CXBucket:
  attributes:
    {.cursor.}:
      engine: NPainterEngine
      color: CXColor
    # Bucket Properties
    {.public.}:
      mode: @ int32
      target: @ int32
      # Bucket Fill Parameters
      threshold: @ Linear
      gap: @ Linear
      antialiasing: @ bool

  proc modecheck: NBucketCheck =
    case CKBucketMode self.mode.peek[]
    of bcmAlphaMin: bkMinimun
    of bcmAlphaDiff: bkAlpha
    of bcmColorDiff: bkColor
    of bcmColorSimilar: bkSimilar

  new cxbucket(engine: NPainterEngine, color: CXColor):
    result.engine = engine
    result.color = color
    # Configure Bucket Values
    let liBasic = linear(0, 100)
    result.threshold = liBasic
    result.gap = liBasic

# -------------------
# Bucket Tool: Widget
# -------------------

widget UXBucketDispatch:
  attributes: {.cursor.}:
    bucket: CXBucket

  new uxbucketdispatch(bucket: CXBucket):
    result.bucket = bucket

  # -- Bucket Dispatcher --
  method event(state: ptr GUIState) =
    let
      bucket {.cursor.} = self.bucket
      engine {.cursor.} = bucket.engine
    if state.kind != evCursorClick:
      return
    let
      fill = addr engine.bucket
      canvas = addr engine.canvas
      # Map Current Position
      affine = canvas[].affine
      p = affine[].forward(state.px, state.py)
      # Integer Position
      x = int32 p.x
      y = int32 p.y
    # Configure Bucket - proof of concept
    discard engine.proxyBucket0proof()
    fill.tolerance = cint(bucket.threshold.peek[].toRaw * 255)
    fill.gap = cint(bucket.gap.peek[].toRaw * 255)
    fill.check = bucket.modecheck
    fill.antialiasing = bucket.antialiasing.peek[]
    fill.rgba = bucket.color.color32()
    # Dispatch Position
    if fill.check != bkSimilar:
      fill[].flood(x, y)
    else: fill[].similar(x, y)
    fill[].blend()
    # Update Render Region
    engine.commit0proof()

  method handle(reason: GUIHandle) =
    echo "bucket reason: ", reason
    let win = getWindow()
    if reason == inHover:
      win.cursor(cursorBasic)
    elif reason == outHover:
      win.cursorReset()

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
      # Blending Modes
      blend: @ NBlendMode
      mode: @ CKMaskMode
      fill: @ CKFillMode
      # Simple Properties
      opacity: @ Linear
      sides: @ Linear
      round: @ Linear
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
    result.sides = linear(0, 32)
    # XXX: proof of concept
    result.antialiasing.peek[] = true
    result.opacity.peek[].lerp(1.0)
    result.sides.peek[].lorp(8)

  proc prepare() =
    const bpp = cint(sizeof uint8)
    let engine {.cursor.} = self.engine
    let image = engine.canvas.image
    let ctx = addr image.ctx
    # Prepare Polygon Buffer
    let pool = getPool()
    let map = ctx[].mapAux(bpp)
    configure(engine.shape, pool, map)
    clear(engine.shape)

  proc commit() =
    discard

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
    discard
