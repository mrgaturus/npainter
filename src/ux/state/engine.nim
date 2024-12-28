import nogui/pack
import nogui/ux/prelude
import nogui/ux/pivot
# XXX: This is a proof of concept
import nogui/data {.all.}
# Import NPainter Engine
import ../../wip/[undo, brush, texture, binary, canvas]
import ../../wip/image/[context, proxy]
from ../../wip/image import createLayer, selectLayer
# TODO: move to engine side
import nogui/async/core as async
import nogui/libs/gl
import locks

cursors 16:
  basic *= "basic.svg" (0, 0)

# ---------------------------
# NPainter Engine Secure-Lock
# ---------------------------

type
  NEngineSecure* = object
    latch {.align: 64.}: uint64
    pool: NThreadPool

proc createSecure(pool: NThreadPool): NEngineSecure =
  result.pool = pool

proc acquire(s: var NEngineSecure) =
  const e = high(uint64)
  while true:
    if atomicExchangeN(addr s.latch, e, ATOMIC_ACQUIRE) == 0: return
    while atomicLoadN(addr s.latch, ATOMIC_RELAXED) == e:
      cpuRelax()

proc release(s: var NEngineSecure) =
  atomicStoreN(addr s.latch, 0, ATOMIC_RELEASE)

proc start*(s: ptr NEngineSecure) =
  s[].acquire()
  s.pool.start()

proc stop*(s: ptr NEngineSecure) =
  s.pool.stop()
  s[].release()

template lock*(s: var NEngineSecure, body: untyped) =
  block secure:
    s.acquire(); body
    s.release()

# --------------------------
# NPainter Engine Controller
# --------------------------

controller NPainterEngine:
  attributes: {.public.}:
    secure: NEngineSecure
    pivot: GUIStatePivot
    # Engine Objects
    brush: NBrushStroke
    bucket: NBucketProof
    # Engine Canvas
    man: NCanvasManager
    canvas: NCanvasImage
    # XXX: Proof Textures
    [tex0, tex1, tex2]: NTexture

  # TODO: prepare proxy at engine side
  proc proxyBrush0proof*: ptr NImageProxy =
    const bpp = cint(sizeof cushort)
    # Prepare Proxy
    let image = self.canvas.image
    result = addr image.proxy
    result[].prepare(image.target)
    # Prepare Brush Engine
    let
      ctx = addr image.ctx
      target = addr self.brush.pipe.canvas
      # TODO: rewrite brush engine to use less physical pages
      mapColor = ctx[].mapAux(bpp * 4)
      mapShape = ctx[].mapAux(bpp * 4)
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
    let image = self.canvas.image
    result = addr image.proxy
    result[].prepare(image.target)
    # Prepare Bucket Tool
    let
      ctx = addr image.ctx
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
    let info = addr self.canvas.image.info
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

  proc commit0proof*() =
    let
      image = self.canvas.image
      undo = self.canvas.undo
      layer = image.target
    self.canvas.update()
    getWindow().fuse()
    # Prepare Undo Step
    let step = undo.push(ucLayerMark)
    step.capture(layer)
    # Commit Changes
    commit(image.proxy)
    clearAux(image.ctx)
    step.capture(layer)
    undo.flush()

  # -- NPainter Constructor - proof of concept --
  new npainterengine(proof_W, proof_H: cint, checker = 0'i32):
    let pool = async.getPool()
    result.secure = createSecure(pool)
    result.man = createCanvasManager(pool)
    result.canvas = result.man.createCanvas(proof_W, proof_H)
    # Proof of Concept Affine Transform
    result.bindBackground0proof(checker)
    result.bindAffine0proof()
    # Initialize Multi-Threading
    result.brush.pipe.pool = pool
    # XXX: demo textures meanwhile a picker is done
    result.tex0 = newPNGTexture(toDataPath "proof/tex0.png")
    result.tex1 = newPNGTexture(toDataPath "proof/tex1.png")
    result.tex2 = newPNGTexture(toDataPath "proof/tex2.png")

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
  async
