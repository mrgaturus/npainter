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
    buffer*: NImageMap
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
    map*: NImageMap
    mask*: NImageMap
    # Proxy Dispatch
    layer: NLayer
    w256, h128: cint
    blocks: seq[NProxyBlock]

# -----------------------
# Image Proxy Compositing
# -----------------------

proc blendProxy(state: ptr NCompositorState) =
  let 
    stream = cast[ptr NProxyStream](state.ext)
    src = chunk(stream.map.buffer)
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

iterator scan(p: ptr NProxyBlock): tuple[tx, ty: cint] =
  let x0 = p.x shl 3
  let y0 = p.y shl 2
  # Scan Dirty Bits
  var dirty = p.dirty
  for y in 0 ..< 4'i32:
    for x in 0 ..< 8'i32:
      # Check Dirty Bit
      if (dirty and 1) > 0:
        yield (x + x0, y + y0)
      # Next Dirty Bit
      dirty = dirty shr 1

proc stream(proxy: ptr NProxyBlock) =
  discard

proc commit(proxy: ptr NProxyBlock) =
  discard

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
