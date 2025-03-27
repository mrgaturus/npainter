// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
#include "image.h"
#include <string.h>

void buffer_clip(image_buffer_t* src, const image_clip_t clip) {
  int cx1 = clip.x + clip.w;
  int cy1 = clip.y + clip.h;
  // Buffer Region
  int x0 = src->x;
  int y0 = src->y;
  int x1 = x0 + src->w;
  int y1 = y0 + src->h;

  // Clip Buffer Region
  if (x0 < clip.x) x0 = clip.x;
  if (y0 < clip.y) y0 = clip.y;
  if (x1 > cx1) x1 = cx1;
  if (y1 > cy1) y1 = cy1;
  // Clip Buffer Deltas
  long long dx = x0 - src->x;
  long long dy = y0 - src->y;
  // Apply Buffer Delta to Pointer
  if (src->stride > src->bpp)
    src->buffer += dy * src->stride + dx * src->bpp;

  // Apply Clipping
  src->x = x0;
  src->y = y0;
  src->w = x1 - x0;
  src->h = y1 - y0;
}

void combine_clip(image_combine_t* co, image_clip_t clip) {
  // Apply Buffer Clipping
  buffer_clip(&co->src, clip);
  buffer_clip(&co->dst, clip);
}

void combine_intersect(image_combine_t* co) {
  image_buffer_t* src = &co->src;
  image_buffer_t* dst = &co->dst;

  // Create Clipping Regions
  image_clip_t src_clip = *((image_clip_t*) src);
  image_clip_t dst_clip = *((image_clip_t*) dst);
  // Apply Buffer Clipping
  buffer_clip(src, dst_clip);
  buffer_clip(dst, src_clip);
}

// ---------------------
// Combine Buffer Basics
// ---------------------

void combine_clear(image_combine_t* co) {
  unsigned char *dst = co->dst.buffer;
  int stride, bytes, rows;

  // Load Combine Region
  stride = co->dst.stride;
  bytes = co->dst.w * co->dst.bpp;
  rows = co->dst.h;

  for (int y = 0; y < rows; y++) {
    memset(dst, 0, bytes);
    dst += stride;
  }
}

void combine_copy(image_combine_t* co) {
  unsigned char *src = co->src.buffer;
  unsigned char *dst = co->dst.buffer;

  // Load Combine Region
  const int bytes = co->src.w * co->src.bpp;
  const int rows = co->src.h;
  // Load Combine Strides
  int src_stride = co->src.stride;
  int dst_stride = co->dst.stride;

  for (int y = 0; y < rows; y++) {
    memcpy(dst, src, bytes);
    // Step Y Buffer
    src += src_stride;
    dst += dst_stride;
  }
}

// ---------------------------------
// Combine Buffer Pack 16bit to 8bit
// ---------------------------------

static void combine_pack_x16(char* src, char* dst, int count) {
  // Source Pixel Values
  __m128i xmm0, xmm1, xmm2, xmm3;
  __m128i xmm4, xmm5, xmm6, xmm7;

  while (count > 0) {
    xmm0 = _mm_load_si128((__m128i*) src);
    xmm1 = _mm_load_si128((__m128i*) src + 1);
    xmm2 = _mm_load_si128((__m128i*) src + 2);
    xmm3 = _mm_load_si128((__m128i*) src + 3);
    xmm4 = _mm_load_si128((__m128i*) src + 4);
    xmm5 = _mm_load_si128((__m128i*) src + 5);
    xmm6 = _mm_load_si128((__m128i*) src + 6);
    xmm7 = _mm_load_si128((__m128i*) src + 7);
    // Convert to 8 bit RGBA
    xmm0 = _mm_srli_epi16(xmm0, 8);
    xmm1 = _mm_srli_epi16(xmm1, 8);
    xmm2 = _mm_srli_epi16(xmm2, 8);
    xmm3 = _mm_srli_epi16(xmm3, 8);
    xmm4 = _mm_srli_epi16(xmm4, 8);
    xmm5 = _mm_srli_epi16(xmm5, 8);
    xmm6 = _mm_srli_epi16(xmm6, 8);
    xmm7 = _mm_srli_epi16(xmm7, 8);
    // Store 8 bpp Pixels
    xmm0 = _mm_packus_epi16(xmm0, xmm1);
    xmm1 = _mm_packus_epi16(xmm2, xmm3);
    xmm2 = _mm_packus_epi16(xmm4, xmm5);
    xmm3 = _mm_packus_epi16(xmm6, xmm7);
    _mm_stream_si128((__m128i*) dst, xmm0);
    _mm_stream_si128((__m128i*) dst + 1, xmm1);
    _mm_stream_si128((__m128i*) dst + 2, xmm2);
    _mm_stream_si128((__m128i*) dst + 3, xmm3);

    // Step Buffers
    src += 128;
    dst += 64;
    // Step Pixels
    count -= 16;
  }
}

static void combine_pack_x4(char* src, char* dst, int count) {
  // Source Pixel Values
  __m128i xmm0, xmm1;

  while (count > 0) {
    xmm0 = _mm_load_si128((__m128i*) src);
    xmm1 = _mm_load_si128((__m128i*) src + 1);
    // Convert to 8 bit RGBA
    xmm0 = _mm_srli_epi16(xmm0, 8);
    xmm1 = _mm_srli_epi16(xmm1, 8);
    // Store 8 bpp Pixels
    xmm0 = _mm_packus_epi16(xmm0, xmm1);
    _mm_stream_si128((__m128i*) dst, xmm0);

    // Step Buffers
    src += 32;
    dst += 16;
    // Step Pixels
    count -= 4;
  }
}

static void combine_pack_x1(char* src, char* dst, int count) {
  // Source Pixel Values
  __m128i xmm0;

  while (count > 0) {
    xmm0 = _mm_loadl_epi64((__m128i*) src);
    xmm0 = _mm_srli_epi16(xmm0, 8);
    // Store 8 bpp Pixel
    xmm0 = _mm_packus_epi16(xmm0, xmm0);
    _mm_storeu_si32((__m128i*) dst, xmm0);

    // Step Buffers
    src += 8;
    dst += 4;
    // Step Pixels
    count--;
  }
}

void combine_pack(image_combine_t* co) {
  // Load Buffer Pointers
  char* src = (char*) co->src.buffer;
  char* dst = (char*) co->dst.buffer;

  int s_src, s_dst;
  // Load Region
  const int w = co->src.w;
  const int h = co->src.h;
  // Load Strides
  s_src = co->src.stride;
  s_dst = co->dst.stride;

  for (int y = 0; y < h; y++) {
    // Pack Pixels to 8 Bit
    if (__builtin_expect(w >= 16, 1))
      combine_pack_x16(src, dst, w);
    else if (__builtin_expect(w >= 4, 1))
      combine_pack_x4(src, dst, w);
    else combine_pack_x1(src, dst, w);

    // Step Y Buffers
    dst += s_dst;
    src += s_src;
  }
}
