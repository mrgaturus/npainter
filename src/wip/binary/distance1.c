// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2022 Cristian Camilo Ruiz <mrgaturus>
#include "binary.h"
#include <smmintrin.h>

// -----------------------------
// Chamfer Distance Forward Pass
// -----------------------------

void distance_pass0(distance_t* chamfer) {
  int x1, y1, x2, y2;
  // Locate Position
  x1 = chamfer->x;
  y1 = chamfer->y;
  x2 = x1 + chamfer->w;
  y2 = y1 + chamfer->h;

  int stride, count;
  // Buffer Strides
  stride = chamfer->stride;
  count = y1 * stride + x1;
  // Buffer Pointers
  unsigned int *distances_row, *distances;
  unsigned int *positions_row, *positions;
  // Buffer Pointer Top
  unsigned int *distances_top;
  unsigned int *positions_top;
  // Locate Buffer Pointers
  distances_row = chamfer->distances + count;
  positions_row = chamfer->positions + count;

  // Cursor Distance Pixels
  unsigned int cursor_dist, cursor_pos;
  unsigned int aux_dist, aux_pos;
  // Semi-SIMD Calculations
  __m128i xmm_dist, xmm_pos, ymm0, ymm1;
  __m128i xmm0, xmm1, xmm2, xmm3, xmm4;
  // Semi-SIMD Magic Constants Infinite
  const unsigned int infinite = 2147483647;
  const __m128i xmm_inf = _mm_set1_epi32(infinite);
  // Semi-SIMD Magic Constants MADD
  const __m128i xmm_step = _mm_set_epi16(0, 1, 1, 1, 1, 0, 1, 1);
  const __m128i xmm_madd = _mm_slli_epi16(xmm_step, 1);
  const __m128i xmm_modd = _mm_set_epi32(1, 2, 1, 2);

  // Process First Line
  if (y1 == 0) {
    distances = distances_row;
    positions = positions_row;
    // Start Previous Pixels
    aux_pos = aux_dist = infinite;
    
    // Process Only One Side
    for (count = x1; count < x2; count++) {
      cursor_dist = *distances;
      cursor_pos = *positions;

      if (cursor_dist) {
        // Calculate Previous Distance
        aux_pos = aux_pos & 0xFFFF;
        aux_dist += (aux_pos << 1) + 1;

        // Change Current Distance
        if (aux_dist < cursor_dist) {
          cursor_dist = aux_dist;
          cursor_pos = aux_pos + 1;

          *distances = cursor_dist;
          *positions = cursor_pos;
        }
      }

      // Change Previous
      aux_dist = cursor_dist;
      aux_pos = cursor_pos;
      // Next Pixel
      distances++;
      positions++;
    }

    // Next Row
    distances_row += stride;
    positions_row += stride;
    // Next Y
    y1++;
  }

  // Process Other Lines
  for (int y = y1; y < y2; y++) {
    distances = distances_row;
    positions = positions_row;
    // Locate Pointers Top
    distances_top = distances - stride;
    positions_top = positions - stride;
    // Load Pointers Neighbours
    xmm_dist = _mm_loadl_epi64((__m128i*) distances_top);
    xmm_pos = _mm_loadl_epi64((__m128i*) positions_top);
    // Insert Two Infinites - X, 0, 1, X
    xmm_dist = _mm_slli_si128(xmm_dist, 4);
    xmm_pos = _mm_slli_si128(xmm_pos, 4);
    xmm_dist = _mm_blend_epi16(xmm_dist, xmm_inf, 0xC3);
    xmm_pos = _mm_blend_epi16(xmm_pos, xmm_inf, 0xC3);
    // Locate Pointers Top
    distances_top += 2;
    positions_top += 2;
    // Start Previous Pixels
    count = x2 - x1;

    while (count > 0) {
      // Load Pixel To XMM
      ymm0 = _mm_loadu_si32(distances);
      ymm1 = _mm_loadu_si32(positions);

      if (_mm_testz_si128(ymm0, ymm0) == 0) {
        xmm0 = _mm_add_epi16(xmm_pos, xmm_step);
        // Calculate Distance Check
        xmm1 = _mm_madd_epi16(xmm_pos, xmm_madd);
        xmm2 = _mm_add_epi32(xmm_dist, xmm_modd);
        xmm1 = _mm_add_epi32(xmm1, xmm2);

        // Find Minimun Distance Pass 0
        xmm2 = _mm_srli_epi64(xmm1, 32);
        xmm4 = _mm_srli_epi64(xmm0, 32);
        xmm1 = _mm_min_epu32(xmm1, xmm2);
        xmm3 = _mm_cmpeq_epi32(xmm1, xmm2);
        xmm0 = _mm_blendv_epi8(xmm0, xmm4, xmm3);

        // Find Minimun Distance Pass 1
        xmm2 = _mm_srli_si128(xmm1, 8);
        xmm4 = _mm_srli_si128(xmm0, 8);
        xmm1 = _mm_min_epu32(xmm1, xmm2);
        xmm3 = _mm_cmpeq_epi32(xmm1, xmm2);
        xmm0 = _mm_blendv_epi8(xmm0, xmm4, xmm3);

        // Find Minimun Distance Pass 2
        ymm0 = _mm_min_epu32(xmm1, ymm0);
        xmm3 = _mm_cmpeq_epi32(xmm1, ymm0);
        ymm1 = _mm_blendv_epi8(ymm1, xmm0, xmm3);

        // Store Minimun Distance
        _mm_storeu_si32(distances, ymm0);
        _mm_storeu_si32(positions, ymm1);
      }

      // Broadcast Distance Pixel
      ymm0 = _mm_shuffle_epi32(ymm0, 0);
      ymm1 = _mm_shuffle_epi32(ymm1, 0);
      // Next Distance Pixel
      xmm_dist = _mm_srli_si128(xmm_dist, 4);
      xmm_pos = _mm_srli_si128(xmm_pos, 4);
      // Change Previous Distance
      xmm0 = _mm_blend_epi16(xmm_dist, ymm0, 0xC0);
      xmm1 = _mm_blend_epi16(xmm_pos, ymm1, 0xC0);
      // Next Distance Pointer
      distances++;
      positions++;

      // Change Next Distance
      if (--count > 1) {
        xmm_dist = _mm_insert_epi32(xmm0, *distances_top, 2);
        xmm_pos = _mm_insert_epi32(xmm1, *positions_top, 2);
        // Next Distance Top
        distances_top++;
        positions_top++;
        // Next Loop
        continue;
      }

      // Put Distance Infinites
      xmm_dist = _mm_blend_epi16(xmm0, xmm_inf, 0x30);
      xmm_pos = _mm_blend_epi16(xmm1, xmm_inf, 0x30);
    }

    // Next Row
    distances_row += stride;
    positions_row += stride;
  }
}

// ------------------------------
// Chamfer Distance Backward Pass
// ------------------------------

void distance_pass1(distance_t* chamfer) {
  int x1, y1, x2, y2;
  // Locate Position
  x1 = chamfer->x;
  y1 = chamfer->y;
  x2 = x1 + chamfer->w;
  y2 = y1 + chamfer->h;

  int stride, count;
  // Buffer Strides
  stride = chamfer->stride;
  count = y2 * stride + x2;
  count -= stride + 1;
  // Buffer Pointers
  unsigned int *distances_row, *distances;
  unsigned int *positions_row, *positions;
  // Buffer Pointer Top
  unsigned int *distances_bot;
  unsigned int *positions_bot;
  // Locate Buffer Pointers
  distances_row = chamfer->distances + count;
  positions_row = chamfer->positions + count;

  // Cursor Distance Pixels
  unsigned int cursor_dist, cursor_pos;
  unsigned int aux_dist, aux_pos;
  // Semi-SIMD Calculations
  __m128i xmm_dist, xmm_pos, ymm0, ymm1;
  __m128i xmm0, xmm1, xmm2, xmm3, xmm4;
  // Semi-SIMD Magic Constants Infinite
  const unsigned int infinite = 2147483647;
  const __m128i xmm_inf = _mm_set1_epi32(infinite);
  // Semi-SIMD Magic Constants MADD
  const __m128i xmm_step = _mm_set_epi16(0, 1, 1, 1, 1, 0, 1, 1);
  const __m128i xmm_madd = _mm_slli_epi16(xmm_step, 1);
  const __m128i xmm_modd = _mm_set_epi32(1, 2, 1, 2);

  // Process First Line
  if (y2 == chamfer->rows) {
    distances = distances_row;
    positions = positions_row;
    // Start Previous Pixels
    aux_pos = aux_dist = infinite;
    
    // Process Only One Side
    for (count = x2; count > x1; count--) {
      cursor_dist = *distances;
      cursor_pos = *positions;

      if (cursor_dist) {
        // Calculate Previous Distance
        aux_dist += ((aux_pos & 0xFFFF) << 1) + 1;

        // Change Current Distance
        if (aux_dist < cursor_dist) {
          cursor_dist = aux_dist;
          cursor_pos = aux_pos + 1;

          *distances = cursor_dist;
          *positions = cursor_pos;
        }
      }

      // Change Previous
      aux_dist = cursor_dist;
      aux_pos = cursor_pos;
      // Next Pixel
      distances--;
      positions--;
    }

    // Next Row
    distances_row -= stride;
    positions_row -= stride;
    // Next Y
    y2--;
  }

  // Process Other Lines
  for (int y = y2; y > y1; y--) {
    distances = distances_row;
    positions = positions_row;
    // Locate Pointers Top
    count = stride - 1;
    distances_bot = distances + count;
    positions_bot = positions + count;
    // Load Pointers Neighbours
    xmm_dist = _mm_loadl_epi64((__m128i*) distances_bot);
    xmm_pos = _mm_loadl_epi64((__m128i*) positions_bot);
    // Insert Two Infinites - 0, 1, X, X
    xmm_dist = _mm_blend_epi16(xmm_dist, xmm_inf, 0xF0);
    xmm_pos = _mm_blend_epi16(xmm_pos, xmm_inf, 0xF0);
    // Locate Pointers Top
    distances_bot--;
    positions_bot--;
    // Start Previous Pixels
    count = x2 - x1;

    while (count > 0) {
      // Load Pixel To XMM
      ymm0 = _mm_loadu_si32(distances);
      ymm1 = _mm_loadu_si32(positions);

      if (_mm_testz_si128(ymm0, ymm0) == 0) {
        xmm0 = _mm_add_epi16(xmm_pos, xmm_step);
        // Calculate Distance Check
        xmm1 = _mm_madd_epi16(xmm_pos, xmm_madd);
        xmm2 = _mm_add_epi32(xmm_dist, xmm_modd);
        xmm1 = _mm_add_epi32(xmm1, xmm2);

        // Find Minimun Distance Pass 0
        xmm2 = _mm_srli_epi64(xmm1, 32);
        xmm4 = _mm_srli_epi64(xmm0, 32);
        xmm1 = _mm_min_epu32(xmm1, xmm2);
        xmm3 = _mm_cmpeq_epi32(xmm1, xmm2);
        xmm0 = _mm_blendv_epi8(xmm0, xmm4, xmm3);

        // Find Minimun Distance Pass 1
        xmm2 = _mm_srli_si128(xmm1, 8);
        xmm4 = _mm_srli_si128(xmm0, 8);
        xmm1 = _mm_min_epu32(xmm1, xmm2);
        xmm3 = _mm_cmpeq_epi32(xmm1, xmm2);
        xmm0 = _mm_blendv_epi8(xmm0, xmm4, xmm3);

        // Find Minimun Distance Pass 2
        ymm0 = _mm_min_epu32(xmm1, ymm0);
        xmm3 = _mm_cmpeq_epi32(xmm1, ymm0);
        ymm1 = _mm_blendv_epi8(ymm1, xmm0, xmm3);

        // Store Minimun Distance
        _mm_storeu_si32(distances, ymm0);
        _mm_storeu_si32(positions, ymm1);
      }

      // Broadcast Distance Pixel
      ymm0 = _mm_shuffle_epi32(ymm0, 0);
      ymm1 = _mm_shuffle_epi32(ymm1, 0);
      // Next Distance Pixel
      xmm_dist = _mm_slli_si128(xmm_dist, 4);
      xmm_pos = _mm_slli_si128(xmm_pos, 4);
      // Change Previous Distance
      xmm0 = _mm_blend_epi16(xmm_dist, ymm0, 0xC0);
      xmm1 = _mm_blend_epi16(xmm_pos, ymm1, 0xC0);
      // Next Distance Pointer
      distances--;
      positions--;

      // Change Next Distance
      if (--count > 1) {
        xmm_dist = _mm_insert_epi32(xmm0, *distances_bot, 0);
        xmm_pos = _mm_insert_epi32(xmm1, *positions_bot, 0);
        // Next Distance Top
        distances_bot--;
        positions_bot--;
        // Next Loop
        continue;
      }

      // Put Distance Infinites
      xmm_dist = _mm_blend_epi16(xmm0, xmm_inf, 0x03);
      xmm_pos = _mm_blend_epi16(xmm1, xmm_inf, 0x03);
    }

    // Next Row
    distances_row -= stride;
    positions_row -= stride;
  }
}
