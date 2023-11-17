import nogui/builder
import nogui/gui/value
# Import NPainter Engine
import ./state/[brush, canvas, color, tools]
import ../../wip/[brush, texture, binary, canvas]
from ../../wip/canvas/context import composed
# Import Multithreading
import nogui/spmc

# --------------------------
# NPainter Engine Controller
# --------------------------

controller NPainterEngine:
  attributes: {.public.}:
    # Engine Objects
    brush: NBrushStroke
    bucket: NBucketProof
    canvas: NCanvasProof
    # Multi-threading
    pool: NThreadPool

  # TODO: bind canvas to tools at engine side
  proc bindBrush0proof =
    let
      ctx = addr self.canvas.ctx
      canvas = addr self.brush.pipe.canvas
    # Set Canvas Dimensions
    canvas.w = ctx.w
    canvas.h = ctx.h
    # Set Canvas Stride
    canvas.stride = canvas.w
    # Working Buffers
    canvas.dst = cast[ptr cshort](ctx[].composed 0)
    canvas.buffer0 = cast[ptr cshort](addr ctx.buffer0[0])
    canvas.buffer1 = cast[ptr cshort](addr ctx.buffer1[0])
    # Clear Brush Engine
    self.brush.clear()

  # TODO: bind canvas to tools at engine side
  proc bindBucket0proof =
    let
      ctx = addr self.canvas.ctx
      composed = cast[ptr cshort](ctx[].composed 0)
      buffer0 = cast[ptr cshort](addr ctx.buffer0[0])
      buffer1 = cast[ptr cshort](addr ctx.buffer1[0])
    # Configure Bucket Tool
    self.bucket = configure(
      composed,
      buffer0, 
      buffer1, 
      ctx.w, ctx.h
    )

  # TODO: init affine at engine side
  proc bindAffine0proof =
    # Initialize View Transform
    let
      ctx = addr self.canvas.ctx
      w = ctx.w
      h = ctx.h
      a = self.canvas.affine()
    # Configure Affine Transform
    a.cw = w
    a.ch = h
    a.x = float32(w) * 0.5
    a.y = float32(h) * 0.5
    a.zoom = 1.0
    a.angle = 0.0
    # Update Canvas
    self.canvas.update()

  # -- NPainter Constructor --
  new npainterengine(proof_W, proof_H: cint):
    result.canvas = createCanvasProof(proof_W, proof_H)
    # Proof of Concept Initializers
    result.bindBrush0proof()
    result.bindBucket0proof()
    result.bindAffine0proof()
    # Initialize Multi-Threading
    result.pool = newThreadPool(6)

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

# ---------------
# State Exporting
# ---------------

export 
  brush,
  canvas,
  color,
  tools

export
  brush,
  texture,
  binary,
  canvas
