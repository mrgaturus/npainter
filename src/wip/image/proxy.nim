# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
import ffi, context, layer, tiles, composite, blend, chunk

type
  NProxyMode* = enum
    pmErase
    pmBlit
    pmBlend
    # Alpha Lock
    pmClipBlit
    pmClipBlend
  # Proxy Streaming
  NProxyMap = object
    tiles*: ptr NTileImage
    buffer*: NImageBuffer
  NProxyStream = object
    mode*: NProxyMode
    fn*: NBlendMode
    # Stream Mapping
    map*: NProxyMap
    mask*: NProxyMap
  # Proxy Dispatch
  NProxyBlock = object
    stream: ptr NProxyStream
    # Block 256x128
    dirty: uint32
    x, y: int16
  NImageProxy* = object
    ctx*: ptr NImageContext
    status*: ptr NImageStatus
    stream*: NProxyStream
    # Image Mapping
    map*: NImageBuffer
    mask*: NImageBuffer
    # Proxy Dispatch
    layer: NLayer
    w256, h128: cint
    blocks: seq[NProxyBlock]

# -----------------------
# Image Proxy Compositing
# -----------------------

proc blendPack(state: ptr NCompositorState, tmp: var NImageBuffer) =
  let stream = cast[ptr NProxyStream](state.ext)
  let map = stream.map
  let lod = state.mipmap
  let bits = map.tiles.bits
  # Prepare Buffer Combine
  if bits == depth2bpp:
    tmp.bpp = map.tiles.bpp
    tmp.stride = tmp.w * tmp.bpp
  # Pack Buffer Tiles
  let src = map.buffer
  let co0 = combine(src, tmp)
  for tx, ty in state.scan():
    var co = co0.clip32(tx, ty)
    # Pack Tile Buffer
    if bits == depth2bpp:
      mipmap_pack2(addr co)
      co.src = co.dst
    combine_reduce(addr co, lod)

proc blendProxy(state: ptr NCompositorState) =
  let stream = cast[ptr NProxyStream](state.ext)
  let map = stream.map
  let src = map.buffer
  # Blend Buffer to Scope
  let lod = state.mipmap
  if map.tiles.bits > depth2bpp and lod == 0:
    state.blendRaw(src)
    return
  # Pack Buffer and Blend
  let stack = addr state.stack
  var tmp = stack[].pushBuffer()
  state.blendPack(tmp)
  state.blendRaw(tmp)
  stack[].popBuffer()

proc proxy16proc(state: ptr NCompositorState) =
  let step = state.step
  case step.cmd
  of cmBlendLayer, cmBlendMask:
    state.blendProxy()
  # Blend Clipping
  of cmScopeClip, cmScopeMask:
    if step.layer.kind != lkMask:
      state.clearScope()
    else: state.copyScope()
    # Blend Proxy Buffer
    state.blendProxy()
  else: state.blend16proc()

# ---------------------
# Image Proxy Configure
# ---------------------

proc configure*(proxy: var NImageProxy) =
  let
    ctx = proxy.ctx
    stream = addr proxy.stream
    # Proxy Blocks Size
    w256 = (ctx.w32 + 0xFF) shr 8
    h128 = (ctx.h32 + 0x7F) shr 7
    l = w256 * h128
  # Initialize Proxy Blocks
  setLen(proxy.blocks, l)
  # Locate Proxy Blocks
  var i: uint = 0
  for y in 0 ..< h128:
    for x in 0 ..< w256:
      let b = addr proxy.blocks[i]
      b.stream = stream
      # Locate Block
      b.x = cshort(x)
      b.y = cshort(y)
      # Next Block
      inc(i)
  # Store Size
  proxy.w256 = w256
  proxy.h128 = h128

proc prepareBuffer(proxy: var NImageProxy, layer: NLayer) =
  let ctx = proxy.ctx
  const bpp = sizeof(uint16) * 4
  let map = ctx[].mapAux(bpp)
  # Configure Buffer
  proxy.map = map
  proxy.map.w = ctx.w
  proxy.map.h = ctx.h
  # Configure Stream Buffer
  proxy.stream.mode = pmBlit
  proxy.stream.fn = bmNormal
  proxy.stream.map.buffer = map
  proxy.stream.map.tiles = addr layer.tiles

proc prepare*(proxy: var NImageProxy, layer: NLayer) =
  assert isNil(proxy.layer)
  assert layer.kind != lkFolder
  # Prepare Proxy
  proxy.prepareBuffer(layer)
  proxy.status[].prepare()
  proxy.status[].clip = mark(0, 0, 0, 0)
  # Prepare Compositor Proc
  layer.hook.fn = cast[NLayerProc](proxy16proc)
  layer.hook.ext = addr proxy.stream
  proxy.layer = layer
  echo "prepared layer: ", layer.kind
  echo "prepared bpp: ", layer.tiles.bits

proc mark*(proxy: var NImageProxy, x, y, w, h: cint) =
  let status = proxy.status
  # Apply Mark Region
  status[].mark(x, y, w, h)
  status[].clip.expand(x, y, w, h)

# --------------------------
# Image Proxy Dispatch: Mark
# --------------------------

proc mark(proxy: var NImageProxy, tx, ty: cint) =
  let
    bw = proxy.w256
    bx = tx shr 3
    by = ty shr 2
    # Dirty Position
    dx = tx and 0x7
    dy = ty and 0x3
    bit = 1 shl (dy shl 3 + dx)
  # Mark Block Bit To Dispatch
  let b = addr proxy.blocks[by * bw + bx]
  b.dirty = b.dirty or cast[uint32](bit)

proc find(proxy: var NImageProxy, check, stage: uint8) =
  for c in proxy.status[].checkAux():
    if c.check[] == check:
      # Mark Block Dirty
      proxy.mark(c.tx, c.ty)
      c.check[] = stage

proc ensure(proxy: var NImageProxy) =
  let tiles = proxy.stream.map.tiles
  let status = proxy.status
  # Status Clip Region
  var m = status.clip
  m = status[].scale(m)
  # Ensure Tile Region
  tiles[].ensure(m.x0, m.y0,
    m.x1 - m.x0, m.y1 - m.y0)

# ----------------------------
# Image Proxy Dispatch: Blocks
# ----------------------------

iterator scan(proxy: ptr NProxyBlock): tuple[tx, ty: cint] =
  let x0 = proxy.x shl 3
  let y0 = proxy.y shl 2
  # Scan Dirty Bits
  var dirty = proxy.dirty
  for y in 0 ..< 4'i32:
    for x in 0 ..< 8'i32:
      # Check Dirty Bit
      if (dirty and 1) > 0:
        yield (x + x0, y + y0)
      # Next Dirty Bit
      dirty = dirty shr 1

proc stream(proxy: ptr NProxyBlock) =
  let
    stream = proxy.stream
    map = stream.map
    tiles = map.tiles
    # Buffer Combine
    dst = map.buffer
    co0 = combine(dst, dst)
  # Select Proxy Stream
  let proxy_stream =
    case tiles.bits
    of depth2bpp: proxy_stream2
    of depth4bpp: proxy_stream8
    else: proxy_stream16
  # Stream Tiles to Proxy Buffer
  for tx, ty in proxy.scan():
    let tile = tiles[].find(tx, ty)
    # Prepare Combine Buffers
    var co = co0.clip32(tx, ty)
    if tile.status < tsColor:
      combine_clear(addr co)
      continue
    # Stream Tile to Proxy
    co.src = tile.chunk()
    if tile.status == tsColor:
      proxy_uniform_fill(addr co)
    else: proxy_stream(addr co)
  # Remove Dirty Mark
  wasMoved(proxy.dirty)

proc commit(proxy: ptr NProxyBlock) =
  let
    stream = proxy.stream
    map = stream.map
    tiles = map.tiles
    # Buffer Combine
    src = map.buffer
    co0 = combine(src, src)
  # Decide Pack Function
  let mipmap_pack =
    case tiles.bits
    of depth2bpp: mipmap_pack2
    of depth4bpp: mipmap_pack8
    else: combine_copy
  # Stream Tiles to Proxy Buffer
  for tx, ty in proxy.scan():
    var co = co0.clip32(tx, ty)
    var tile = tiles[].find(tx, ty)
    assert not isNil(tile.data)
    # Pack Tile 16bit to Depth
    if mipmap_pack != combine_copy:
      co.dst.bpp = tiles.bpp
      mipmap_pack(addr co)
      co.src = co.dst
    # Check Tile Uniform
    proxy_uniform_check(addr co)
    if co.src.bpp == co.src.stride:
      tile.toColor(co.src.pixel)
      continue
    # Stream and Reduce
    tile.toBuffer()
    co.dst = tile.chunk()
    combine_copy(addr co)
    tile.mipmaps()
  # Remove Dirty Mark
  wasMoved(proxy.dirty)

# --------------------
# Image Proxy Dispatch
# --------------------

# IMPORTANT TODO: multithreading
proc stream*(proxy: var NImageProxy) =
  proxy.find(check = 1, stage = 2)
  # Dispatch Update Blocks
  for p in mitems(proxy.blocks):
    if p.dirty > 0:
      stream(addr p)

# IMPORTANT TODO: multithreading
proc commit*(proxy: var NImageProxy) =
  proxy.find(check = 2, stage = 0)
  proxy.ensure()
  # Dispatch Store Blocks
  for p in mitems(proxy.blocks):
    if p.dirty > 0:
      commit(addr p)
  # Restore Compositor Proc
  proxy.layer.hook = default(NLayerHook)
  proxy.stream = default(NProxyStream)
  proxy.ctx[].clearAux()
  # Remove Mappings
  wasMoved(proxy.map)
  wasMoved(proxy.mask)
  wasMoved(proxy.layer)
