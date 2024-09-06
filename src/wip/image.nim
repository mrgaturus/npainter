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
