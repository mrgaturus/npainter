// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2022 Cristian Camilo Ruiz <mrgaturus>
#include "binary.h"
#include <smmintrin.h>

// -----------------
// Binary Clear Fill
// -----------------

void binary_clear(binary_clear_t* clear) {
  int x1, y1, x2, y2;
  // Clear Region
  x1 = clear->x;
  y1 = clear->y;
  x2 = x1 + clear->w;
  y2 = y1 + clear->h;

  int bytes, stride;
  // Calculate Bytes
  bytes = clear->bytes;
  stride = clear->stride;
  // Extend Stride
  stride *= bytes;
  // Extend Lanes
  x1 *= bytes;
  x2 *= bytes;

  int len, count;
  // Calculate Row Size
  len = x2 - x1;

  unsigned char *buffer, *buffer_row;
  // Locate Buffer Pointer
  buffer_row = clear->buffer;
  buffer_row += y1 * stride + x1;
  // Initialize Zeros Clearing
  const __m128i zeros = _mm_setzero_si128();

  for (int y = y1; y < y2; y++) {
    buffer = buffer_row;
    // Reset Length
    count = len;

    while (count > 0) {
      // Store 16 Pixels
      if (count >= 16) {
        _mm_storeu_si128((__m128i*) buffer, zeros); 
        // Step 16 Pixels
        buffer += 16;
        count -= 16;
        // Skip to Next
        continue;
      }

      // Store 8 Pixels
      if (count >= 8) {
        _mm_storeu_si64(buffer, zeros); 
        // Step 8 Pixels
        buffer += 8;
        count -= 8;
      }

      // Store 4 Pixels
      if (count >= 4) {
        _mm_storeu_si32(buffer, zeros); 
        // Step 4 Pixels
        buffer += 4;
        count -= 4;
      }

      // Stop SIMD
      break;
    }

    while (count > 0) {
      // Store One Pixel
      *(buffer) = 0;
      // Step One Pixel
      buffer++;
      count--;
    }

    // Step Stride
    buffer_row += stride;
  }
}

// --------------------
// Binary Clear Stencil
// --------------------

void binary_stencil(binary_stencil_t* stencil) {
  int x1, y1, x2, y2;
  // Clear Region
  x1 = stencil->x;
  y1 = stencil->y;
  x2 = x1 + stencil->w;
  y2 = y1 + stencil->h;

  int bytes, stride;
  // Calculate Bytes
  bytes = stencil->bytes;
  stride = stencil->stride;
  // Extend Stride
  stride *= bytes;
  // Extend Lanes
  x1 *= bytes;
  x2 *= bytes;

  int len, count, calc;
  // Calculate Row Size
  len = x2 - x1;

  unsigned char *src, *src_row;
  unsigned char *dst, *dst_row;
  // Load Buffer Pointers
  src_row = stencil->buffer0;
  dst_row = stencil->buffer1;
  // Locate Buffer Position
  calc = y1 * stride + x1;
  // Locate Buffer Pointers
  src_row += calc;
  dst_row += calc;

  __m128i xmm0, xmm1;
  // Apply Binary Stencil
  for (int y = y1; y < y2; y++) {
    src = src_row;
    dst = dst_row;
    // Reset Length
    count = len;

    while (count > 0) {
      xmm0 = _mm_loadu_si128((__m128i*) src);
      xmm1 = _mm_loadu_si128((__m128i*) dst);
      xmm0 = _mm_and_si128(xmm1, xmm0);

      // Store 16 Pixels
      if (count >= 16) {
        _mm_storeu_si128((__m128i*) dst, xmm0);
        // Step 16 Pixels
        src += 16;
        dst += 16;
        count -= 16;
        // Skip to Next
        continue;
      }

      // Store 8 Pixels
      if (count >= 8) {
        _mm_storeu_si64(dst, xmm0);
        _mm_srli_si128(xmm0, 8);
        // Step 8 Pixels
        src += 8;
        dst += 8;
        count -= 8;
      }

      // Store 4 Pixels
      if (count >= 4) {
        _mm_storeu_si32(dst, xmm0);
        // Step 4 Pixels
        src += 4;
        dst += 4;
        count -= 4;
      }

      // Stop SIMD
      break;
    }

    while (count > 0) {
      // Store One Pixel
      *(dst) &= ~(*src);
      // Step One Pixel
      src++;
      dst++;
      count--;
    }

    // Step Stride
    src_row += stride;
    dst_row += stride;
  }
}
