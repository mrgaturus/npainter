// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
#include "image.h"

// -----------------
// Proxy Tile Stream
// -----------------

void proxy_stream(image_combine_t* co) {
  // Load Buffer Pointers
  unsigned char *dst_x, *dst_y;
  unsigned char *src_x, *src_y;
  dst_y = co->dst.buffer;
  src_y = co->src.buffer;

  int w, h, s_src, s_dst;
  // Load Region
  w = co->src.w;
  h = co->src.h;
  // Load Strides
  s_src = co->src.stride;
  s_dst = co->dst.stride;

  // Source Pixel Values
  __m128i xmm0, xmm1, xmm2, xmm3;
  __m128i xmm4, xmm5, xmm6, xmm7;

  for (int count, y = 0; y < h; y++) {
    dst_x = dst_y;
    src_x = src_y;
    count = w;

    // Copy Source bytes to Destination
    while (count > 0) {
      xmm0 = _mm_load_si128((__m128i*) src_x);
      xmm1 = _mm_load_si128((__m128i*) src_x + 1);
      xmm2 = _mm_load_si128((__m128i*) src_x + 2);
      xmm3 = _mm_load_si128((__m128i*) src_x + 3);
      xmm4 = _mm_load_si128((__m128i*) src_x + 4);
      xmm5 = _mm_load_si128((__m128i*) src_x + 5);
      xmm6 = _mm_load_si128((__m128i*) src_x + 6);
      xmm7 = _mm_load_si128((__m128i*) src_x + 7);
      // Copy 16 Pixels
      _mm_stream_si128((__m128i*) dst_x, xmm0);
      _mm_stream_si128((__m128i*) dst_x + 1, xmm1);
      _mm_stream_si128((__m128i*) dst_x + 2, xmm2);
      _mm_stream_si128((__m128i*) dst_x + 3, xmm3);
      _mm_stream_si128((__m128i*) dst_x + 4, xmm4);
      _mm_stream_si128((__m128i*) dst_x + 5, xmm5);
      _mm_stream_si128((__m128i*) dst_x + 6, xmm6);
      _mm_stream_si128((__m128i*) dst_x + 7, xmm7);

      // Step Buffers
      src_x += 128;
      dst_x += 128;
      // Step Pixels
      count -= 16;
    }

    // Step Y Buffers
    dst_y += s_dst;
    src_y += s_src;
  }
}

void proxy_fill(image_combine_t* co) {
  // Load Buffer Pointers
  unsigned char *dst_x, *dst_y;
  dst_y = co->dst.buffer;

  int w, h, s_src, s_dst;
  // Load Region
  w = co->src.w;
  h = co->src.h;
  // Load Strides
  s_dst = co->dst.stride;

  __m128i xmm0;
  // Uniform Pixel Value
  xmm0 = _mm_loadl_epi64((__m128i*) co->src.buffer);
  xmm0 = _mm_unpacklo_epi64(xmm0, xmm0);

  for (int count, y = 0; y < h; y++) {
    dst_x = dst_y;
    count = w;

    // Copy Source bytes to Destination
    while (count > 0) {
      // Copy 16 Pixels
      _mm_stream_si128((__m128i*) dst_x, xmm0);
      _mm_stream_si128((__m128i*) dst_x + 1, xmm0);
      _mm_stream_si128((__m128i*) dst_x + 2, xmm0);
      _mm_stream_si128((__m128i*) dst_x + 3, xmm0);
      _mm_stream_si128((__m128i*) dst_x + 4, xmm0);
      _mm_stream_si128((__m128i*) dst_x + 5, xmm0);
      _mm_stream_si128((__m128i*) dst_x + 6, xmm0);
      _mm_stream_si128((__m128i*) dst_x + 7, xmm0);

      // Step Buffer
      dst_x += 128;
      count -= 16;
    }

    // Step Y Buffer
    dst_y += s_dst;
  }
}

// ------------------
// Proxy Tile Uniform
// ------------------

void proxy_uniform(image_combine_t* co) {
  // Load Buffer Pointers
  unsigned char *src_x, *src_y;
  src_y = co->src.buffer;

  int w, h, s_src;
  // Load Region
  w = co->src.w;
  h = co->src.h;
  // Load Strides
  s_src = co->src.stride;

  // Source Pixel Values
  __m128i xmm0, xmm1, xmm2, xmm3;
  __m128i xmm4, xmm5, xmm6, xmm7;
  // Load First Buffer
  __m128i check = _mm_load_si128((__m128i*) src_y);
  __m128i mask = _mm_cmpeq_epi32(check, check);
  check = _mm_unpacklo_epi64(check, check);
  check = _mm_srli_epi16(check, 8);

  for (int count, y = 0; y < h; y++) {
    src_x = src_y;
    count = w;

    // Check Region Uniform
    while (count > 0) {
      xmm0 = _mm_load_si128((__m128i*) src_x);
      xmm1 = _mm_load_si128((__m128i*) src_x + 1);
      xmm2 = _mm_load_si128((__m128i*) src_x + 2);
      xmm3 = _mm_load_si128((__m128i*) src_x + 3);
      xmm4 = _mm_load_si128((__m128i*) src_x + 4);
      xmm5 = _mm_load_si128((__m128i*) src_x + 5);
      xmm6 = _mm_load_si128((__m128i*) src_x + 6);
      xmm7 = _mm_load_si128((__m128i*) src_x + 7);
      // Lower Pixel Precision
      xmm0 = _mm_srli_epi16(xmm0, 8);
      xmm1 = _mm_srli_epi16(xmm1, 8);
      xmm2 = _mm_srli_epi16(xmm2, 8);
      xmm3 = _mm_srli_epi16(xmm3, 8);
      xmm4 = _mm_srli_epi16(xmm4, 8);
      xmm5 = _mm_srli_epi16(xmm5, 8);
      xmm6 = _mm_srli_epi16(xmm6, 8);
      xmm7 = _mm_srli_epi16(xmm7, 8);
      // Check if Pixel Match Pattern
      xmm0 = _mm_cmpeq_epi8(xmm0, check);
      xmm1 = _mm_cmpeq_epi8(xmm1, check);
      xmm2 = _mm_cmpeq_epi8(xmm2, check);
      xmm3 = _mm_cmpeq_epi8(xmm3, check);
      xmm4 = _mm_cmpeq_epi8(xmm4, check);
      xmm5 = _mm_cmpeq_epi8(xmm5, check);
      xmm6 = _mm_cmpeq_epi8(xmm6, check);
      xmm7 = _mm_cmpeq_epi8(xmm7, check);
      // Combine Pixel Checks
      xmm0 = _mm_and_si128(xmm0, xmm1);
      xmm2 = _mm_and_si128(xmm2, xmm3);
      xmm4 = _mm_and_si128(xmm4, xmm5);
      xmm6 = _mm_and_si128(xmm6, xmm7);
      xmm0 = _mm_and_si128(xmm0, xmm2);
      xmm1 = _mm_and_si128(xmm4, xmm6);
      xmm0 = _mm_and_si128(xmm0, xmm1);
      // Accumulate Pixel Checks
      mask = _mm_and_si128(mask, xmm0);

      // Step Buffer
      src_x += 128;
      count -= 16;
    }

    // Step Y Buffer
    src_y += s_src;
  }

  // Change Buffer to Uniform if pass
  xmm1 = _mm_cmpeq_epi32(mask, mask);
  if (_mm_testc_si128(mask, xmm1) == 1) {
    co->src.stride = co->src.bpp;
    // Store 8bit to 16bit Uniform
    check = _mm_packus_epi16(check, check);
    check = _mm_unpacklo_epi8(check, check);
    _mm_store_si128((__m128i*) co->src.buffer, check);
  }
}
