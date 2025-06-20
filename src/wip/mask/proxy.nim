# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2025 Cristian Camilo Ruiz <mrgaturus>
import ../image/[context, tiles, ffi, layer, composite, chunk, blend]
import nogui/async/core
import ffi, polygon
export NPolyRule
export NBlendMode

type
  NPolygonCombine {.byref.} = object
    pixel {.align: 16.}: uint64
    src: NImageBuffer
    dst: NImageBuffer
  NPolyMode* = enum
    modeMaskBlit
    modeMaskUnion
    modeMaskExclude
    modeMaskIntersect
    # Color Fill Mode
    modeColorBlend
    modeColorErase
  NPolygonProxy* = object
    ctx: ptr NImageContext
    status: ptr NImageStatus
    pool: NThreadPool
    # Polygon Buffers
    map: NImageBuffer
    mask: NImageBuffer
    rast: NPolygon
    layer: NLayer
    # Polygon Properties
    rule*: NPolyRule
    mode*: NPolyMode
    blend*: NBlendMode
    alpha*: uint64
    color*: uint64
    smooth*: bool
    lod*: int32
    lox: int32 # <- remove this when rework NImageStatus

proc clip32(co: var NPolygonCombine, x, y, lod: int32): NImageCombine =
  result = combine(co.dst, co.dst).clip32(x, y, lod)
  result.src = co.src
  let clip = NImageClip(
    x: (co.dst.x + x shl 5) shr lod,
    y: (co.dst.y + y shl 5) shr lod,
    # Clipping Dimensions
    w: result.dst.w,
    h: result.dst.h
  )
  # Check and Ensure 16-Byte Alignment
  buffer_clip(addr result.src, clip)
  var pixel = cast[ptr uint64](result.src.buffer)
  if (cast[uint64](pixel) and 0xF) != 0:
    result.src.buffer = addr co.pixel
    co.pixel = pixel[]

# -----------------------------------
# Polygon Proxy Composite: Color/Mask
# -----------------------------------

proc dstColor(state: ptr NCompositorState): NImageBuffer =
  let tiles = addr state.step.layer.tiles
  result = pushBuffer(state.stack)
  let lod = state.mipmap
  let tx0 = result.x shr 5
  let ty0 = result.y shr 5
  # Prepare Proxy Stream
  let proxy_stream = 
    case tiles.bits
    of depth0bpp: proxy_stream2
    of depth2bpp: proxy_stream2
    of depth4bpp: proxy_stream8
    of depth8bpp: proxy_stream16
  # Prepare Temporal Buffer
  for tx, ty in state.scan():
    let tile = tiles[].find(tx0 + tx, ty0 + ty)
    let src = tile.chunk(lod)
    var co = combine(src, result)
    # Copy Buffer Tile
    case tile.status
    of tsInvalid, tsZero: combine_clear(addr co)
    of tsColor: proxy_uniform_fill(addr co)
    of tsBuffer: proxy_stream(addr co)

proc srcColor(state: ptr NCompositorState): NImageBuffer =
  let proxy = cast[ptr NPolygonProxy](state.ext)
  result = pushBuffer(state.stack)
  let lod = state.mipmap
  result.w = result.w shr lod
  result.h = result.h shr lod
  let clip = NImageClip(
    x: result.x shr lod,
    y: result.y shr lod,
    w: result.w,
    h: result.h
  )
  # Prepare Unpack Polygon Mask
  var mc {.noinit.}: NMaskCombine
  mc.co.src = proxy.mask
  mc.co.dst = result
  mc.alpha = proxy.alpha
  mc.color = proxy.color
  # Prepare Unpack Polygon Clipping
  buffer_clip(addr mc.co.src, clip)
  copyMem(addr result, addr mc.co.src, sizeof NImageClip)
  mc.co.src.w = max(mc.co.src.w, 8)
  # Unpack Polygon Mask to Color
  if proxy.mode != modeColorBlend:
    result.bpp = sizeof(uint16) * 1
    polygon_mask_blit(addr mc)
  else: polygon_color_blit16(addr mc)

proc prepareColor(state: ptr NCompositorState): NImageBuffer =
  let proxy = cast[ptr NPolygonProxy](state.ext)
  var co {.noinit.}: NImageComposite
  var po {.noinit.}: NPolygonCombine
  po.src = srcColor(state)
  po.dst = dstColor(state)
  # Prepare Compositing
  co.alpha = 65535
  co.clip = 0 # TODO: alpha lock
  co.fn = blend_procs[proxy.blend]
  if proxy.mode != modeColorBlend:
    co.fn = composite_mask
  # Prepare Buffer
  let lod = state.mipmap
  for tx, ty in state.scan():
    let c = cast[ptr NImageCombine](addr co)
    c[] = po.clip32(tx, ty, lod)
    blendChunk(addr co)
  # Return Prepared Buffer
  return po.dst

# -----------------------------
# Polygon Proxy Composite: Hook
# -----------------------------

proc blendColor(state: ptr NCompositorState) =
  var raw = state.prepareColor()
  if state.step.cmd == cmBlendMask:
    var co0 = combine(raw, raw)
    # Pack Grayscale to Mask
    for tx, ty in state.scan():
      let co = co0.clip32(tx, ty)
      mipmap_pack2(addr co)
  # Blend and Remove Temporal Buffers
  state.blendRaw(raw)    
  popBuffer(state.stack)
  popBuffer(state.stack)

proc proxy16proc(state: ptr NCompositorState) =
  let step = state.step
  case step.cmd
  of cmBlendLayer, cmBlendMask:
    state.blendColor()
  # Blend Clipping
  of cmScopeClip, cmScopeMask:
    if step.layer.kind != lkMask:
      state.clearScope()
    else: state.copyScope()
    # Blend Proxy Buffer
    state.blendColor()
  else: state.blend16proc()

# ----------------------------------
# Polygon Proxy Composite: Configure
# ----------------------------------

proc configure*(proxy: var NPolygonProxy,
    ctx: ptr NImageContext,
    status: ptr NImageStatus,
    pool: NThreadPool) =
  proxy.ctx = ctx
  proxy.status = status
  proxy.pool = pool

proc prepare*(proxy: var NPolygonProxy, layer: NLayer) =
  layer.hook.fn = cast[NLayerProc](proxy16proc)
  layer.hook.ext = addr proxy
  proxy.layer = layer
  echo "hooked layer: ", layer.props.label
  # Prepare Proxy Buffer
  proxy.map = proxy.ctx[].mapAux(1)
  proxy.rast.configure(proxy.pool, proxy.map)
  proxy.rast.clear()

# ----------------------------------
# Polygon Proxy Composite: Rasterize
# ----------------------------------

proc mark(proxy: var NPolygonProxy) =
  let mask = addr proxy.mask
  if mask.w == 0 or mask.h == 0: return
  # Mark Proxy Position
  let lod = proxy.lox
  let m = mark(
    mask.x shl lod,
    mask.y shl lod,
    mask.w shl lod,
    mask.h shl lod)
  # XXX: get rid of this
  proxy.status.clip.expand(m.x0, m.y0,
    m.x1 - m.x0, m.y1 - m.y0)
  proxy.status[].mark(m)

proc push*(proxy: var NPolygonProxy, x, y: float32) =
  let scale = 1.0 / float32(1 shl proxy.lod)
  proxy.rast.push NPolyPoint(
    x: x * scale, y: y * scale)

proc rasterize*(proxy: var NPolygonProxy) =
  let rast = addr proxy.rast
  rast.rule = proxy.rule
  rast.smooth = proxy.smooth
  proxy.status.clip = default(NImageMark)
  # Dispatch Rasterizer
  proxy.mark() # Mark Prev
  proxy.mask = rast[].rasterize()
  proxy.lox = proxy.lod
  proxy.mark() # Mark Next
  rast[].clear()

# -------------------------------
# Polygon Proxy Composite: Commit
# -------------------------------

# IMPORTANT TODO: multithreading
proc commit*(proxy: var NPolygonProxy) =
  let mask = proxy.mask
  # Clear Buffer Auxiliar and Layer Hook
  proxy.layer.hook = default(NLayerHook)
  proxy.ctx[].clearAux()
  # Remove Mappings
  wasMoved(proxy.map)
  wasMoved(proxy.mask)
  wasMoved(proxy.layer)
