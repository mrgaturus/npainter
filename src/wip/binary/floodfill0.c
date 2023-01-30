// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2022 Cristian Camilo Ruiz <mrgaturus>
#include "binary.h"
#include <smmintrin.h>

// ------------------------
// FLOODFILL SCANLINE PASS0
// ------------------------

static void scanline_simple_right(scanline_t* scan) {
  unsigned char *buffer0, *buffer1;
  unsigned char *upper0, *upper1;
  unsigned char *lower0, *lower1;
  // Calculate Buffer Stride
  const int stride = scan->stride;
  const int index = scan->index;
  // Calculate Buffer Position
  int x = scan->x;
  int y = scan->y;
  // Calculate Stack Pointer
  short* stack = scan->stack;
  // Calculate Buffer Size
  const int w = scan->w;
  const int h = scan->h;
  // Calculate Buffer Location
  buffer0 = scan->buffer0 + index;
  buffer1 = scan->buffer1 + index;
  // Calculate Scanline Advances
  upper0 = buffer0 - stride;
  upper1 = buffer1 - stride;
  lower0 = buffer0 + stride;
  lower1 = buffer1 + stride;
  // Check Scanline Advances
  if (y - 1 < 0) upper0 = (void*) 0;
  if (y + 1 >= h) lower0 = (void*) 0;

  unsigned int count0, count1;
  unsigned int check0, check1, check2;
  // Initialize Checking to 0
  count0 = count1 = check0 = 0;
  // Calculate Scanline Residual
  for (int i = w - x & 15; i > 0; i--, x++) {
    if (check0 = *buffer0 | *buffer1) break;

    // Check Scanline Advances
    check1 = upper0 ? (*upper0++ | *upper1++) : 255;
    check2 = lower0 ? (*lower0++ | *lower1++) : 255;
    // Check Scanline Counts
    count0 = check1 ? 0 : count0 + 1;
    count1 = check2 ? 0 : count1 + 1;

    if (count0 == 1) {
      *(stack++) = x;
      *(stack++) = y - 1;
    }

    if (count1 == 1) {
      *(stack++) = x;
      *(stack++) = y + 1;
    }

    // Put Current Mask
    *(buffer1) = 255;
    // Step Buffers
    buffer0++;
    buffer1++;
  }

  __m128i xmm0, xmm1, xmm2;
  __m128i ymm0, ymm1, ymm2;
  // Initialize As Ones
  xmm1 = ymm1 = _mm_cmpeq_epi32(xmm0, xmm0);
  xmm2 = ymm2 = _mm_cmpeq_epi32(ymm0, ymm0);
  const __m128i ones = _mm_cmpeq_epi32(ones, ones);
  // Calculate Scanline SIMD
  while (x < w && check0 == 0) {
    xmm0 = _mm_loadu_si128((__m128i*) buffer0);
    ymm0 = _mm_loadu_si128((__m128i*) buffer1);

    // Load Top Scanline
    if (upper0) {
      xmm1 = _mm_loadu_si128((__m128i*) upper0);
      ymm1 = _mm_loadu_si128((__m128i*) upper1);
      // Next Upper
      upper0 += 16;
      upper1 += 16;
    }

    // Load Lower Scanline
    if (lower0) {
      xmm2 = _mm_loadu_si128((__m128i*) lower0);
      ymm2 = _mm_loadu_si128((__m128i*) lower1);
      // Next Lower
      lower0 += 16;
      lower1 += 16;
    }

    // Merge Each Scanline
    xmm0 = _mm_or_si128(xmm0, ymm0);
    xmm1 = _mm_or_si128(xmm1, ymm1);
    xmm2 = _mm_or_si128(xmm2, ymm2);
    // Calculate Each Mask
    check0 = _mm_movemask_epi8(xmm0);
    check1 = _mm_movemask_epi8(xmm1);
    check2 = _mm_movemask_epi8(xmm2);

    if (check0 == 0) {
      _mm_storeu_si128((__m128i*) buffer1, ones);
    } else {
      // Boundary Ones
      xmm0 = ones;
      check0 = ~check0;

      while (check0 & 1) {
        xmm0 = _mm_slli_si128(xmm0, 1);
        // Next Bit
        check0 >>= 1;
      }

      xmm1 = _mm_blendv_epi8(ones, ymm0, xmm0);
      unsigned int mask = _mm_movemask_epi8(xmm0);
      // Store Mask Respecting Boundaries
      _mm_storeu_si128((__m128i*) buffer1, xmm1);
      // Apply Boundary Mask
      check1 |= mask;
      check2 |= mask;
    }

    for (int i = 0; i < 16; i++, x++) {
      count0 = (check1 & 1) ? 0 : count0 + 1;
      count1 = (check2 & 1) ? 0 : count1 + 1;

      if (count0 == 1) {
        *(stack++) = x;
        *(stack++) = y - 1;
      }

      if (count1 == 1) {
        *(stack++) = x;
        *(stack++) = y + 1;
      }

      // Next Bit
      check1 >>= 1;
      check2 >>= 1;
    }

    // Next Scanline
    buffer0 += 16;
    buffer1 += 16;
  }

  // Replace Current Stack
  scan->stack = stack;
  // Check Right Boundary
  if (x > scan->x2)
    scan->x2 = x;
}

static void scanline_simple_left(scanline_t* scan) {
  unsigned char *buffer0, *buffer1;
  unsigned char *upper0, *upper1;
  unsigned char *lower0, *lower1;
  // Calculate Buffer Stride
  const int stride = scan->stride;
  const int index = scan->index - 1;
  // Calculate Buffer Position
  int x = scan->x - 1;
  int y = scan->y;
  // Calculate Stack Pointer
  short* stack = scan->stack;
  // Calculate Buffer Size
  const int w = scan->w;
  const int h = scan->h;
  // Calculate Buffer Location
  buffer0 = scan->buffer0 + index;
  buffer1 = scan->buffer1 + index;
  // Calculate Scanline Advances
  upper0 = buffer0 - stride;
  upper1 = buffer1 - stride;
  lower0 = buffer0 + stride;
  lower1 = buffer1 + stride;
  // Check Scanline Advances
  if (y - 1 < 0) upper0 = (void*) 0;
  if (y + 1 >= h) lower0 = (void*) 0;
  // Check X Bound
  if (x < 0) return;

  unsigned int count0, count1;
  unsigned int check0, check1, check2;
  // Initialize Checking to 0
  count0 = count1 = check0 = 0;
  // Calculate Scanline Residual
  for (int i = x & 15; i >= 0; i--, x--) {
    if (check0 = *buffer0 | *buffer1) break;

    // Check Scanline Advances
    check1 = upper0 ? (*upper0-- | *upper1--) : 255;
    check2 = lower0 ? (*lower0-- | *lower1--) : 255;
    // Check Scanline Counts
    count0 = check1 ? 0 : count0 + 1;
    count1 = check2 ? 0 : count1 + 1;

    if (count0 == 1) {
      *(stack++) = x;
      *(stack++) = y - 1;
    }

    if (count1 == 1) {
      *(stack++) = x;
      *(stack++) = y + 1;
    }

    // Put Current Mask
    *(buffer1) = 255;
    // Step Buffers
    buffer0--;
    buffer1--;
  }

  __m128i xmm0, xmm1, xmm2;
  __m128i ymm0, ymm1, ymm2;
  // Initialize As Ones
  xmm1 = ymm1 = _mm_cmpeq_epi32(xmm0, xmm0);
  xmm2 = ymm2 = _mm_cmpeq_epi32(ymm0, ymm0);
  const __m128i ones = _mm_cmpeq_epi32(ones, ones);

  // Offset Buffers
  buffer0 -= 15;
  buffer1 -= 15;
  // Offset Upper, Lower
  check1 = (upper0) ? 15 : 0;
  check2 = (lower0) ? 15 : 0;
  // Apply Offer Upper Lower
  upper0 -= check1; lower0 -= check2;
  upper1 -= check1; lower1 -= check2;

  // Calculate Scanline SIMD
  while (x > 0 && check0 == 0) {
    xmm0 = _mm_loadu_si128((__m128i*) buffer0);
    ymm0 = _mm_loadu_si128((__m128i*) buffer1);

    // Load Top Scanline
    if (upper0) {
      xmm1 = _mm_loadu_si128((__m128i*) upper0);
      ymm1 = _mm_loadu_si128((__m128i*) upper1);
      // Next Upper
      upper0 -= 16;
      upper1 -= 16;
    }

    // Load Lower Scanline
    if (lower0) {
      xmm2 = _mm_loadu_si128((__m128i*) lower0);
      ymm2 = _mm_loadu_si128((__m128i*) lower1);
      // Next Lower
      lower0 -= 16;
      lower1 -= 16;
    }

    // Merge Each Scanline
    xmm0 = _mm_or_si128(xmm0, ymm0);
    xmm1 = _mm_or_si128(xmm1, ymm1);
    xmm2 = _mm_or_si128(xmm2, ymm2);
    // Calculate Each Mask
    check0 = _mm_movemask_epi8(xmm0);
    check1 = _mm_movemask_epi8(xmm1);
    check2 = _mm_movemask_epi8(xmm2);

    if (check0 == 0) {
      _mm_storeu_si128((__m128i*) buffer1, ones);
    } else {
      // Boundary Ones
      xmm0 = ones;
      check0 = ~check0;

      while (check0 & 0x8000) {
        xmm0 = _mm_srli_si128(xmm0, 1);
        // Next Bit
        check0 <<= 1;
      }

      // Store Mask Respecting Boundaries
      xmm1 = _mm_blendv_epi8(ones, ymm0, xmm0);
      _mm_storeu_si128((__m128i*) buffer1, xmm1);
      // Calculate Boundary Mask
      int mask = _mm_movemask_epi8(xmm0);
      // Apply Boundary Mask
      check1 |= mask;
      check2 |= mask;
    }

    for (int i = 0; i < 16; i++, x--) {
      count0 = (check1 & 0x8000) ? 0 : count0 + 1;
      count1 = (check2 & 0x8000) ? 0 : count1 + 1;

      if (count0 == 1) {
        *(stack++) = x;
        *(stack++) = y - 1;
      }

      if (count1 == 1) {
        *(stack++) = x;
        *(stack++) = y + 1;
      }

      // Next Bit
      check1 <<= 1;
      check2 <<= 1;
    }

    // Next Scanline
    buffer0 -= 16;
    buffer1 -= 16;
  }

  // Replace Current Stack
  scan->stack = stack;
  // Check Left Boundary
  if (x < scan->x1)
    scan->x1 = x;
}

// ---------------------------
// FLOODFILL SCANLINE DISPATCH
// ---------------------------

void floodfill_simple(floodfill_t* flood) {
  int x, y, w, h;
  // Initial Seed
  x = flood->x;
  y = flood->y;
  // Buffer Size
  w = flood->w;
  h = flood->h;

  printf("starting x: %d, y: %d\n", x, y);

  scanline_t scan;
  // Load Mask Buffer
  scan.buffer0 = flood->buffer0;
  scan.buffer1 = flood->buffer1;
  // Load Mask Metrics
  scan.w = w;
  scan.h = h;
  // Load Mask Stride
  scan.stride = w;
  // Load Stack Pointer
  short* stack0 = flood->stack;
  scan.stack = stack0;

  // Load Stack Initial
  *(scan.stack++) = x;
  *(scan.stack++) = y;
  // Load Scanline AABB
  scan.x1 = scan.x2 = x;
  scan.y1 = scan.y2 = y;

  while (scan.stack > stack0) {
    // Load Coordinates
    scan.y = *(--scan.stack);
    scan.x = *(--scan.stack);

    if (scan.x < 0 || scan.x >= w) {
      printf("error x: %d\n", scan.x);
      continue;
    }

    if (scan.y < 0 || scan.y >= h) {
      printf("error y: %d\n", scan.y);
      continue;
    }

    // Calculate Location Index
    scan.index = scan.y * w + scan.x;
    // Calculate Scanline
    scanline_simple_right(&scan);
    scanline_simple_left(&scan);
  }
}
