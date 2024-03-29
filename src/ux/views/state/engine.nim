import nogui/builder
# Import NPainter Engine
import ../../../wip/[brush, texture, binary, canvas]
import ../../../wip/image/[layer, context, proxy]
from ../../../wip/image import createLayer, selectLayer
# Import Multithreading
import nogui/spmc
# TODO: move to engine side
import nogui/libs/gl

# --------------------------------------------------
# NPainter Engine Workaround Event
# TODO: remove this after unify event/callback queue
# --------------------------------------------------
import nogui/gui/widget
from nogui/gui/event import GUIEvent
export GUIEvent
export widget

type
  AuxState* = object
    # XXX: hacky way to avoid flooding engine events
    #      - This will be solved unifying event/callback queue
    #      - Also allow deferring a callback after polling events/callbacks
    busy*: ptr bool
    first*: bool
    # Cursor Event
    click0*: uint
    x0*, y0*: float32
    x*, y*: float32
    pressure*: float32
    # Pressed Key
    flags*: GUIFlags
    kind*: GUIEvent
    key*: uint
    mods*: uint

proc guard*(aux: ptr AuxState): bool =
  let busy = aux.busy
  # Guard Aux State
  # XXX: this hack is useful to deal
  #      with current awful event->callaback sequence
  #      occurs as [ev0, ev1, ev2 -> cb0, cb1, cb2]
  #      it should be [ev0 -> cb0, ev1 -> cb1, ev2 -> cb2]
  result = busy[]
  busy[] = true

proc release*(aux: ptr AuxState) =
  aux.busy[] = false

# --------------------------
# NPainter Engine Controller
# --------------------------

controller NPainterEngine:
  attributes: {.public.}:
    # Engine Objects
    brush: NBrushStroke
    bucket: NBucketProof
    canvas: NCanvasImage
    # Canvas Manager
    man: NCanvasManager
    pool: NThreadPool
    # XXX: Proof Textures
    [tex0, tex1, tex2]: NTexture

  # TODO: prepare proxy at engine side
  proc proxyBrush0proof*: ptr NImageProxy =
    const bpp = cint(sizeof cushort)
    # Prepare Proxy
    let canvas = self.canvas
    result = addr canvas.image.proxy
    result[].prepare(pmBlit)
    # Prepare Brush Engine
    let
      ctx = addr canvas.image.ctx
      target = addr self.brush.pipe.canvas
      # Buffer Mappings
      mapColor = ctx[].mapAux(bpp * 4)
      mapShape = ctx[].mapAux(bpp)
    # Target Dimensions
    target.w = ctx.w
    target.h = ctx.h
    # Target Buffer Stride
    target.stride = result.map.stride shr 3
    # Target Buffer Pointers
    target.dst = cast[ptr cshort](result.map.buffer)
    target.buffer0 = cast[ptr cshort](mapColor.buffer)
    target.buffer1 = cast[ptr cshort](mapShape.buffer)
    # Clear Brush Engine
    self.brush.clear()

  proc proxyBucket0proof*: ptr NImageProxy =
    const bpp = cint(sizeof cushort)
    # Prepare Proxy
    let canvas = self.canvas
    result = addr canvas.image.proxy
    result[].prepare(pmBlit)
    # Prepare Bucket Tool
    let
      ctx = addr canvas.image.ctx
      mapColor = ctx[].mapAux(bpp * 4)
      mapShape = ctx[].mapAux(bpp * 4)
    # Configure Bucket Tool
    self.bucket = configure(
      result.map.buffer,
      # Auxiliar Buffers
      mapColor.buffer,
      mapShape.buffer,
      ctx.w, ctx.h
    )
    # We need mark all buffer
    result[].mark(0, 0, ctx.w, ctx.h)
    result[].stream()

  proc bindBackground0proof(checker: cint) =
    let info = addr self.canvas.info
    # Primary Color
    info.r0 = 255
    info.g0 = 255
    info.b0 = 255
    # Secondary Color
    info.r1 = 225
    info.g1 = 225
    info.b1 = 225
    # Update Background
    info.checker = 4
    self.canvas.background()

  proc bindAffine0proof =
    # Initialize View Transform
    let
      canvas = self.canvas
      ctx = addr canvas.image.ctx
      w = ctx.w
      h = ctx.h
      a = canvas.affine
    # Configure Affine Transform
    a.cw = w
    a.ch = h
    a.x = float32(w) * 0.5
    a.y = float32(h) * 0.5
    a.zoom = 0.5
    a.angle = 0.0
    # Update Canvas
    canvas.transform()

  proc bindLayer0proof =
    let
      canvas = self.canvas
      img = canvas.image
      layer = img.createLayer(lkColor)
    # Change Layer Properties
    layer.props.flags.incl(lpVisible)
    layer.props.opacity = 1.0
    # Select Current Layer
    img.root.attachInside(layer)
    img.selectLayer(layer)

  proc clearProxy*() =
    clearAux(self.canvas.image.ctx)

  # -- NPainter Constructor - proof of concept --
  new npainterengine(proof_W, proof_H: cint, checker = 0'i32):
    result.man = createCanvasManager()
    result.canvas = result.man.createCanvas(proof_W, proof_H)
    # Proof of Concept Affine Transform
    result.bindLayer0proof()
    result.bindBackground0proof(checker)
    result.bindAffine0proof()
    # Initialize Multi-Threading
    result.pool = newThreadPool(6)
    result.brush.pipe.pool = result.pool
    # XXX: demo textures meanwhile a picker is done
    result.tex0 = newPNGTexture("tex0.png")
    result.tex1 = newPNGTexture("tex1.png")
    result.tex2 = newPNGTexture("tex2.png")

  # -- Foreign Renderer --
  proc renderGL*() =
    # TODO: move to engine side
    glEnable(GL_BLEND)
    glBlendEquation(GL_FUNC_ADD)
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA)
    # Render Canvas
    self.canvas.render()

# ----------------
# Engine Exporting
# ----------------

export
  brush,
  texture,
  binary,
  canvas,
  spmc
