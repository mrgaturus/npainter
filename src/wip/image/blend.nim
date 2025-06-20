# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
import ffi, context, composite, layer, tiles, chunk

type
  NBlendCombine* {.pure, union.} = object
    co0*: NImageCombine
    co1*: NImageComposite

proc full*(state: ptr NCompositorState): bool {.inline.} =
  state.mipmap == 0 and state.chunk.dirty == 0xFFFF

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

# ---------------------------
# Blending Compositor Prepare
# ---------------------------

proc blendCombine*(state: ptr NCompositorState): NBlendCombine =
  result = default(NBlendCombine)
  let step = state.step
  let co = addr result.co1
  # Prepare Props
  let mode = step.mode
  let alpha = uint32(step.alpha)
  # Prepare Opacity, Clipping and Blending
  co.alpha = (alpha shl 8) or alpha
  co.clip = cast[cuint](step.clip)
  co.fn = blend_procs[mode]
  # Special Blending Modes
  case step.cmd
  of cmScopeClip, cmScopeMask:
    co.alpha = 65535
    if mode notin {bmMask, bmStencil}:
      co.fn = blend_normal
      return
    # Mask Scoping Function
    co.clip = cast[cuint](mode == bmStencil)
    co.fn = composite_mask
  of cmBlendMask:
    const pass = {bmPassthrough, bmMask, bmStencil}
    co.clip = cast[cuint](mode == bmStencil)
    # Mask Blending to Passthrough
    if state.scope.step.mode in pass:
      co.opaque = addr state.lower.buffer
      co.fn = composite_passmask
    else: co.fn = composite_mask
  else: co.fn = blend_procs[mode]

proc blendChunk*(co: ptr NImageComposite) =
  let bpp = co.src.bpp
  let uniform = co.src.stride == bpp
  # Dispatch Normal Blending
  if co.fn == blend_normal and co.clip == 0:
    if uniform: composite_blend_uniform(co)
    elif bpp == 8: composite_blend16(co)
    elif bpp == 4: composite_blend8(co)
  # Masking Blending Equation
  elif co.fn == composite_mask:
    if uniform: composite_mask_uniform(co)
    else: composite_mask(co)
  elif co.fn == composite_passmask:
    let ext = cast[ptr NImageBuffer](co.opaque)
    co.ext = combine(co.dst, ext[]).dst
    # Dispatch Passthrough Masking
    if uniform: composite_passmask_uniform(co)
    else: composite_passmask(co)
  # Advanced Blending Equation
  elif uniform: composite_fn_uniform(co)
  elif bpp == 8: composite_fn16(co)
  elif bpp == 4: composite_fn8(co)

# -------------------------
# Blending Compositor Scope
# -------------------------

proc clearScope*(state: ptr NCompositorState) =
  let
    lod = state.mipmap
    dst = state.scope.buffer
    co0 = combine(dst, dst)
  # Clear Full Scope
  if state.full():
    combine_clear(addr co0)
    return
  # Clear Partial Buffer Tiles
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
  # Blend Full Scope
  if state.full():
    co.co0 = co0
    blendChunk(addr co.co1)
    return
  # Blend Partial Buffer Tiles
  for tx, ty in state.scan():
    co.co0 = co0.clip32(tx, ty, lod)
    blendChunk(addr co.co1)

proc packScope(state: ptr NCompositorState) =
  let 
    lod = state.mipmap
    src = state.scope.buffer
  # Configure Buffer Combine
  let ctx = cast[ptr NImageContext](state.ext)
  var dst = ctx[].mapFlat(lod)
  dst.w = dst.w shl lod
  dst.h = dst.h shl lod
  var co0 = combine(src, dst)
  # Pack all if is fully dirty
  if state.full():
    combine_pack(addr co0)
    return
  # Pack Partially
  for tx, ty in state.scan():
    var co = co0.pack32(tx, ty, lod)
    combine_pack(addr co)

# --------------------------
# Blending Compositor Buffer
# --------------------------

proc blendRaw*(state: ptr NCompositorState, src: NImageBuffer) =
  let
    lod = state.mipmap
    dst = state.scope.buffer
    co0 = combine(src, dst)
  var co = blendCombine(state)
  # Blend Fully Dirty
  if state.full():
    co.co0 = co0
    blendChunk(addr co.co1)
    return
  # Blend Partial Buffer Tiles
  for tx, ty in state.scan():
    co.co0 = co0.clip32(tx, ty, lod)
    blendChunk(addr co.co1)

proc blendLayer*(state: ptr NCompositorState) =
  let
    lod = state.mipmap
    # Layer Objects
    layer = state.step.layer
    mode = state.step.mode
    tiles = addr layer.tiles
    dst = state.scope.buffer
    # Layer Region Size
    tx0 = dst.x shr 5
    ty0 = dst.y shr 5
  # Layer Region Blending
  var zero = default(NTileCell)
  var co = blendCombine(state)
  # Blend Layer Tiles
  for tx, ty in state.scan():
    var tile = tiles[].find(tx + tx0, ty + ty0)
    if tile.status < tsColor:
      if mode != bmStencil:
        continue
      # Zero Fill for Stencil
      tile.status = tsZero
      tile.data = addr zero
    # Prepare Tile Chunk
    let chunk = tile.chunk(lod)
    co.co0 = combine(chunk, dst)
    # Blend Layer Chunk
    blendChunk(addr co.co1)

# -------------------------------
# Blending Compositor Passthrough
# -------------------------------

proc copyScope*(state: ptr NCompositorState) =
  let
    lod = state.mipmap
    src = state.lower.buffer
    dst = state.scope.buffer
    co0 = combine(src, dst)
  # Copy Full Scope
  if state.full():
    combine_copy(addr co0)
    return
  # Copy Partial Buffer Tiles
  for tx, ty in state.scan():
    let co = co0.clip32(tx, ty, lod)
    combine_copy(addr co)

proc passScope*(state: ptr NCompositorState) =
  let
    lod = state.mipmap
    src = state.scope
    dst = state.lower
  # Optimize Passthrough Copy
  let alpha: uint32 = state.step.alpha
  if alpha == 255:
    state.scope = dst
    state.lower = src
    state.copyScope()
    state.scope = src
    state.lower = dst
    return
  # Prepare Layer Passthrough
  var co = default(NBlendCombine)
  co.co1.alpha = (alpha shl 8) or alpha
  let co0 = combine(src.buffer, dst.buffer)
  # Passthrough All When Full
  if state.full():
    co.co0 = co0
    composite_pass(addr co.co1)
    return
  # Passthrough Buffer Tiles
  for tx, ty in state.scan():
    co.co0 = co0.clip32(tx, ty, lod)
    composite_pass(addr co.co1)

# -------------------------
# Blending Compositor Procs
# -------------------------

proc blend16proc*(state: ptr NCompositorState) =
  const pass = {bmPassthrough, bmMask, bmStencil}
  let step = state.step
  # Dispatch Layer Blending
  case step.cmd
  of cmBlendDiscard: discard
  of cmBlendLayer, cmBlendMask:
    state.blendLayer()
  of cmBlendScope:
    if step.mode notin pass:
      state.blendScope()
    else: state.passScope()
  # Blending Compositor Scope
  of cmScopeImage: state.clearScope()
  of cmScopePass: state.copyScope()
  of cmScopeClip, cmScopeMask:
    case step.layer.kind
    of lkColor16, lkColor8:
      state.clearScope()
    of lkMask: state.copyScope()
    of lkFolder: return
    # Blend Layer to Scope
    state.blendLayer()

proc root16proc*(state: ptr NCompositorState) =
  case state.step.cmd
  of cmBlendScope: state.packScope()
  of cmScopeImage: state.clearScope()
  else: discard
