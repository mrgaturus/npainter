// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
#include "canvas.h"

static inline __m128i canvas_pixel_white(__m128i src) {
  const __m128i alphas = _mm_set_epi32(
    0xF0F0F0F, 0xB0B0B0B, 0x7070707, 0x3030303);
  const __m128i ones = _mm_cmpeq_epi32(alphas, alphas);

  __m128i xmm0;
  // Blend With White Pixel
  xmm0 = _mm_shuffle_epi8(src, alphas);
  xmm0 = _mm_subs_epi8(ones, xmm0);
  src = _mm_adds_epi8(src, xmm0);

  // Return Blended Source
  return src;
}

static inline __m128i canvas_pixel_blend(__m128i src, __m128i dst) {
  __m128i alpha0, alpha1;
  __m128i xmm0, xmm1, xmm2, xmm3;
  // Unpack Pixels to 16bit
  xmm0 = _mm_unpacklo_epi8(src, src);
  xmm1 = _mm_unpacklo_epi8(dst, dst);
  xmm2 = _mm_unpackhi_epi8(src, src);
  xmm3 = _mm_unpackhi_epi8(dst, dst);
  // Shuffle 16bit Opacity
  alpha0 = _mm_shufflelo_epi16(xmm0, 0xFF);
  alpha1 = _mm_shufflelo_epi16(xmm2, 0xFF);
  alpha0 = _mm_shufflehi_epi16(alpha0, 0xFF);
  alpha1 = _mm_shufflehi_epi16(alpha1, 0xFF);
  // s + d - d * sa
  alpha0 = _mm_mulhi_epu16(alpha0, xmm1);
  alpha1 = _mm_mulhi_epu16(alpha1, xmm3);
  xmm1 = _mm_subs_epu16(xmm1, alpha0);
  xmm3 = _mm_subs_epu16(xmm3, alpha1);
  xmm0 = _mm_adds_epu16(xmm0, xmm1);
  xmm2 = _mm_adds_epu16(xmm2, xmm3);

  // Pack Pixels to 8 Bit
  xmm0 = _mm_srli_epi16(xmm0, 8);
  xmm2 = _mm_srli_epi16(xmm2, 8);
  return _mm_packus_epi16(xmm0, xmm2);
}

// ---------------------------------
// Canvas Stream + Simple Background
// ---------------------------------

void canvas_copy_white(canvas_copy_t* copy) {
  int x0, y0, x1, y1;
  // Locate Copy Region
  x0 = (copy->x256 << 8) + copy->x;
  y0 = (copy->y256 << 8) + copy->y;
  x1 = x0 + copy->w;
  y1 = y0 + copy->h;
  // Copy Source Buffer
  canvas_src_t* src0 = copy->src;
  canvas_src_clamp(src0, &x1, &y1);

  int s_src, s_dst;
  unsigned char *src, *src_y;
  unsigned char *dst, *dst_y;
  // Copy Strides
  s_src = src0->s0;
  s_dst = copy->w << 2;
  // Copy Buffer Pointers
  src_y = src0->buffer;
  dst_y = copy->buffer;
  src_y += y0 * s_src + (x0 << 2);

  // SIMD Registers
  __m128i xmm0, xmm1, xmm2, xmm3;

  for (int y = y0; y < y1; y++) {
    src = src_y;
    dst = dst_y;
    // Lane Count
    int count = x1 - x0;

    while (count > 0) {
      xmm0 = _mm_load_si128((__m128i*) src);
      xmm1 = _mm_load_si128((__m128i*) src + 1);
      xmm2 = _mm_load_si128((__m128i*) src + 2);
      xmm3 = _mm_load_si128((__m128i*) src + 3);
      // Blend to White Pixel
      xmm0 = canvas_pixel_white(xmm0);
      xmm1 = canvas_pixel_white(xmm1);
      xmm2 = canvas_pixel_white(xmm2);
      xmm3 = canvas_pixel_white(xmm3);
      // Stream to PBO Buffer
      _mm_stream_si128((__m128i*) dst, xmm0);
      _mm_stream_si128((__m128i*) dst + 1, xmm1);
      _mm_stream_si128((__m128i*) dst + 2, xmm2);
      _mm_stream_si128((__m128i*) dst + 3, xmm3);

      // Next Pixels
      count -= 16;
      src += 64;
      dst += 64;
    }

    // Next Lane
    src_y += s_src;
    dst_y += s_dst;
  }
}

void canvas_copy_color(canvas_copy_t* copy) {
  int x0, y0, x1, y1;
  // Locate Copy Region
  x0 = (copy->x256 << 8) + copy->x;
  y0 = (copy->y256 << 8) + copy->y;
  x1 = x0 + copy->w;
  y1 = y0 + copy->h;
  // Copy Source Buffer
  canvas_src_t* src0 = copy->src;
  canvas_src_clamp(src0, &x1, &y1);

  int s_src, s_dst;
  unsigned char *src, *src_y;
  unsigned char *dst, *dst_y;
  // Copy Strides
  s_src = src0->s0;
  s_dst = copy->w << 2;
  // Copy Buffer Pointers
  src_y = src0->buffer;
  dst_y = copy->buffer;
  src_y += y0 * s_src + (x0 << 2);

  // SIMD Registers
  __m128i xmm0, xmm1, color;
  // Prepare Solid Color Background
  color = _mm_loadu_si32(&copy->bg->color0);
  color = _mm_shuffle_epi32(color, 0);

  for (int y = y0; y < y1; y++) {
    src = src_y;
    dst = dst_y;
    // Lane Count
    int count = x1 - x0;

    while (count > 0) {
      xmm0 = _mm_load_si128((__m128i*) src);
      xmm1 = _mm_load_si128((__m128i*) src + 1);
      // Blend to White Pixel
      xmm0 = canvas_pixel_blend(xmm0, color);
      xmm1 = canvas_pixel_blend(xmm1, color);
      // Stream to PBO Buffer
      _mm_stream_si128((__m128i*) dst, xmm0);
      _mm_stream_si128((__m128i*) dst + 1, xmm1);

      // Next Pixels
      count -= 8;
      src += 32;
      dst += 32;
    }

    // Next Lane
    src_y += s_src;
    dst_y += s_dst;
  }
}

// ----------------------------------
// Canvas Stream + Pattern Background
// ----------------------------------

void canvas_gen_checker(canvas_bg_t* bg) {
  int shift = bg->shift;
  int size = 2 << shift;
  int mask = 1 << shift;
  // Checker Colors
  unsigned int color0 = bg->color0;
  unsigned int color1 = bg->color1;
  // Checker Buffer
  unsigned int* buffer = bg->buffer;

  // Fill Checker Pattern
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      // Decide Fill Color
      int check = (x & mask) ^ (y & mask);
      *(buffer) = check ? color0 : color1;
      // Next Pixel
      buffer++;
    }
  }
}

void canvas_copy_checker(canvas_copy_t* copy) {
  int x0, y0, x1, y1;
  // Locate Copy Region
  x0 = (copy->x256 << 8) + copy->x;
  y0 = (copy->y256 << 8) + copy->y;
  x1 = x0 + copy->w;
  y1 = y0 + copy->h;
  // Copy Source Buffer
  canvas_src_t* src0 = copy->src;
  canvas_src_clamp(src0, &x1, &y1);
  
  int s_src, s_dst;
  unsigned char *src, *src_y;
  unsigned char *dst, *dst_y;
  // Copy Strides
  s_src = src0->s0;
  s_dst = copy->w << 2;
  // Copy Buffer Pointers
  src_y = src0->buffer;
  dst_y = copy->buffer;
  src_y += y0 * s_src + (x0 << 2);

  // SIMD Registers
  __m128i xmm0, xmm1;
  __m128i color0, color1;
  // Checker Pattern Buffer
  unsigned int *bg_x, *bg_y;
  unsigned int *bg = copy->bg->buffer;
  // Checker Pattern Size
  int size = 2 << copy->bg->shift;
  int repeat = size - 1;

  for (int y = y0; y < y1; y++) {
    src = src_y;
    dst = dst_y;
    // Warp Pattern Vertically
    bg_y = bg + (y & repeat) * size;

    for (int x = x0; x < x1; x += 8) {
      bg_x = bg_y + (x & repeat);
      // Load Source and Pattern Pixels
      xmm0 = _mm_load_si128((__m128i*) src);
      xmm1 = _mm_load_si128((__m128i*) src + 1);
      color0 = _mm_load_si128((__m128i*) bg_x);
      color1 = _mm_load_si128((__m128i*) bg_x + 1);
      // Blend to White Pixel
      xmm0 = canvas_pixel_blend(xmm0, color0);
      xmm1 = canvas_pixel_blend(xmm1, color1);
      // Stream to PBO Buffer
      _mm_stream_si128((__m128i*) dst, xmm0);
      _mm_stream_si128((__m128i*) dst + 1, xmm1);

      // Next Pixels
      src += 32;
      dst += 32;
    }

    // Next Lane
    src_y += s_src;
    dst_y += s_dst;
  }
}
