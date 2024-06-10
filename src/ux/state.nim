import nogui/builder
import nogui/core/value
import nogui/ux/values/dual
# Import State Objects
import ./state/[
  color,
  canvas,
  brush,
  tools,
  engine,
  layers
]

# -------------------------
# NPainter State Controller
# -------------------------

type
  CKPainterTool* = enum
    # Manipulation Tools
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
    stView

controller NPainterState:
  attributes: {.public.}:
    engine: NPainterEngine
    layers: CXLayers
    tool: @ int32 # <- CKPainterTool
    # Common State
    color: CXColor
    canvas: CXCanvas
    # Tools State
    brush: CXBrush
    bucket: CXBucket

  new npainterstate0proof(w, h: int32, checker = 0'i32):
    let engine = npainterengine(w, h, checker)
    result.layers = cxlayers(engine.canvas)
    result.engine = engine
    # Initialize Color State
    let color = cxcolor()
    result.color = color
    # Initialize Tools State
    result.canvas = cxcanvas(engine)
    result.brush = cxbrush(engine, color)
    result.bucket = cxbucket(engine, color)

  proc proof0default*() =
    # Locate Canvas to Center
    let engine {.cursor.} = self.engine
    self.canvas.x.peek[] = cfloat(engine.canvas.image.ctx.w) * 0.5
    self.canvas.y.peek[] = cfloat(engine.canvas.image.ctx.h) * 0.5
    lorp self.canvas.zoom.peek[], -1.0
    # Default Brush Values
    proof0default(self.brush)

# ---------------
# State Exporting
# ---------------

export
  engine,
  color,
  canvas,
  brush,
  tools
