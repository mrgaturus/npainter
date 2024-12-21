import nogui/ux/prelude
import nogui/ux/values/dual
import ../wip/undo
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
  CKPainterTool* {.size: int32.sizeof.} = enum
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
    stCanvas

controller NPainterState:
  attributes: {.public.}:
    engine: NPainterEngine
    layers: CXLayers
    tool: @ CKPainterTool
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

  # XXX: proof of concept undo
  proc reactUndo(flags: set[NUndoEffect]) =
    let layers {.cursor.} = self.layers
    if ueLayerTiles in flags:
      update(self.engine.canvas)
    if ueLayerProps in flags:
      let layer {.cursor.} = layers.selected
      let user {.cursor.} = cast[GUIWidget](layer.user)
      # Reflect Props Changes to Widget
      if ueLayerList notin flags:
        send(user.parent, wsLayout)
      layers.reflect(layer)
    if ueLayerList in flags:
      force(layers.onstructure)

  callback cbUndo:
    let canvas = self.engine.canvas
    wasMoved(canvas.image.status.clip)
    # Dispatch Undo Step
    let flags = undo(canvas.undo)
    self.reactUndo(flags)

  callback cbRedo:
    let canvas = self.engine.canvas
    wasMoved(canvas.image.status.clip)
    # Dispatch Redo Step
    let flags = redo(canvas.undo)
    self.reactUndo(flags)

  # XXX: proof of concept defaults
  proc proof0default*() =
    # Locate Canvas to Center
    let engine {.cursor.} = self.engine
    let ctx {.cursor.} = engine.canvas.image.ctx
    self.canvas.x.peek[] = cfloat(ctx.w) * 0.5
    self.canvas.y.peek[] = cfloat(ctx.h) * 0.5
    lorp self.canvas.zoom.peek[], -1.0
    # Default Brush Values
    proof0default(self.brush)
    proof0default(self.layers)

# ---------------
# State Exporting
# ---------------

export
  engine,
  color,
  canvas,
  brush,
  tools
