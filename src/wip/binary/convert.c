// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2022 Cristian Camilo Ruiz <mrgaturus>
#include "binary.h"
#include <smmintrin.h>

// -----------------------
// Color to Binary Convert
// -----------------------

void binary_threshold_color(binary_t* binary) {
  int x1, y1, x2, y2;
  // Conversion Region
  x1 = binary->x;
  y1 = binary->y;
  x2 = x1 + binary->w;
  y2 = y1 + binary->h;

  unsigned int count, len, mask;
  // Conversion Row
  len = x2 - x1;

  unsigned char *buffer_row, *buffer;
  unsigned short *color_row, *color;
  // Binary Buffer Pointers
  buffer_row = binary->buffer;
  color_row = binary->color;
  // Binary Buffer Strides
  const int buffer_s = binary->stride;
  const int color_s = buffer_s << 2;
  // Locate Buffer Pointer
  buffer_row += y1 * buffer_s + x1;
  color_row += y1 * color_s + (x1 << 2);

  __m128i xmm0, xmm1;
  __m128i value, threshold, ones;
  // Color Source & Threshold
  value = _mm_set1_epi32(binary->value);
  threshold = _mm_set1_epi16(binary->threshold);
  ones = _mm_cmpeq_epi32(value, value);
  // Color Source Unpack to 16
  value = _mm_cvtepu8_epi16(value);

  for (int y = y1; y < y2; y++) {
    color = color_row;
    buffer = buffer_row;
    // Row Lenght
    count = len;

    while (count > 0) {
      // Absolute Differente Between Src and Value
      xmm0 = _mm_loadu_si128((__m128i*) color);
      xmm0 = _mm_srli_epi16(xmm0, 8);
      xmm0 = _mm_sub_epi16(xmm0, value);
      xmm0 = _mm_abs_epi16(xmm0);
      // Comprare With Threshold
      xmm0 = _mm_cmplt_epi16(xmm0, threshold);
      xmm0 = _mm_cmpeq_epi64(xmm0, ones);
      xmm0 = _mm_andnot_si128(xmm0, ones);
      // Extract Mask Check
      mask = _mm_movemask_epi8(xmm0);

      // Store Mask
      if (count > 1)
        *((unsigned short*) buffer) = mask;
      else *((unsigned char*) buffer) = mask;

      // Two Pixels
      buffer += 2;
      color += 8;
      // Two Count
      count -= 2;
    }

    // Next Row
    color_row += color_s;
    buffer_row += buffer_s;
  }
}

void binary_threshold_alpha(binary_t* binary) {
  int x1, y1, x2, y2;
  // Conversion Region
  x1 = binary->x;
  y1 = binary->y;
  x2 = x1 + binary->w;
  y2 = y1 + binary->h;

  unsigned char *buffer_row, *buffer;
  unsigned short *color_row, *color;
  // Binary Buffer Pointers
  buffer_row = binary->buffer;
  color_row = binary->color;
  // Binary Buffer Strides
  const int buffer_s = binary->stride;
  const int color_s = buffer_s << 2;
  // Locate Buffer Pointer
  buffer_row += y1 * buffer_s + x1;
  color_row += y1 * color_s + (x1 << 2);
  // Locate to Alpha Channel
  color_row += 3;

  short value, threshold, mask;
  // Alpha Source & Threshold
  value = binary->value >> 24;
  threshold = binary->threshold;

  for (int y = y1; y < y2; y++) {
    color = color_row;
    buffer = buffer_row;

    for (int x = x1; x < x2; x++) {
      mask = *(color) >> 8;
      // Compute Difference
      mask -= value;
      if (mask < 0)
        mask = -mask;
      // Test Difference
      mask = mask > threshold;
      if (mask) mask = 0xFF;
      // Store Computed Mask
      *(buffer) = mask;

      // Step Buffer
      buffer++;
      // Step Color
      color += 4;
    }

    // Next Row
    color_row += color_s;
    buffer_row += buffer_s;
  }
}

// ------------------------------
// Binary to Color Convert Simple
// ------------------------------

void binary_convert_simple(binary_t* binary) {
  int x1, y1, x2, y2;
  // Conversion Region
  x1 = binary->x;
  y1 = binary->y;
  x2 = x1 + binary->w;
  y2 = y1 + binary->h;

  unsigned char *buffer_row, *buffer;
  unsigned short *color_row, *color;
  // Binary Buffer Pointers
  buffer_row = binary->buffer;
  color_row = binary->color;
  // Binary Buffer Strides
  const int buffer_s = binary->stride;
  const int color_s = buffer_s << 2;
  // Locate Buffer Pointer
  buffer_row += y1 * buffer_s + x1;
  color_row += y1 * color_s + (x1 << 2);
  // Binary Check Conversion
  const int check = binary->check;

  __m128i xmm0, xmm1, xmm2;
  // Color Conversion
  xmm0 = _mm_cvtsi32_si128(binary->rgba);
  xmm0 = _mm_cvtepu8_epi16(xmm0);
  xmm1 = _mm_slli_epi16(xmm0, 8);
  xmm0 = _mm_or_si128(xmm0, xmm1);
  // Zero Conversion
  xmm1 = _mm_setzero_si128();

  for (int y = y1; y < y2; y++) {
    color = color_row;
    buffer = buffer_row;

    for (int x = x1; x < x2; x++) {
      xmm2 = *buffer == check ? xmm0 : xmm1;
      _mm_storel_epi64((__m128i*) color, xmm2);

      // Step Buffer
      buffer++;
      // Step Color
      color += 4;
    }

    // Next Row
    color_row += color_s;
    buffer_row += buffer_s;
  }
}

// -----------------------------------
// Binary to Color Convert Antialiased
// -----------------------------------

void binary_convert_smooth(binary_smooth_t* smooth) {
  int x1, y1, x2, y2;
  // Conversion Region
  x1 = smooth->x;
  y1 = smooth->y;
  x2 = x1 + smooth->w;
  y2 = y1 + smooth->h;

  unsigned short *color_row, *color;
  unsigned short *gray_row, *gray;
  // Binary Buffer Pointers
  color_row = (unsigned short*) smooth->magic;
  gray_row = (unsigned short*) smooth->gray;
  const int gray_s = smooth->stride;
  const int color_s = gray_s << 2;
  color_row += y1 * color_s + (x1 << 2);

  __m128i xmm0, xmm1, xmm2;
  // Color Conversion
  xmm0 = _mm_cvtsi32_si128(smooth->rgba);
  xmm0 = _mm_cvtepu8_epi32(xmm0);
  xmm1 = _mm_slli_epi32(xmm0, 8);
  xmm0 = _mm_or_si128(xmm0, xmm1);

  for (int y = y1; y < y2; y++) {
    color = color_row;
    gray = gray_row;

    for (int x = x1; x < x2; x++) {
      xmm1 = _mm_cvtsi32_si128(*gray);
      xmm1 = _mm_shuffle_epi32(xmm1, 0);
      // Apply Magic Value
      xmm2 = _mm_mullo_epi32(xmm0, xmm1);
      xmm2 = _mm_add_epi32(xmm2, xmm1);
      xmm2 = _mm_srli_epi32(xmm2, 15);
      xmm2 = _mm_packus_epi32(xmm2, xmm2);
      // Store Current Color
      _mm_storel_epi64((__m128i*) color, xmm2);
      // Step Pixel
      color += 4;
      gray++;
    }

    // Next Pixel Row
    color_row += color_s;
    gray_row += gray_s;
  }
}
