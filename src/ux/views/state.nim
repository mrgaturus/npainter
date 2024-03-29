import nogui/builder
import nogui/gui/value
from nogui/values import lerp
# Import State Objects
import ./state/[
  color,
  canvas,
  brush,
  tools,
  engine
]

# -------------------------
# NPainter State Controller
# -------------------------

type
  CKPainterTool* = enum
    # Manipulation Docks
    stMove
    stLasso
    stSelect
    stWand
    # Painting Tools
    stBrush
    stEraser
    stFill
    stEyedrop
    # Special Tools
    stShapes
    stGradient
    stText

controller NPainterState:
  attributes: {.public.}:
    engine: NPainterEngine
    tool: @ int32 # <- CKPainterTool
    # Common State
    color: CXColor
    canvas: CXCanvas
    # Tools State
    brush: CXBrush
    bucket: CXBucket

  new npainterstate():
    result.color = cxcolor()
    result.canvas = cxcanvas()
    # Tools State
    result.brush = cxbrush()
    result.bucket = cxbucket()

  proc engine0proof*(w, h: int32) =
    let
      engine = npainterengine(w, h)
      color {.cursor.} = self.color
      # Engine Tools
      brush {.cursor.} = self.brush
      bucket {.cursor.} = self.bucket
    # Apply Engine To Objects
    self.engine = engine
    self.canvas.engine = engine
    brush.engine = engine
    brush.color = color
    bucket.engine = engine
    bucket.color = color
    # Locate Canvas to Center
    self.canvas.x.peek[] = cfloat(engine.canvas.ctx.w) * 0.5
    self.canvas.y.peek[] = cfloat(engine.canvas.ctx.h) * 0.5
    lerp self.canvas.zoom.peek[], 0.475
    # Default Brush Values
    proof0default(brush)

# ---------------
# State Exporting
# ---------------

export
  engine,
  color,
  canvas,
  brush,
  tools
