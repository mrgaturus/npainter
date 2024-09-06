# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
import ./image/[
  context, 
  layer, 
  composite, 
  blend,
  proxy,
  tiles
]

type
  NImage* = ptr object
    ctx*: NImageContext
    status*: NImageStatus
    com*: NCompositor
    # Image Ticket
    ticket: cint
    t0, t1: cint
    # Image Layering
    owner*: NLayerOwner
    root*: NLayer
    # Image Proxy
    selected*: NLayer
    proxy*: NImageProxy

# ----------------------------
# Image Creation & Destruction
# ----------------------------

proc configure(img: NImage) =
  let
    root = img.root
    ctx = addr img.ctx
    status = addr img.status
  # Compositor Configure
  block compositor:
    let c = addr img.com
    c.root = root
    c.ctx = ctx
    c.mipmap = 4
    # Configure Root Layer
    root.props.flags = {lpVisible}
    root.hook.fn = cast[NLayerProc](root16proc)
    c.fn = cast[NCompositorProc](blend16proc)
  # Proxy Configure
  block proxy:
    let p = addr img.proxy
    p.ctx = ctx
    p.status = status
  # Configure Compositor & Proxy
  img.com.configure()
  img.proxy.configure()

proc createImage*(w, h: cint): NImage =
  result = create(result[].type)
  result.ticket = 0
  # Create Image Root Layer
  let owner = cast[NLayerOwner](addr result.ticket)
  result.root = createLayer(lkFolder, owner)
  result.owner = owner
  # Create Image Context
  result.ctx = createImageContext(w, h)
  result.status = createImageStatus(w, h)
  # Configure Compositor and Proxy
  result.configure()

proc destroy*(img: NImage) =
  # Dealloc Layers and Context
  destroy(img.root)
  destroy(img.ctx)
  # Dealloc Image
  `=destroy`(img[])
  dealloc(img)

# ------------------------
# Image Layer Manipulation
# ------------------------

proc createLayer*(img: NImage, kind: NLayerKind): NLayer =
  result = createLayer(kind, img.owner)
  # Define Layer Ticket
  result.props.code = img.ticket
  result.props.label = "Layer " & $img.t0
  # Step Layer Count
  inc(img.ticket)
  inc(img.t0)

proc selectLayer*(img: NImage, layer: NLayer) =
  # Check if layer belongs to image
  let check = pointer(layer.owner) == pointer(img.owner)
  assert check, "layer owner mismatch"
  # Configure Proxy Selected
  img.selected = layer
  img.proxy.layer = layer

proc markLayer*(img: NImage, layer: NLayer) =
  let status = addr img.status
  # Mark Tiles if is a Image Layer
  if layer.kind == lkColor:
    for tile in layer.tiles:
      status[].mark32(tile.x, tile.y)
  # Mark Recursive if is a Folder
  elif layer.kind == lkFolder:
    var la = layer.first
    # Walk Folder Childrens
    while not isNil(la):
      img.markLayer(la)
      la = la.next

# ---------------------
# Image Layer Duplicate
# ---------------------

proc copyLayerBase(img: NImage, layer: NLayer): NLayer =
  result = createLayer(layer.kind, img.owner)
  result.props = layer.props
  result.props.code = img.ticket
  # Step Layer Count
  inc(img.ticket)

proc copyTiles(src, dst: NLayer) =
  let
    g0 = addr src.tiles
    g1 = addr dst.tiles
  # Ensure Layer Tiles
  let r = g0[].region()
  g1[].ensure(r.x, r.y, r.w, r.h)
  # Copy Tile Buffers
  for t0 in g0[]:
    var t1 = g1[].find(t0.x, t0.y)
    # Copy Uniform Tile
    if t0.uniform:
      t1.data.color = t0.data.color
      continue
    # Copy Buffer Tile
    t1.toBuffer()
    copyMem(t1.data.buffer, 
      t0.data.buffer, t0.bytes)

proc copyLayer*(img: NImage, layer: NLayer): NLayer =
  result = img.copyLayerBase(layer)
  # Copy Buffer Color Tiles
  if layer.kind == lkColor:
    layer.copyTiles(result)
  elif layer.kind == lkFolder:
    var la0 = layer.last
    # Walk Layer Childrens
    while not isNil(la0):
      let la = img.copyLayer(la0)
      # Attach Created Layer
      result.attachInside(la)
      la0 = la0.prev
