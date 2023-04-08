# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
import canvas/[context, render, grid]

type
  NCanvasCheck = object
    w256, h256: cint
    buffer: seq[bool]
  NCanvasProof* = ref object
    ctx*: NCanvasContext
    view: NCanvasViewport
    check: NCanvasCheck

# -----------------------
# Canvas Proof Tile Check
# -----------------------

proc createCanvasCheck*(w, h: cint): NCanvasCheck =
  let
    w256 = (w + 255) shr 8
    h256 = (h + 255) shr 8
  # Define Canvas Check
  result.w256 = w256
  result.h256 = h256
  result.buffer.setLen(w256 * h256)

proc mark(check: var NCanvasCheck; x, y: cint) =
  let
    stride = check.w256
    rows = check.h256
  if x >= 0 and y >= 0 and x < stride and y < rows:
    check.buffer[y * stride + x] = true

proc mark(check: var NCanvasCheck; x, y, w, h: cint) =
  let
    x0 = x shr 8
    y0 = y shr 8
    x1 = (x + w + 255) shr 8
    y1 = (y + w + 255) shr 8
  for y in y0 ..< y1:
    for x in x0 ..< x1:
      check.mark(x, y)

proc test(check: var NCanvasCheck, x, y: cint): bool =
  let
    stride = check.w256
    rows = check.h256
  if x >= 0 and y >= 0 and x < stride and y < rows:
    result = check.buffer[y * stride + x]

proc clear(check: var NCanvasCheck) =
  zeroMem(addr check.buffer[0], check.w256 * check.h256)

# ----------------------
# Canvas Awful Test Copy
# ----------------------

type
  NCanvasAwful8 = ptr UncheckedArray[uint8]
  NCanvasAwful16 = ptr UncheckedArray[uint16]

proc copy(dst: NCanvasAwful8, src: NCanvasAwful16; stride, x, y, w, h: int) =
  var
    cursor_src = 
      (y * stride + x) shl 2
    cursor_dst: int
  # Convert to RGBA8
  for yi in 0 ..< h:
    for xi in 0 ..< w:
      dst[cursor_dst + 0] = cast[uint8](src[cursor_src + 0] shr 8)
      dst[cursor_dst + 1] = cast[uint8](src[cursor_src + 1] shr 8)
      dst[cursor_dst + 2] = cast[uint8](src[cursor_src + 2] shr 8)
      dst[cursor_dst + 3] = cast[uint8](src[cursor_src + 3] shr 8)
      # Next Pixel
      cursor_src += 4
      cursor_dst += 4
    # Next Row
    cursor_src += (stride - w) shl 2

# ---------------------
# Canvas Proof Creation
# ---------------------

proc createCanvasProof*(render: var NCanvasRenderer; w, h: cint): NCanvasProof =
  result.ctx = createCanvasContext(w, h)
  result.view = render.createCanvasViewport(w, h)
  result.check = createCanvasCheck(w, h)

# -------------------------
# Canvas Proof Manipulation
# -------------------------

proc copy*(canvas: var NCanvasProof) =
  discard

proc update*(canvas: var NCanvasProof) =
  canvas.view.update()
  let
    stride = canvas.ctx.w
    img = cast[NCanvasAwful16](canvas.ctx.composed 0)
  # Calculate Canvas New Tiles
  var pbos: seq[NCanvasPBOMap]
  for tile in tiles(canvas.view):
    if tile.invalid:
      pbos.add canvas.view.map(tile)
  # XXX: Where use renderer directly?
  map(canvas.view.renderer[])
  for pbo in pbos:
    let chunk = cast[NCanvasAwful8](pbo.chunk)
    copy(chunk, img, stride, pbo.x256 shl 8, pbo.y256 shl 8, 256, 256)
  unmap(canvas.view.renderer[])

proc clean*(canvas: var NCanvasProof) =
  # Iterate Each Check to Copy Buffer
  let
    stride = canvas.ctx.w
    img = cast[NCanvasAwful16](canvas.ctx.composed 0)
    w256 = canvas.check.w256
    h256 = canvas.check.h256
  # Update New Canvas Tiles
  var pbos: seq[NCanvasPBOMap]
  for y256 in 0 ..< h256:
    for x256 in 0 ..< w256:
      if canvas.check.test(x256, y256):
        pbos.add canvas.view.map(x256, y256)
  # XXX: Where use renderer directly?
  map(canvas.view.renderer[])
  for pbo in pbos:
    let chunk = cast[NCanvasAwful8](pbo.chunk)
    copy(chunk, img, stride, pbo.x256 shl 8, pbo.y256 shl 8, 256, 256)
  unmap(canvas.view.renderer[])
  # Clear Canvas Check 
  canvas.check.clear()

proc mark*(canvas: var NCanvasProof; x, y, w, h: cint) =
  let dirty = (x, y, w, h)
  canvas.view.mark(dirty)
  canvas.check.mark(x, y, w, h)
