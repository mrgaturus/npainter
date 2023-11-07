import nogui/builder
import ./state/[brush, canvas, color, tools]

# -------------------------
# NPainter State Controller
# -------------------------

controller NPainterState:
  attributes: {.public.}:
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

# ---------------
# State Exporting
# ---------------

export 
  brush,
  canvas,
  color,
  tools
