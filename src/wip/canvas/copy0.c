// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
#include "canvas.h"

// ------------------
// Canvas Stream Copy
// ------------------

void canvas_copy_stream(canvas_copy_t* copy) {
  int x0, y0, x1, y1;
  // Locate Copy Region
  x0 = (copy->x256 << 8) + copy->x;
  y0 = (copy->y256 << 8) + copy->y;
  x1 = x0 + copy->w;
  y1 = y0 + copy->h;
  // Clamp Copy Region
  canvas_copy_align(copy, &x1, &y1);

  int s_src, s_dst;
  unsigned char *src, *src_y;
  unsigned char *dst, *dst_y;
  // Copy Strides
  s_src = copy->s0 << 2;
  s_dst = copy->w << 2;
  // Copy Buffer Pointers
  src_y = copy->buffer0;
  dst_y = copy->buffer1;
  src_y += y0 * s_src + (x0 << 2);

  __m128i xmm0, xmm1, xmm2, xmm3;
  __m128i xmm4, xmm5, xmm6, xmm7;

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
      xmm4 = _mm_load_si128((__m128i*) src + 4);
      xmm5 = _mm_load_si128((__m128i*) src + 5);
      xmm6 = _mm_load_si128((__m128i*) src + 6);
      xmm7 = _mm_load_si128((__m128i*) src + 7);
      // Stream to PBO Buffer
      _mm_stream_si128((__m128i*) dst, xmm0);
      _mm_stream_si128((__m128i*) dst + 1, xmm1);
      _mm_stream_si128((__m128i*) dst + 2, xmm2);
      _mm_stream_si128((__m128i*) dst + 3, xmm3);
      _mm_stream_si128((__m128i*) dst + 4, xmm4);
      _mm_stream_si128((__m128i*) dst + 5, xmm5);
      _mm_stream_si128((__m128i*) dst + 6, xmm6);
      _mm_stream_si128((__m128i*) dst + 7, xmm7);

      // Next Pixels
      count -= 32;
      src += 128;
      dst += 128;
    }

    // Next Lane
    src_y += s_src;
    dst_y += s_dst;
  }
}

// --------------------
// Canvas Zeros Padding
// --------------------

void canvas_copy_padding(canvas_copy_t* copy) {
  int x0, y0, x1, y1, x2, y2;
  // Locate Padding Regions
  x0 = (copy->x256 << 8) + copy->x;
  y0 = (copy->y256 << 8) + copy->y;
  x1 = copy->w0 - x0;
  y1 = copy->h0 - y0;
  x2 = x0 + copy->w;
  y2 = y0 + copy->h;
  // Clamp Padding Region
  x1 = (x1 < x2) ? x1 : x2;
  y1 = (y1 < y2) ? y1 : y2;

  int lane, stride, offset;
  unsigned char *dst, *dst_y;
  // Padding Strides
  stride = copy->w << 2;
  offset = (x1 - x0) << 2;
  // Padding Buffer Pointer
  dst_y = copy->buffer1;
  dst_y += copy->x * stride + (copy->y << 2);
  // Zero SIMD Streaming
  const __m128i zeros = _mm_setzero_si128();

  // Horizontal Padding
  for (lane = y0; lane < y1; lane++) {
    dst = dst_y + offset;
    // Lane Count
    int count0 = (x2 - x1) & 0x1F;
    int count1 = (x2 - x1) & ~0x1F;

    while (count0 > 0) {
      _mm_stream_si32((int*) dst, 0);
      // Next Pixel
      dst += 4;
      count0--;
    }

    while (count1 > 0) {
      // Stream to PBO Buffer
      _mm_stream_si128((__m128i*) dst, zeros);
      _mm_stream_si128((__m128i*) dst + 1, zeros);
      _mm_stream_si128((__m128i*) dst + 2, zeros);
      _mm_stream_si128((__m128i*) dst + 3, zeros);
      _mm_stream_si128((__m128i*) dst + 4, zeros);
      _mm_stream_si128((__m128i*) dst + 5, zeros);
      _mm_stream_si128((__m128i*) dst + 6, zeros);
      _mm_stream_si128((__m128i*) dst + 7, zeros);

      // Next Pixels
      dst += 128;
      count1 -= 32;
    }

    // Next Lane
    dst_y += stride;
  }

  // Vertical Padding
  for (lane = y1; lane < y2; lane++) {
    dst = dst_y;
    int count = x2 - x0;

    while (count > 0) {
      // Stream to PBO Buffer
      _mm_stream_si128((__m128i*) dst, zeros);
      _mm_stream_si128((__m128i*) dst + 1, zeros);
      _mm_stream_si128((__m128i*) dst + 2, zeros);
      _mm_stream_si128((__m128i*) dst + 3, zeros);
      _mm_stream_si128((__m128i*) dst + 4, zeros);
      _mm_stream_si128((__m128i*) dst + 5, zeros);
      _mm_stream_si128((__m128i*) dst + 6, zeros);
      _mm_stream_si128((__m128i*) dst + 7, zeros);

      // Next Pixels
      dst += 128;
      count -= 32;
    }

    // Next Lane
    dst_y += stride;
  }
}
