# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>

type
  NBlendMode* {.pure.} = enum
    bmNormal
    bmPassthrough
    bmMask, bmStencil
    # Darker
    bmMultiply
    bmDarken
    bmColorBurn
    bmLinearBurn
    bmDarkerColor
    # Light
    bmScreen
    bmLighten
    bmColorDodge
    bmLinearDodge
    bmLighterColor
    # Contrast
    bmOverlay
    bmSoftLight
    bmHardLight
    bmVividLight
    bmLinearLight
    bmPinLight
    bmHardMix
    # Compare
    bmDifference
    bmExclusion
    bmSubstract
    bmDivide
    # Composite
    bmHue
    bmSaturation
    bmColor
    bmLuminosity

# ---------------------
# image.h ffi importing
# ---------------------

{.compile: "blend.c".}
{.compile: "combine.c".}
{.compile: "composite.c".}
{.compile: "mask.c".}
{.compile: "mipmap.c".}
{.compile: "proxy.c".}
{.push header: "wip/image/image.h".}

type
  NBlendProc* {.importc: "blend_proc_t".} = pointer
  NImageBuffer* {.importc: "image_buffer_t".} = object
    x*, y*, w*, h*: cint
    # Buffer Properties
    stride*, bpp*: cint
    buffer*: pointer
  NImageClip* {.importc: "image_clip_t".} = object
    x*, y*, w*, h*: cint
  # -- Image Compositing --
  NImageCombine* {.importc: "image_combine_t".} = object
    dst*, src*: NImageBuffer
  NImageComposite* {.importc: "image_composite_t".} = object
    dst*, src*: NImageBuffer
    ext*: NImageBuffer
    # Combine Properties
    alpha*, clip*: cuint
    fn*: NBlendProc
    opaque*: pointer

{.push importc.}

# combine.c
proc combine_intersect*(co: ptr NImageCombine)
proc combine_clip*(co: ptr NImageCombine, clip: NImageClip)
proc combine_clear*(co: ptr NImageCombine)
proc combine_copy*(co: ptr NImageCombine)
proc combine_pack*(co: ptr NImageCombine)

# composite.c
proc composite_blend*(co: ptr NImageComposite)
proc composite_blend_uniform*(co: ptr NImageComposite)
proc composite_fn*(co: ptr NImageComposite)
proc composite_fn_uniform*(co: ptr NImageComposite)

# mask.c
proc composite_mask*(co: ptr NImageComposite)
proc composite_mask_uniform*(co: ptr NImageComposite)
proc composite_pass*(co: ptr NImageComposite)
proc composite_passmask*(co: ptr NImageComposite)
proc composite_passmask_uniform*(co: ptr NImageComposite)

# mipmap.c
proc mipmap_pack8*(co: ptr NImageCombine)
proc mipmap_pack2*(co: ptr NImageCombine)
proc mipmap_reduce16*(co: ptr NImageCombine)
proc mipmap_reduce8*(co: ptr NImageCombine)
proc mipmap_reduce2*(co: ptr NImageCombine)

# proxy.c
proc proxy_stream16*(co: ptr NImageCombine)
proc proxy_stream8*(co: ptr NImageCombine)
proc proxy_stream2*(co: ptr NImageCombine)
proc proxy_uniform_fill*(co: ptr NImageCombine)
proc proxy_uniform_check*(co: ptr NImageCombine)

{.pop.} # importc
{.pop.} # image.h

# ----------------------
# image.h ffi blend proc
# ----------------------

let blend_normal* {.nodecl, importc.}: NBlendProc
let blend_procs* {.nodecl, importc.}: 
  array[NBlendMode, NBlendProc]
