# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
import nogui/async/pool
import canvas/[matrix, render, copy]
import image, image/[context], undo
from image/composite import
  mark, dispatch

type
  NCanvasManager* = ptr object
    render: NCanvasRenderer
    actives: seq[NCanvasImage]
    pool: NThreadPool
  NCanvasImage* = ptr object
    man: NCanvasManager
    undo*: NImageUndo
    image*: NImage
    path*: string
    # Canvas Viewport
    affine*: ptr NCanvasAffine
    view: NCanvasViewport
    data: NCanvasData

# ---------------------
# Canvas Image Creation
# ---------------------

proc createCanvasManager*(pool: NThreadPool): NCanvasManager =
  result = create(result[].typeof)
  result.render = createCanvasRenderer()
  result.pool = pool

proc createCanvas*(man: NCanvasManager, w, h: cint): NCanvasImage =
  result = create(result[].typeof)
  # Create Canvas Image
  let image = createImage(w, h)
  let undo = createImageUndo(image)
  result.image = image
  result.undo = undo
  # Create Canvas Viewport
  result.view = createCanvasViewport(man.render, w, h)
  result.view.data = addr result.data
  result.affine = addr result.view.affine
  # Register to Canvas Manager
  man.actives.add(result)
  result.man = man

# -----------------------
# Canvas Image Destructor
# -----------------------

proc destroy(canvas: NCanvasImage) =
  destroy(canvas.undo)
  destroy(canvas.image)
  destroy(canvas.data.bg)
  # Destroy Canvas
  `=destroy`(canvas[])
  dealloc(canvas)

proc close*(canvas: NCanvasImage) =
  let
    man = canvas.man
    idx = find(man.actives, canvas)
  assert idx > 0
  # Destroy Current Canvas
  man.actives.del(idx)
  canvas.destroy()

proc destroy*(man: NCanvasManager) =
  # Destroy Actives
  for canvas in man.actives:
    canvas.destroy()
  # Destroy Canvas Manager
  `=destroy`(man[])
  dealloc(man)

# -------------------
# Canvas Image Source
# -------------------

proc background*(canvas: NCanvasImage) =
  let
    info = addr canvas.image.info
    bg = addr canvas.data.bg
  # Set Background Colors and Pattern
  bg[].color0(info.r0, info.g0, info.b0)
  bg[].color1(info.r1, info.g1, info.b1)
  bg[].pattern(info.checker)

proc source(canvas: NCanvasImage, level: cint) =
  let
    # Clamp Mipmap Level
    lvl = clamp(level, 0, 5)
    # Source Buffers
    ctx = addr canvas.image.ctx
    src = addr canvas.data.src
    map = ctx[].mapFlat(lvl)
  # Map Source to View Data
  src.w0 = ctx.w shr lvl
  src.h0 = ctx.h shr lvl
  src.s0 = map.stride
  src.buffer = map.buffer
  # Change Compositor Mipmap
  canvas.image.com.mipmap = lvl

# --------------------
# Canvas Image Staging
# --------------------

proc mark(image: NImage, tile: ptr NCanvasTile, level: cint) =
  let
    status = addr image.status
    com = addr image.com
    clip0 = status.clip
    # LOD Levels Bits
    size = cint(256 shl level)
    shift = cint(5 - level)
    mask = uint8(1 shl level)
    # Tile Position and Level
    x = cint(tile.tx) * size
    y = cint(tile.ty) * size
  # Intersect Mark Clipping
  intersect(status.clip, x, y, size, size)
  # Mark Region inside Canvas Tile
  for c in status[].checkFlat(level):
    let
      tx = c.tx
      ty = c.ty
    # Mark Compositor and Tile
    com[].mark(tx, ty)
    tile.mark(tx shl shift, ty shl shift)
    # Remove Dirty Mark
    c.check[] = c.check[] or mask
  # Restore Clipping
  status.clip = clip0

# -------------------
# Canvas Image Update
# -------------------

proc composite*(canvas: NCanvasImage) =
  let
    image = canvas.image
    view = addr canvas.view
    level = canvas.affine.lod.level
  # Mark Canvas Tiles
  for tile in view[].tiles:
    mark(image, tile, level)
  # Dispatch Compositor
  let pool = canvas.man.pool
  image.com.dispatch(pool)

proc stream*(canvas: NCanvasImage) =
  let
    render = addr canvas.man.render
    view = addr canvas.view
  # Prepare Dirty Tiles
  for tile in view[].tiles:
    view[].map(tile)
  # Copy Canvas to GPU
  render[].map()
  for map in render[].maps:
    map.stream()
  render[].unmap()

proc update*(canvas: NCanvasImage) =
  let pool = canvas.man.pool
  pool.start()
  canvas.composite()
  pool.stop()
  # Stream to GPU
  canvas.stream()

proc transform*(canvas: NCanvasImage) =
  let
    view = addr canvas.view
    lod = addr canvas.affine.lod
    clip = addr canvas.image.status.clip
    level = lod.level
  # Apply Transform
  view[].update()
  # Prepare Canvas Source
  canvas.source(lod.level)
  # Backup Current Region
  let clip0 = clip[]
  clip[] = mark(0, 0, 0, 0)
  # React to LOD Changes
  if level != lod.level:
    for tile in view[].tiles:
      tile.whole()
  # Update Canvas
  canvas.update()
  clip[] = clip0

# ----------------------
# Canvas Image Rendering
# ----------------------

proc render*(canvas: NCanvasImage) {.inline.} =
  canvas.view.render()
