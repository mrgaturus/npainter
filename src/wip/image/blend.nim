# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
import ffi, context, composite, layer, tiles, chunk

# -------------------------
# Blending Compositor Dirty
# -------------------------

proc full*(state: ptr NCompositorState): bool {.inline.} =
  state.chunk.dirty == 0xFFFF and state.mipmap == 0

iterator scan*(state: ptr NCompositorState): tuple[tx, ty: cint] =
  var dirty = state.chunk.dirty
  # Iterate Dirty Bits
  const l = int32(4)
  for y in 0 ..< l:
    for x in 0 ..< l:
      # Check Dirty Bit
      if (dirty and 1) > 0:
        yield (x, y)
      # Next Dirty Bit
      dirty = dirty shr 1

# --------------------------
# Blending Compositor Chunks
# --------------------------

type
  NBlendCombine* {.union.} = object
    co0*: NImageCombine
    co1*: NImageComposite

proc blendCombine*(state: ptr NCompositorState): NBlendCombine =
  let
    co1 = addr result.co1
    # State Information
    props = addr state.layer.props
    scope = state.scope
    mode = props.mode
    # Accumulated Opacity
    alpha = props.opacity * scope.alpha1
  # Prepare Opacity, Clipping and Blending
  co1.alpha = cuint(alpha * 65535.0)
  co1.clip = cast[cuint](state.clip)
  co1.fn = blend_procs[mode]
  # Reset when Preparing Clipping
  if state.cmd == cmScopeClip:
    co1.alpha = 65535
    co1.fn = blend_normal

proc blendChunk*(co: ptr NImageComposite) =
  let uniform = co.src.stride == co.src.bpp
  # Basic Blending Equation
  if co.fn == blend_normal and co.clip == 0:
    if uniform: composite_blend_uniform(co)
    else: composite_blend(co)
  # Advanced Blending Equation
  elif uniform: composite_fn_uniform(co)
  else: composite_fn(co)

# -------------------------
# Blending Compositor Scope
# -------------------------

proc clearScope*(state: ptr NCompositorState) =
  let
    lod = state.mipmap
    dst = state.scope.buffer
    co0 = combine(dst, dst)
  # Clear all if is Fully Dirty
  if state.full():
    combine_clear(addr co0)
    return
  # Clear Buffer Tiles
  for tx, ty in state.scan():
    let co = co0.clip32(tx, ty, lod)
    combine_clear(addr co)

proc blendScope*(state: ptr NCompositorState) =
  let
    lod = state.mipmap
    src = state.scope.buffer
    dst = state.lower.buffer
    # Source to Destination
    co0 = combine(src, dst)
  var co = blendCombine(state)
  # Blend all if is Fully Dirty
  if state.full():
    co.co0 = co0
    blendChunk(addr co.co1)
    return
  # Blend Buffer Tiles
  for tx, ty in state.scan():
    co.co0 = co0.clip32(tx, ty, lod)
    blendChunk(addr co.co1)

proc packScope(state: ptr NCompositorState) =
  let 
    lod = state.mipmap
    ctx = state.chunk.com.ctx
    # Prepare Buffer Combine
    dst = ctx[].mapFlat(0).chunk()
    src = state.scope.buffer
    co0 = combine(src, dst)
  # Pack all if is fully dirty
  if state.full():
    combine_pack(addr co0)
    return
  # Pack Partially
  for tx, ty in state.scan():
    let co = co0.pack32(tx, ty, lod)
    combine_pack(addr co)

# --------------------------
# Blending Compositor Buffer
# --------------------------

proc blendRaw(state: ptr NCompositorState, src: NImageBuffer) =
  let
    dst = state.scope.buffer
    co0 = combine(src, dst)
  var co = blendCombine(state)
  # Blend all if is Fully Dirty
  if state.full():
    co.co0 = co0
    blendChunk(addr co.co1)
    return
  # Blend Buffer Tiles
  for tx, ty in state.scan():
    co.co0 = co0.clip32(tx, ty)
    blendChunk(addr co.co1)

proc blendBuffer*(state: ptr NCompositorState, src: NImageBuffer) =
  let lod = state.mipmap
  if lod == 0:
    state.blendRaw(src)
    return
  # LOD Blending
  let
    tmp = state.stack.pushBuffer()
    dst = state.scope.buffer
    # Combine Buffers
    ro0 = combine(src, tmp)
    co0 = combine(tmp, dst)
  var co = blendCombine(state)
  # Reduce and Blend Buffer Tiles
  for tx, ty in state.scan():
    var ro = ro0.clip32(tx, ty)
    combine_reduce(addr ro, lod)
    # Blend Reduced Tile
    co.co0 = co0.clip32(tx, ty, lod)
    blendChunk(addr co.co1)
  # Clear Temporal Buffer
  state.stack.popBuffer()

proc blendLayer*(state: ptr NCompositorState) =
  let
    lod = state.mipmap
    # Layer Objects
    layer = state.layer
    tiles = addr layer.tiles
    dst = state.scope.buffer
    # Layer Region Size
    tx0 = dst.x shr 5
    ty0 = dst.y shr 5
  # Layer Region Blending
  var co = blendCombine(state)
  # Blend Layer Tiles
  for tx, ty in state.scan():
    let tile = tiles[].find(tx + tx0, ty + ty0)
    if not tile.found: continue
    # Prepare Tile Chunk
    let chunk = tile.chunk(lod)
    co.co0 = combine(chunk, dst)
    # Blend Layer Chunk
    blendChunk(addr co.co1)

# -------------------------
# Blending Compositor Procs
# -------------------------

proc blend16proc*(state: ptr NCompositorState) =
  case state.cmd
  of cmBlendLayer:
    state.blendLayer()
  # Blend Scoping
  of cmBlendScope, cmBlendClip:
    state.blendScope()
  of cmScopeRoot, cmScopeImage:
    state.clearScope()
  # Blend Clipping
  of cmScopeClip:
    # Skip folder because has image already
    if state.layer.kind == lkFolder: return
    if state.scope.mode != bmPassthrough:
      state.clearScope()
    state.blendLayer()
  # Blend Discard
  else: discard

proc root16proc*(state: ptr NCompositorState) =
  case state.cmd
  of cmScopeRoot:
    state.clearScope()
  of cmBlendScope:
    state.packScope()
  # Blend Discard
  else: discard
