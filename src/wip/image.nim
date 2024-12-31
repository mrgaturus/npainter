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
    t0*, t1*, t2*: uint32
    owner*: NLayerOwner
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

proc mergeComposite(src, dst: NLayer): NImageComposite =
  let flags = src.props.flags - dst.props.flags
  let props = addr src.props
  var mode = props.mode
  # Configure Layer Blending
  result = default(NImageComposite)
  result.alpha = cuint(props.opacity * 65535.0)
  result.clip = cast[cuint](lpClipping in flags)
  result.fn = blend_procs[mode]
  # Configure Layer Blending: Mask
  if src.kind == lkMask:
    result.clip = cast[cuint](mode == bmStencil)
    result.fn = composite_mask
  # Configure Destination Auxiliar
  let tile = NTile(bpp: 8)
  var dst = tile.chunk()
  dst.stride = dst.bpp * dst.w
  dst.buffer = alloc(dst.stride * dst.h)
  result.ext = dst
  result.dst = dst

proc mergeTile(co: ptr NImageComposite, src, dst: NTile): bool =
  result =
    src.status >= tsColor or
    dst.status >= tsColor
  if not result: return result
  # Optimize Uniform Destination
  let check = src.status >= tsColor or
    (src.bpp == 2 and co.clip != 0)
  if dst.status == tsColor and not check:
    co.dst = co.ext
    co.dst.stride = co.dst.bpp
    # Copy Uniform Pixel to Data
    pixel(co.dst, dst.data.color)
    return result
  # Unpack Destination Pixels
  var c = combine(dst.chunk, co.ext)
  if dst.status < tsColor: combine_clear(addr c)
  elif dst.status == tsColor: proxy_uniform_fill(addr c)
  elif dst.bpp == 8: proxy_stream16(addr c)
  elif dst.bpp == 4: proxy_stream8(addr c)
  # Blend Source Pixels
  if not check: return
  co.dst = co.ext
  co.src = src.chunk()
  # Check Zero Pixel
  var zero {.align: 16.}: uint64 = 0
  if isNil(co.src.buffer):
    co.src.buffer = addr zero
  # Blend Source Pixel
  blendChunk(co)

proc packTile(co: ptr NImageComposite, tile: var NTile) =
  if co.dst.bpp == co.dst.stride:
    tile.toColor(co.dst.pixel)
    co.dst = co.ext
    return
  # Prepare Buffer Check
  var c = combine(co.ext, co.ext)
  c.dst.stride = tile.bpp * c.dst.w
  c.dst.bpp = tile.bpp
  # Pack Pixels and Check Uniform
  if tile.bpp == 4: mipmap_pack8(addr c)
  c.src = c.dst; proxy_uniform_check(addr c)
  if c.src.bpp == c.src.stride:
    tile.toColor(c.src.pixel)
    return
  # Copy Buffer to Tile
  tile.toBuffer()
  c.dst = tile.chunk()
  combine_copy(addr c)
  tile.mipmaps()

proc mergeLayer*(img: NImage, src, dst: NLayer): NLayer =
  result = default(NLayer)
  # Avoid Merge Invalid Cases
  let clip = lpClipping in src.props.flags
  if src.kind == lkFolder or
    (src.kind == lkMask and not clip) or
    dst.kind > lkColor8:
      return result
  # Create New Layer Base
  result = img.copyLayerBase(dst)
  if src.kind == lkColor16:
    dst.kind = lkColor16
  # Ensure Layer Tiles
  let r = mergeRegion(src, dst)
  result.tiles.ensure(r.x, r.y,
    r.w - r.x, r.h - r.y)
  # Perpare Merge Composite
  let g0 = addr src.tiles
  let g1 = addr dst.tiles
  let g2 = addr result.tiles
  var co = mergeComposite(src, dst)
  # Merge Layer Tiles
  for y in r.y ..< r.h:
    for x in r.x ..< r.w:
      var t0 = g0[].find(x, y)
      let t1 = g1[].find(x, y)
      # Locate Buffer Combine
      co.ext.x = x shl 5
      co.ext.y = y shl 5
      # Merge Layer Tile
      if mergeTile(addr co, t0, t1):
        t0 = g2[].find(x, y)
        packTile(addr co, t0)
  # Dealloc Temporal Buffer
  dealloc(co.ext.buffer)
  result.tiles.shrink()
