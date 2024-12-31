// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
#ifndef NPAINTER_IMAGE_H
#define NPAINTER_IMAGE_H
#include <smmintrin.h>

__attribute__((always_inline))
static inline __m128i _mm_mul_color32(__m128i a, __m128i b) {
  // Apply Alpha to Source
  a = _mm_mullo_epi32(a, b);
  a = _mm_add_epi32(a, b);
  a = _mm_srli_epi32(a, 16);

  return a;
}

__attribute__((always_inline))
static inline __m128i _mm_mul_color16(__m128i a, __m128i b) {
  __m128i xmm0 = _mm_mulhi_epu16(a, b);
  // Apply Alpha to Source
  a = _mm_or_si128(a, b);
  a = _mm_srli_epi16(a, 15);
  b = _mm_adds_epu16(xmm0, a);

  return b;
}

// --------------------
// Image Buffer Structs
// --------------------

typedef __m128i (*blend_proc_t)(__m128i, __m128i);

typedef struct {
  int x, y, w, h;
  // Buffer Properties
  int stride, bpp;
  unsigned char* buffer;
} image_buffer_t;

typedef struct {
  int x, y, w, h;
} image_clip_t;

typedef struct {
  image_buffer_t src;
  image_buffer_t dst;
} image_combine_t;

typedef struct {
  image_buffer_t src;
  image_buffer_t dst;
  image_buffer_t ext;
  // Blend Properties
  unsigned int alpha, clip;
  blend_proc_t fn;
  void* opaque;
} image_composite_t;

// --------------------------------
// Image Buffer Combine & Composite
// --------------------------------

// combine.c
void combine_intersect(image_combine_t* co);
void combine_clip(image_combine_t* co, image_clip_t clip);
void combine_clear(image_combine_t* co);
void combine_copy(image_combine_t* co);
void combine_pack(image_combine_t* co);

// composite.c
void composite_blend8(image_composite_t* co);
void composite_blend16(image_composite_t* co);
void composite_blend_uniform(image_composite_t* co);
void composite_fn8(image_composite_t* co);
void composite_fn16(image_composite_t* co);
void composite_fn_uniform(image_composite_t* co);

// mask.c
void composite_mask(image_composite_t* co);
void composite_mask_uniform(image_composite_t* co);
void composite_pass(image_composite_t* co);
void composite_passmask(image_composite_t* co);
void composite_passmask_uniform(image_composite_t* co);

// ------------------
// Image Buffer Proxy
// ------------------

// mipmap.c
void mipmap_pack8(image_combine_t* co);
void mipmap_pack2(image_combine_t* co);
void mipmap_reduce16(image_combine_t* co);
void mipmap_reduce8(image_combine_t* co);
void mipmap_reduce2(image_combine_t* co);

// proxy.c
void proxy_stream16(image_combine_t* co);
void proxy_stream8(image_combine_t* co);
void proxy_stream2(image_combine_t* co);
void proxy_uniform_fill(image_combine_t* co);
void proxy_uniform_check(image_combine_t* co);

// --------------------
// Image Buffer blend.c
// --------------------

__m128i blend_normal(__m128i src, __m128i dst);
extern const blend_proc_t blend_procs[];

#endif // NPAINTER_IMAGE_H
