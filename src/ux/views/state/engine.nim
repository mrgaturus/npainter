import nogui/builder
# Import NPainter Engine
import ../../../wip/[brush, texture, binary, canvas]
from ../../../wip/canvas/context import composed
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
  canvas
