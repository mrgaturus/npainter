// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
#include "image.h"

// ---------------------
// Mipmap Tile Reduction
// ---------------------

void mipmap_reduce(image_combine_t* co) {
  // Load Buffer Pointers
  unsigned char *dst_x, *dst_y;
  unsigned char *src_x0, *src_x1, *src_y;
  dst_y = co->dst.buffer;
  src_y = co->src.buffer;

  int w, h, s_src, s_dst;
  // Load Region
  w = co->dst.w;
  h = co->dst.h;
  // Load Strides
  s_src = co->src.stride;
  s_dst = co->dst.stride;

  // Source Pixel Values
  __m128i xmm0, xmm1, xmm2, xmm3;
  __m128i xmm4, xmm5, xmm6, xmm7;

  for (int count, y = 0; y < h; y++) {
    dst_x = dst_y;
    // Source Pixels
    src_x0 = src_y;
    src_x1 = src_y + s_src;
    // Lane Count
    count = w;

    // Copy Source bytes to Destination
    while (count > 0) {
      // Upper Source Pixels
      xmm0 = _mm_load_si128((__m128i*) src_x0);
      xmm1 = _mm_load_si128((__m128i*) src_x0 + 1);
      xmm2 = _mm_load_si128((__m128i*) src_x0 + 2);
      xmm3 = _mm_load_si128((__m128i*) src_x0 + 3);
      // Bottom Source Pixels
      xmm4 = _mm_load_si128((__m128i*) src_x1);
      xmm5 = _mm_load_si128((__m128i*) src_x1 + 1);
      xmm6 = _mm_load_si128((__m128i*) src_x1 + 2);
      xmm7 = _mm_load_si128((__m128i*) src_x1 + 3);

      // Average 8 Pixels Vertically
      xmm0 = _mm_avg_epu16(xmm0, xmm4);
      xmm1 = _mm_avg_epu16(xmm1, xmm5);
      xmm2 = _mm_avg_epu16(xmm2, xmm6);
      xmm3 = _mm_avg_epu16(xmm3, xmm7);
      // Average 4 Pixels Horizontally
      xmm4 = _mm_unpacklo_epi64(xmm0, xmm1);
      xmm5 = _mm_unpacklo_epi64(xmm2, xmm3);
      xmm6 = _mm_unpackhi_epi64(xmm0, xmm1);
      xmm7 = _mm_unpackhi_epi64(xmm2, xmm3);
      xmm0 = _mm_avg_epu16(xmm4, xmm6);
      xmm1 = _mm_avg_epu16(xmm5, xmm7);

      // Store 4 Pixels
      if (__builtin_expect(count >= 4, 1)) {
        _mm_stream_si128((__m128i*) dst_x, xmm0);
        _mm_stream_si128((__m128i*) dst_x + 1, xmm1);

        // Step Buffers
        src_x0 += 64;
        src_x1 += 64;
        dst_x += 32;
        // Step 4 Pixels
        count -= 4;
        continue;
      }

      // Store 2 Pixels
      if (count >= 2) {
        _mm_stream_si128((__m128i*) dst_x, xmm0);
        xmm0 = xmm1;
        // Step 2 Pixels
        dst_x += 16;
        count -= 2;
      }

      // Store 1 Pixel
      if (count == 1) {
        _mm_storel_epi64((__m128i*) dst_x, xmm0);
        // No More Pixels
        count--;
      }
    }

    // Step Y Buffers
    src_y += s_src << 1;
    dst_y += s_dst;
  }
}
