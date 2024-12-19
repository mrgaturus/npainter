# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
import ffi, context, layer, tiles, composite, blend, chunk

type
  NProxyMode* = enum
    pmBlit
    pmBlend
    pmErase
    # Alpha Lock
    pmClipBlit
    pmClipBlend
  NProxyStream = object
    mode: NProxyMode
    # Image Mapping
    tiles: ptr NTileImage
    map: NImageMap
  NProxyBlock = object
    x, y: cshort
    dirty: uint32
    # Buffer Stream
    stream: ptr NProxyStream
  # Image Tile Proxy
  NImageRegion {.borrow.} =
    distinct NImageMap
  NImageProxy* = object
    ctx*: ptr NImageContext
    status*: ptr NImageStatus
    layer*: NLayer
    # Proxy Streaming
    map*: NImageRegion
    stream: NProxyStream
    # Proxy Dispatch
    w256, h128: cint
    blocks: seq[NProxyBlock]

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
  var i: cint
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

# -----------------------
# Image Proxy Compositing
# -----------------------

proc blendProxy(state: ptr NCompositorState) =
  let 
    stream = cast[ptr NProxyStream](state.ext)
    src = chunk(stream.map)
  # Blend Buffer to Scope
  state.blendBuffer(src)

proc proxy16proc(state: ptr NCompositorState) =
  case state.step.cmd
  of cmBlendLayer:
    state.blendProxy()
  # Blend Clipping
  of cmScopeClip:
    state.clearScope()
    state.blendProxy()
  # Blending Default
  else: state.blend16proc()

# ---------------------
# Image Proxy Preparing
# ---------------------

proc mapping(proxy: var NImageProxy, mode: NProxyMode) =
  let
    ctx = proxy.ctx
    layer = proxy.layer
  # Configure Context Mapping
  const bpp = sizeof(uint16) shl 2
  let map = ctx[].mapAux(bpp)
  # Configure Mapping Region
  proxy.map = NImageRegion(map)
  proxy.map.w = ctx.w
  proxy.map.h = ctx.h
  # Configure Stream
  proxy.stream.mode = mode
  proxy.stream.map = map
  proxy.stream.tiles = addr layer.tiles

proc prepare*(proxy: var NImageProxy, mode: NProxyMode) =
  let
    layer = proxy.layer
    status = proxy.status
  # Prepare Buffer Mapping
  proxy.mapping(mode)
  # Prepare Status Mark
  status[].prepare()
  status.clip = mark(0, 0, 0, 0)
  # Prepare Compositor Proc
  assert layer.kind != lkFolder
  layer.hook.fn = cast[NLayerProc](proxy16proc)
  layer.hook.ext = addr proxy.stream

proc mark*(proxy: var NImageProxy, x, y, w, h: cint) =
  let status = proxy.status
  # Apply Mark Region
  status[].mark(x, y, w, h)
  status.clip.expand(x, y, w, h)

# -------------------
# Image Proxy Marking
# -------------------

proc mark(proxy: var NImageProxy, tx, ty: cint) =
  let
    bw = proxy.w256
    bx = tx shr 3
    by = ty shr 2
    # Lookup Compositor Block
    b = addr proxy.blocks[by * bw + bx]
    # Dirty Position
    dx = tx and 0x7
    dy = ty and 0x3
    # Bit Position
    bit = 1 shl (dy shl 3 + dx)
  # Mark Block To Dispatch
  b.dirty = b.dirty or uint32(bit)

proc find(proxy: var NImageProxy, check, stage: uint8) =
  for c in proxy.status[].checkAux():
    if c.check[] == check:
      # Mark Block Dirty
      proxy.mark(c.tx, c.ty)
      c.check[] = stage

iterator scan(p: ptr NProxyBlock): tuple[tx, ty: cint] =
  let
    x0 = p.x shl 3
    y0 = p.y shl 2
  var dirty = p.dirty
  # Iterate Dirty Bits
  const l = int32(4)
  for y in 0 ..< l:
    for x in 0 ..< l + l:
      # Check Dirty Bit
      if (dirty and 1) > 0:
        yield (x + x0, y + y0)
      # Next Dirty Bit
      dirty = dirty shr 1

# ---------------------
# Image Proxy Streaming
# ---------------------

proc update(p: ptr NProxyBlock) =
  let
    stream = p.stream
    tiles = stream.tiles
    # Buffer Combine
    dst = chunk(stream.map)
    co0 = combine(dst, dst)
  # Stream Tiles to Proxy Buffer
  for tx, ty in p.scan():
    let tile = tiles[].find(tx, ty)
    # Prepare Combine Buffers
    var co = co0.clip32(tx, ty)
    if not tile.found:
      combine_clear(addr co)
      continue
    # Stream Tile to Proxy
    co.src = tile.chunk()
    if tile.uniform: proxy_fill(addr co)
    else: proxy_stream(addr co)
  # Remove Dirty
  p.dirty = 0

proc store(p: ptr NProxyBlock) =
  let
    stream = p.stream
    tiles = stream.tiles
    # Buffer Combine
    src = chunk(stream.map)
    co0 = combine(src, src)
  # Stream Tiles to Proxy Buffer
  for tx, ty in p.scan():
    var
      co = co0.clip32(tx, ty)
      tile = tiles[].find(tx, ty)
    # Check Tile Uniform
    proxy_uniform(addr co)
    # Convert to Buffer
    assert not isNil(tile.data)
    if co.src.bpp != co.src.stride:
      tile.toBuffer()
      co.dst = tile.chunk()
      # Stream to Buffer and Reduce
      proxy_stream(addr co)
      tile.mipmaps()
    # Convert to Uniform
    else:
      let color = cast[ptr uint64](co.src.buffer)[]
      tile.toColor(color)
  # Remove Dirty
  p.dirty = 0

# --------------------
# Image Proxy Dispatch
# --------------------

proc ensure(proxy: var NImageProxy) =
  let
    status = proxy.status
    tiles = proxy.stream.tiles
  # Status Clip Region
  var m = status.clip
  m = status[].scale(m)
  # Ensure Tile Region
  m.x1 -= m.x0; m.y1 -= m.y0
  tiles[].ensure(m.x0, m.y0, m.x1, m.y1)

# Instant TODO: multithreading
proc stream*(proxy: var NImageProxy) =
  proxy.find(check = 1, stage = 2)
  # Dispatch Update Blocks
  for p in mitems(proxy.blocks):
    if p.dirty > 0:
      update(addr p)

# Instant TODO: multithreading
proc commit*(proxy: var NImageProxy) =
  proxy.find(check = 2, stage = 0)
  proxy.ensure()
  # Dispatch Store Blocks
  for p in mitems(proxy.blocks):
    if p.dirty > 0:
      store(addr p)
  # Restore Compositor Proc
  proxy.layer.hook = default(NLayerHook)
