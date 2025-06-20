# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
import nogui/bst
import ./mask/ffi
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
    t0*, t1*, t2*: uint32
    owner*: NLayerOwner
    mask*: NLayer
    root*: NLayer
    # Image Proxy
    test*: NLayer
    target*: NLayer
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
  # Create Image Root Layers
  let root = createLayer(lkFolder)
  let mask = createLayer(lkMask)
  if result.owner.insert(addr root.code): result.root = root
  if result.owner.register(addr mask.code): result.mask = mask
  # Create Image Context and Status
  result.ctx = createImageContext(w, h)
  result.status = createImageStatus(w, h)
  result.configure()

proc destroy*(img: NImage) =
  # Dealloc Layers and Context
  destroy(img.root)
  destroy(img.ctx)
  # Dealloc Image
  `=destroy`(img[])
  dealloc(img)

# ------------------
# Image Layer Basics
# ------------------

proc createLayer*(img: NImage, kind: NLayerKind): NLayer =
  result = createLayer(kind)
  # Register to Owner and Define Label
  if img.owner.register(addr result.code):
    let props = addr result.props
    case result.kind
    of lkColor16: props.label = "Layer " & $img.t0; inc(img.t0)
    of lkColor8: props.label = "Layer8 " & $img.t0; inc(img.t0)
    of lkMask: props.label = "Mask " & $img.t1; inc(img.t1)
    of lkFolder: props.label = "Folder " & $img.t2; inc(img.t2)

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
  img.target = layer

# -------------------------
# Image Layer Marking: Base
# -------------------------

proc markBase(img: NImage, layer: NLayer) =
  let status = addr img.status
  # Mark Color Layer
  case layer.kind
  of lkColor16, lkColor8:
    for tile in layer.tiles:
      status[].mark32(tile.x, tile.y)
  # Mark Folder Recursive
  of lkMask: discard
  of lkFolder:
    var la = layer.first
    # Walk Folder Childrens
    while not isNil(la):
      img.markBase(la)
      la = la.next

proc markClip(img: NImage, layer: NLayer) =
  var la = layer.prev
  # Mark Layer Clips
  while not isNil(la) and
    lpClipping in la.props.flags:
      img.markBase(la)
      la = la.prev

proc markScope(img: NImage, layer: NLayer) =
  var la = layer
  while not isNil(la) and
    lpClipping in la.props.flags:
      la = la.next
  if not isNil(la) and
    la.kind == lkMask:
      la = la.folder
  # Mark Layer Scope
  if not isNil(la):
    img.markBase(la)

# -------------------
# Image Layer Marking
# -------------------

proc markFolder(img: NImage, layer: NLayer) =
  let mode = layer.props.mode
  img.markBase(layer)
  # Mark Passthrough Clips
  if mode == bmPassthrough:
    img.markClip(layer)

proc markMask(img: NImage, layer: NLayer) =
  let mode = layer.props.mode
  # Mark Layer Mask
  if mode != bmStencil:
    let status = addr img.status
    for tile in layer.tiles:
      status[].mark32(tile.x, tile.y)
    img.markClip(layer)
  else: img.markScope(layer)

proc markLayer*(img: NImage, layer: NLayer) =
  case layer.kind
  of lkColor16, lkColor8:
    img.markBase(layer)
  of lkFolder: img.markFolder(layer)
  of lkMask: img.markMask(layer)

proc markSafe*(img: NImage, layer: NLayer) =
  let prev = layer.prev
  let next = layer.next
  let folder = layer.folder
  # Redundant Mark Checking
  let mode = layer.props.mode
  let special = layer.kind == lkMask
  let clipper = not isNil(prev) and
    lpClipping in prev.props.flags
  # Mark Folder if Special
  var scope = layer
  if special and not isNil(folder):
    scope = layer.folder
  elif clipper:
    if mode != bmPassthrough:
      img.markClip(scope)
    if not isNil(next):
      img.markLayer(next)
  # Check Redundant Marked
  let test = img.test
  if not isNil(test):
    var check = scope
    while not isNil(check):
      if check == test: return
      check = check.folder
  # Mark Current Layer
  img.markLayer(scope)
  img.test = scope

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
    if t0.status < tsBuffer:
      t1.data.color = t0.data.color
      continue
    # Copy Buffer Tile
    t1.toBuffer()
    copyMem(t1.data.buffer, 
      t0.data.buffer, t0.bytes * 2)

proc copyLayer*(img: NImage, layer: NLayer): NLayer =
  result = img.copyLayerBase(layer)
  # Copy Buffer Color Tiles
  if layer.kind != lkFolder:
    layer.copyTiles(result)
  elif layer.kind == lkFolder:
    var la0 = layer.last
    # Walk Layer Childrens
    while not isNil(la0):
      let la = img.copyLayer(la0)
      # Attach Created Layer
      result.attachInside(la)
      la0 = la0.prev

# ----------------------------
# Image Layer Merge: Composite
# ----------------------------

type
  NMergeProc = proc(m: ptr NImageMerge, src, dst: NTile): bool {.nimcall.}
  NMergeMaskProc = proc (co: ptr NMaskCombine) {.nimcall.}
  NImageMerge = object
    co: NImageComposite
    fn: NMergeProc
    # Combine Opacity
    alpha0: uint32
    alpha1: uint32

proc mergeRGBA(m: ptr NImageMerge, src, dst: NTile): bool =
  result = dst.status > tsZero or src.status > tsZero
  if not result: return result
  let coco = cast[ptr NImageCombine](addr m.co)
  m.co.src = m.co.dst
  combine_clear(coco)
  # Prepare Destination Pixels
  if dst.status > tsZero:
    var co = m.co
    co.src = dst.chunk()
    co.alpha = m.alpha1
    co.fn = blend_procs[bmNormal]
    co.clip = 0; blendChunk(addr co)
  # Combine Source Pixels
  if src.status > tsZero:
    m.co.src = src.chunk()
    m.co.alpha = m.alpha0
    blendChunk(addr m.co)

proc mergeMask(m: ptr NImageMerge, src, dst: NTile): bool =
  result = dst.status > tsZero or src.status > tsZero
  if not result: return result
  # Prepare Mask Merge
  var mo {.noinit.}: NMaskCombine
  mo.co.src = dst.chunk()
  mo.co.dst = m.co.dst
  mo.co.dst.bpp = dst.bpp
  # Prepare Destination Pixels
  if dst.status == tsColor:
    var co = combine(mo.co.src, m.co.ext)
    proxy_uniform_fill(addr co)
    mo.co.src = m.co.ext
  mo.alpha = m.alpha1
  combine_clear(addr mo.co)
  if dst.status > tsZero:
    combine_mask_union(addr mo)
  # Combine Source Pixels
  mo.co.src = src.chunk()
  if src.status == tsColor:
    var co = combine(mo.co.src, m.co.ext)
    proxy_uniform_fill(addr co)
    mo.co.src = m.co.ext
  mo.alpha = m.alpha0
  if src.status > tsZero:
    let fn = cast[NMergeMaskProc](m.co.fn)
    fn(addr mo)

proc mergePack(m: ptr NImageMerge, tile: var NTile) =
  var co {.noinit.}: NImageCombine
  co.src = m.co.dst
  if tile.bpp == 4:
    co.dst = co.src
    mipmap_pack8(addr co)
  # Prepare Tile Buffer
  tile.toBuffer()
  co.dst = tile.chunk()
  co.src.bpp = tile.bpp
  # Check Pixel Uniform
  proxy_uniform_stream(addr co)
  if co.dst.stride == co.dst.bpp:
    tile.toColor(co.dst.pixel)
  else: tile.mipmaps()

# --------------------------
# Image Layer Merge: Prepare
# --------------------------

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

proc mergePrepare(src, dst: NLayer): NImageMerge =
  let flags = src.props.flags - dst.props.flags
  let clip = lpClipping in flags
  let mode = src.props.mode
  # Configure Layer Blending
  result = default(NImageMerge)
  result.alpha0 = uint32(src.props.opacity * 65535.0)
  result.alpha1 = uint32(dst.props.opacity * 65535.0)
  let co = addr result.co
  co.fn = blend_procs[mode]
  co.clip = cast[cuint](clip)
  if clip: result.alpha1 = 65535
  # Configure Temporal Buffers
  let chunk = NImageBuffer(
    x: 32, y: 32,
    w: 32, h: 32,
    bpp: 8, stride: 256)
  co.dst = chunk; co.ext = chunk
  co.dst.buffer = alloc(chunk.stride * chunk.h)
  co.ext.buffer = alloc(chunk.stride * chunk.h)
  # Configure Layer Masking
  result.fn = mergeRGBA
  if src.kind == lkMask:
    co.clip = cast[cuint](mode == bmStencil)
    if dst.kind != lkMask:
      co.fn = composite_mask
      return
    # Mask-Mask Merge
    result.fn = mergeMask
    co.fn = if not clip:
      combine_mask_union
    else: combine_mask_exclude
    co.dst.bpp = 2
    co.ext.bpp = 2

# -----------------
# Image Layer Merge
# -----------------

proc mergeCheck(src, dst: NLayer): bool =
  let props0 = addr src.props
  let props1 = addr dst.props
  let clip0 = lpClipping in props0.flags
  let clip1 = lpClipping in props1.flags
  result = (src.kind != lkFolder and dst.kind != lkFolder) and
    (dst.kind != lkMask and (src.kind != lkMask or clip0))
  # Check Mask Blending
  if not result: result =
    (src.kind == lkMask and dst.kind == lkMask) and
    (props0.mode != bmStencil and props1.mode != bmStencil)
  result = result and (clip0 or not clip1)

proc mergeBase(img: NImage, src, dst: NLayer): NLayer =
  result = img.copyLayerBase(dst)
  # Prepare Layer Attributes
  if lpClipping notin src.props.flags:
    result.props.opacity = 1.0
  if src.kind == lkColor16:
    result.tiles = createTileImage(depth8bpp)
    result.kind = lkColor16

proc mergeLayer*(img: NImage, src, dst: NLayer): NLayer =
  result = default(NLayer)
  if not mergeCheck(src, dst):
    return result
  # Prepare Merge Layer
  let r = mergeRegion(src, dst)
  result = mergeBase(img, src, dst)
  result.tiles.ensure(r.x, r.y,
    r.w - r.x, r.h - r.y)
  # Perpare Merge Composite
  let g0 = addr src.tiles
  let g1 = addr dst.tiles
  let g2 = addr result.tiles
  var m = mergePrepare(src, dst)
  let co = addr m.co
  # Merge Layer Tiles
  for y in r.y ..< r.h:
    for x in r.x ..< r.w:
      var t0 = g0[].find(x, y)
      let t1 = g1[].find(x, y)
      # Locate Buffer Combine
      co.ext.x = x shl 5
      co.ext.y = y shl 5
      # Merge Layer Tile
      if m.fn(addr m, t0, t1):
        t0 = g2[].find(x, y)
        mergePack(addr m, t0)
  # Dealloc Temporal Buffers
  dealloc(co.dst.buffer)
  dealloc(co.ext.buffer)
  result.tiles.shrink()
