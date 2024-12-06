import nogui/ux/prelude
import nogui/ux/values/dual
import ../wip/[undo, proof, image]
import ../wip/image/context
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
    let flags = undo(canvas.undo)
    self.reactUndo(flags)

  callback cbRedo:
    let canvas = self.engine.canvas
    let flags = redo(canvas.undo)
    self.reactUndo(flags)

  # XXX: proof of concept file i/o
  callback cbFileOpen:
    let canvas = self.engine.canvas
    let image = canvas.image
    let effect = loadFile(image, canvas.undo)
    if effect == {}: return
    # Replace Canvas Undo And React
    canvas.undo = createImageUndo(image)
    image.selectLayer(image.root.first)
    # Redraw Whole Canvas
    let status = addr image.status
    complete(status.clip)
    status[].mark(status.clip)
    # React Undo Effect
    self.reactUndo(effect)
    echo effect

  callback cbFileSave:
    let canvas = self.engine.canvas
    let image = canvas.image
    # Save Image File
    saveFile(image)

  callback cbExportPNG:
    let canvas = self.engine.canvas
    let image = canvas.image
    # Save Image File
    saveFilePNG(image)

  # XXX: proof of concept defaults
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
