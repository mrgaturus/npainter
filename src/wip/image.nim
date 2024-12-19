# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
import nogui/bst
import ./image/[
  context,
  layer,
  composite,
  blend,
  proxy,
  tiles,
  # Layer Merge
  chunk,
  ffi
]

type
  NImageInfo* = object
    hash*: uint64
    w*, h*, bpp*: cint
    # Background Information
    r0*, g0*, b0*, a0: uint8
    r1*, g1*, b1*, a1: uint8
    checker*: cint
  NImage* = ptr object
    info*: NImageInfo
    ctx*: NImageContext
    status*: NImageStatus
    com*: NCompositor
    # Image Layering
    t0*, t1*: cint
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
    # Configure Root Layer
    root.props.flags = {lpVisible}
    root.props.opacity = 1.0
    root.hook.fn = cast[NLayerProc](root16proc)
    root.hook.ext = cast[ptr NImageContext](ctx)
    # Confgure Compositor Context
    c.fn = cast[NCompositorProc](blend16proc)
    c.ext = cast[ptr NImageContext](ctx)
    c[].configure(ctx.w32, ctx.h32)
  # Proxy Configure
  block proxy:
    let p = addr img.proxy
    p.status = status
    p.ctx = ctx
    p[].configure()

proc createImage*(w, h: cint): NImage =
  result = create(result[].typeof)
  result.owner.configure()
  # Create Image Root Layer
  let root = createLayer(lkFolder)
  if result.owner.insert(addr root.code):
    result.root = root
  # Create Image Context and Status
  result.ctx = createImageContext(w, h)
  result.status = createImageStatus(w, h)
  # Configure Image
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
  result = createLayer(kind)
  # Register to Owner and Define Label
  if img.owner.register(addr result.code):
    let props = addr result.props
    if kind != lkFolder:
      props.label = "Layer " & $img.t0
      inc(img.t0)
    else: # Define Folder Label
      props.label = "Folder " & $img.t1
      inc(img.t1)

proc attachLayer*(img: NImage, layer: NLayer, tag: NLayerTag) =
  let owner = addr img.owner
  let code = addr layer.code
  # Register Layer to Owner
  if code.tree != owner:
    discard owner[].insert(code)
  let node = owner[].search(tag.code)
  assert not isNil(node) and
    tag.mode != ltAttachUnknown
  # Attach Layer Using Mode
  let la = node.layer()
  case tag.mode
  of ltAttachUnknown: discard
  of ltAttachNext: la.attachNext(layer)
  of ltAttachPrev: la.attachPrev(layer)
  of ltAttachFolder: la.attachInside(layer)

proc selectLayer*(img: NImage, layer: NLayer) =
  let check = layer.code.tree == addr img.owner
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
  result = createLayer(layer.kind)
  # Register to Owner and Copy Props
  if img.owner.register(addr result.code):
    result.props = layer.props

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
      t0.data.buffer, t0.bytes * 2)

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

# -----------------
# Image Layer Merge
# -----------------

proc mergeRegion(src, dst: NLayer): NTileReserved =
  var
    r0 = src.tiles.region()
    r1 = dst.tiles.region()
  # Combine Reserved Region
  r0.w += r0.x; r0.h += r0.y
  r1.w += r1.x; r1.h += r1.y
  # Extend Reserved Region
  result.x = min(r0.x, r1.x)
  result.y = min(r0.y, r1.y)
  result.w = max(r0.w, r1.w)
  result.h = max(r0.h, r1.h)

proc mergeFill(dst: var NTile) =
  var color {.align: 16.}: uint64 = 0
  if dst.found:
    color = dst.data.color
  # Convert to Buffer
  dst.toBuffer()
  let c1 = dst.chunk()
  var c0 = c1
  # Fill Both Buffers
  c0.buffer = addr color
  var co = combine(c0, c1)
  proxy_fill(addr co)

proc mergeTile(src, dst: var NTile, co: ptr NImageComposite) =
  if not src.found:
    return
  if dst.uniform:
    dst.mergeFill()
  # Blend Layer Tile
  co.src = src.chunk()
  co.dst = dst.chunk()
  blendChunk(co)
  # Check Layer Uniform
  let co0 = cast[ptr NImageCombine](co)
  co0.src = co0.dst
  proxy_uniform(co0)
  # Convert to Uniform if was Uniform
  if co0.src.stride == co0.src.bpp:
    let color = cast[ptr uint64](co.src.buffer)[]
    dst.toColor(color)
  # Generate Mipmaps
  else: dst.mipmaps()

proc mergeLayer*(img: NImage, src, dst: NLayer): NLayer =
  result = img.copyLayer(dst)
  let g0 = addr src.tiles
  let g1 = addr result.tiles
  # Ensure Layer Tiles
  let r = mergeRegion(src, dst)
  g1[].ensure(r.x, r.y,
    r.w - r.x, r.h - r.y)
  # Configure Layer Blending
  let props = addr src.props
  var co = default(NImageComposite)
  co.alpha = cuint(props.opacity * 65535.0)
  co.fn = blend_procs[props.mode]
  # Configure Layer Blending: Clipping
  let flags = props.flags - dst.props.flags
  co.clip = cast[cuint](lpClipping in flags)
  # Blend Layer Tiles
  for y in r.y ..< r.h:
    for x in r.x ..< r.w:
      var
        t0 = g0[].find(x, y)
        t1 = g1[].find(x, y)
      # Merge Layer Tile
      mergeTile(t0, t1, addr co)
