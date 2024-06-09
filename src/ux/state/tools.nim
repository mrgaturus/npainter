import nogui/ux/prelude
import nogui/builder
# Import Values
import nogui/ux/values/linear
import engine, color
import ../../wip/canvas/matrix
from ../../wip/image/proxy import commit

# ----------------------
# Bucket Tool Controller
# ----------------------

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
    {.public.}:
      mode: @ int32
      target: @ int32
      # Bucket Fill Parameters
      threshold: @ Linear
      gap: @ Linear
      antialiasing: @ bool
    # TODO: Move this to a dispatch widget
    {.public, cursor.}:
      color: CXColor
      engine: NPainterEngine

  proc awful0mode: NBucketCheck =
    case CKBucketMode self.mode.peek[]
    of bcmAlphaMin: bkMinimun
    of bcmAlphaDiff: bkAlpha
    of bcmColorDiff: bkColor
    of bcmColorSimilar: bkSimilar

  # -- Bucket Dispatcher --
  callback cbDispatch:
    let
      engine {.cursor.} = self.engine
      state = engine.state
    if state.kind != evCursorClick:
      return
    let
      canvas = addr engine.canvas
      proxy = self.engine.proxyBucket0proof()
      fill = addr engine.bucket
      # Map Current Position
      affine = canvas[].affine
      p = affine[].forward(state.px, state.py)
      # Integer Position
      x = int32 p.x
      y = int32 p.y
    # Configure Bucket
    fill.tolerance = cint(self.threshold.peek[].toRaw * 255)
    fill.gap = cint(self.gap.peek[].toRaw * 255)
    fill.check = self.awful0mode
    fill.antialiasing = self.antialiasing.peek[]
    fill.rgba = self.color.color32()
    # Dispatch Position
    if fill.check != bkSimilar:
      fill[].flood(x, y)
    else: fill[].similar(x, y)
    fill[].blend()
    # Update Render Region
    canvas[].update()
    proxy[].commit()
    # Clear Proxy
    self.engine.clearProxy()

  new cxbucket():
    let liBasic = linear(0, 100)
    result.threshold = liBasic
    result.gap = liBasic
