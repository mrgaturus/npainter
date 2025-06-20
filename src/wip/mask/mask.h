// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Cristian Camilo Ruiz <mrgaturus>
#ifndef NPAINTER_SHAPE_H
#define NPAINTER_SHAPE_H
#include "../image/image.h"

// ---------------------------------
// Combine Mask Blending: Operations
// ---------------------------------

__attribute__((always_inline))
static inline __m128i _mm_union_mask(__m128i src, __m128i dst) {
  __m128i xmm0 = _mm_mul_fix16(dst, src);
  xmm0 = _mm_subs_epu16(dst, xmm0);
  xmm0 = _mm_adds_epu16(src, xmm0);
  // SRC + (DST - DST * SRC)
  return xmm0;
}

__attribute__((always_inline))
static inline __m128i _mm_exclude_mask(__m128i src, __m128i dst) {
  __m128i xmm0 = _mm_mul_fix16(dst, src);
  xmm0 = _mm_subs_epu16(dst, xmm0);
  // DST - DST * SRC
  return xmm0;
}

__attribute__((always_inline))
static inline __m128i _mm_color_mask(__m128i src, __m128i dst) {
  __m128i xmm0, xmm1;

  // Apply Source Alpha to Destination
  xmm0 = _mm_shufflelo_epi16(src, 0xFF);
  xmm0 = _mm_shufflehi_epi16(xmm0, 0xFF);
  xmm1 = _mm_mul_fix16(dst, xmm0);
  // SRC + (DST - DST * A_SRC)
  xmm1 = _mm_subs_epu16(dst, xmm1);
  xmm1 = _mm_adds_epu16(src, xmm1);

  return xmm1;
}

// --------------------
// Shape Buffer Structs
// --------------------

typedef struct {
  int x0, x1;
  int offset, skip;
  int stride, pad;
  // Polygon Lane Buffers
  void *buffer, *smooth;
  unsigned char* cursor;
} polygon_line_t;

typedef enum {
  maskUnion,
  maskExclude,
  maskIntersect
} mask_mode_t;

typedef struct {
  image_combine_t co;
  unsigned long long color;
  unsigned long long alpha;
} mask_combine_t;

typedef struct {
  void* tiles[9];
  int ox, oy;
  // Vertex Output
  int log, count;
  unsigned short* buffer;
} mask_outline_t;

// Polygon Lane Location
void polygon_line_range(polygon_line_t* lane, int x0, int x1);
void polygon_line_skip(polygon_line_t* line, int y0);
void polygon_line_clear(polygon_line_t* lane);
void polygon_line_next(polygon_line_t* lane);
// Polygon Lane Rasterization
void polygon_line_simple(polygon_line_t* lane);
void polygon_line_coverage(polygon_line_t* lane);
void polygon_line_smooth(polygon_line_t* lane);

// Polygon Combine Mask: unpack.c
void polygon_mask_blit(mask_combine_t* co);
void polygon_mask_union(mask_combine_t* co);
void polygon_mask_exclude(mask_combine_t* co);
void polygon_mask_intersect(mask_combine_t* co);
// Polygon Combine Color: unpack.c
void polygon_color_blit16(mask_combine_t* co);
void polygon_color_blit8(mask_combine_t* co);
void polygon_color_blend16(mask_combine_t* co);
void polygon_color_blend8(mask_combine_t* co);
void polygon_color_erase16(mask_combine_t* co);
void polygon_color_erase8(mask_combine_t* co);

// Combine Mask Operations: mask.c
void combine_mask_union(mask_combine_t* co);
void combine_mask_exclude(mask_combine_t* co);
void combine_mask_intersect(mask_combine_t* co);
void combine_mask_invert(mask_combine_t* co);
void combine_mask_outline(mask_outline_t* co);
// Combine Color to Mask: mask.c
void convert_color16_mask(mask_combine_t* co);
void convert_color8_mask(mask_combine_t* co);
void convert_gray16_mask(mask_combine_t* co);
void convert_gray8_mask(mask_combine_t* co);
// Combine Mask to Color: mask.c
void convert_mask_color16(mask_combine_t* co);
void convert_mask_color8(mask_combine_t* co);
void convert_mask_blend16(mask_combine_t* co);
void convert_mask_blend8(mask_combine_t* co);
void convert_mask_erase16(mask_combine_t* co);
void convert_mask_erase8(mask_combine_t* co);
void convert_mask_clip16(mask_combine_t* co);
void convert_mask_clip8(mask_combine_t* co);

#endif // NPAINTER_SHAPE_H
