// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
#ifndef NPAINTER_IMAGE_H
#define NPAINTER_IMAGE_H
#include <smmintrin.h>

static inline __m128i _mm_multiply_color(__m128i a, __m128i b) {
  // Apply Alpha to Source
  a = _mm_mullo_epi32(a, b);
  a = _mm_add_epi32(a, b);
  a = _mm_srli_epi32(a, 16);

  return a;
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
  // Blend Properties
  unsigned int alpha, clip;
  blend_proc_t fn;
} image_composite_t;

// ------------------------------------
// Image Buffer combine.c + composite.c
// ------------------------------------

// combine.c
void combine_intersect(image_combine_t* co);
void combine_clip(image_combine_t* co, image_clip_t clip);
void combine_clear(image_combine_t* co);
void combine_pack(image_combine_t* co);

// composite.c
void composite_blend(image_composite_t* co);
void composite_blend_uniform(image_composite_t* co);
void composite_fn(image_composite_t* co);
void composite_fn_uniform(image_composite_t* co);

// -------------------------------
// Image Buffer mipmap.c + proxy.c
// -------------------------------

// mipmap.c
void mipmap_reduce(image_combine_t* co);

// proxy.c
void proxy_stream(image_combine_t* co);
void proxy_fill(image_combine_t* co);
void proxy_uniform(image_combine_t* co);

// --------------------
// Image Buffer blend.c
// --------------------

__m128i blend_normal(__m128i src, __m128i dst);
extern const blend_proc_t blend_procs[];

#endif // NPAINTER_IMAGE_H
