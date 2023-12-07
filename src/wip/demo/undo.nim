import supersnappy
# Import Canvas Proof
import ../canvas
import ../canvas/context

# -------------------
# Demo History Object
# -------------------

type
  # Undo History Buffer
  NDemoNZ = seq[uint8]
  # Undo History
  NDemoHistory* = object
    canvas*: ptr NCanvasProof
    # History Stack
    stack: seq[NDemoNZ]
    idx: cint

# -----------------
# Demo Buffer Chunk
# -----------------

proc chunk(canvas: ptr NCanvasProof): NDemoNZ =
  let
    ctx = addr canvas.ctx
    size = (ctx.w64 * ctx.h64) shl 3
  var buf = newSeqUninitialized[uint8](size)
  copyMem(addr buf[0], ctx[].composed 0, size)
  result = compress(buf)

proc apply(canvas: ptr NCanvasProof, chunk: NDemoNZ) =
  let
    ctx = addr canvas.ctx
  var buf = uncompress(chunk)
  copyMem(ctx[].composed 0, addr buf[0], buf.len)
  # Apply to Canvas
  canvas[].mark(0, 0, ctx.w, ctx.h)
  canvas[].clean()

proc clear(canvas: ptr NCanvasProof) =
  let 
    ctx = addr canvas.ctx
    size = (ctx.w64 * ctx.h64) shl 3
  zeroMem(ctx[].composed 0, size)
  # Apply to Canvas
  canvas[].mark(0, 0, ctx.w, ctx.h)
  canvas[].clean()

# --------------------
# Demo History Storing
# --------------------

proc snapshot*(story: var NDemoHistory) =
  let c = story.canvas.chunk()
  # Shrink if is not Last
  if story.idx < len(story.stack):
    story.stack.setLen(story.idx)
  # Push Chunk to Stack
  story.stack.add(c)
  inc(story.idx)

# --------------------
# Demo History Manager
# --------------------

proc undo*(story: var NDemoHistory) =
  let i = story.idx - 2
  # Clear When Last
  if i < 0:
    if i + 1 == 0:
      story.canvas.clear()
      dec(story.idx)
    return
  # Lookup Current Index
  let z = story.stack[i]
  # Apply Redo
  story.canvas.apply(z)
  dec(story.idx)

proc redo*(story: var NDemoHistory) =
  let i = story.idx
  if i < len(story.stack):
    # Lookup Current Index
    let z = story.stack[i]
    # Apply Undo
    story.canvas.apply(z)
    inc(story.idx)
