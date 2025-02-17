// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Cristian Camilo Ruiz <mrgaturus>
#include "mask.h"
#include <string.h>

// ---------------------
// Polygon Line Location
// ---------------------

void polygon_line_range(polygon_line_t* line, int x0, int x1) {
  line->x0 = x0; line->x1 = x1;
}

void polygon_line_skip(polygon_line_t* line, int y0) {
  int oy = line->skip + y0;
  line->skip = oy; oy >>= 8;
  // Locate Buffer Pointer
  long long stride = line->stride;
  unsigned char* buffer = line->buffer;
  line->cursor = buffer + (stride * oy);
}

void polygon_line_clear(polygon_line_t* line) {
  void* cursor = line->cursor;
  long long bytes = line->stride;

  // Check Smooth Buffer
  void* smooth = line->smooth;
  if (smooth) {
    cursor = smooth;
    bytes <<= 1;
  }

  // Zero Fill Current Line
  memset(cursor, 0, bytes);
}

void polygon_line_next(polygon_line_t* line) {
  line->cursor += line->stride;
}


// ----------------------------------
// Polygon Line Rasterization: Simple
// ----------------------------------

void polygon_line_simple(polygon_line_t* line) {
  int x0 = (line->x0 - line->offset) >> 8;
  int x1 = (line->x1 - line->offset) >> 8;

  // Write Un-Aligned 16 Bytes
  const __m128i ones = _mm_cmpeq_epi32(ones, ones);
  unsigned char* cursor = line->cursor + x0;
  for (; (x0 & 15) && x0 < x1; x0++)
    *(cursor++) = 0xFF;

  // Write Aligned 128 Bytes
  int count = x1 - x0;
  while (count >= 128) {
    _mm_stream_si128((__m128i*) cursor + 0, ones);
    _mm_stream_si128((__m128i*) cursor + 1, ones);
    _mm_stream_si128((__m128i*) cursor + 2, ones);
    _mm_stream_si128((__m128i*) cursor + 3, ones);
    _mm_stream_si128((__m128i*) cursor + 4, ones);
    _mm_stream_si128((__m128i*) cursor + 5, ones);
    _mm_stream_si128((__m128i*) cursor + 6, ones);
    _mm_stream_si128((__m128i*) cursor + 7, ones);
    cursor += 128; count -= 128;
  }

  // Write Aligned 64 Bytes
  if (count >= 64) {
    _mm_stream_si128((__m128i*) cursor + 0, ones);
    _mm_stream_si128((__m128i*) cursor + 1, ones);
    _mm_stream_si128((__m128i*) cursor + 2, ones);
    _mm_stream_si128((__m128i*) cursor + 3, ones);
    cursor += 64; count -= 64;
  }

  // Write Aligned 32 Bytes
  if (count >= 32) {
    _mm_stream_si128((__m128i*) cursor + 0, ones);
    _mm_stream_si128((__m128i*) cursor + 1, ones);
    cursor += 32; count -= 32;
  }

  // Write Aligned 16 Bytes
  if (count >= 16) {
    _mm_stream_si128((__m128i*) cursor, ones);
    cursor += 16; count -= 16;
  }

  // Write Aligned 8 Bytes
  if (count >= 8) {
    _mm_storel_epi64((__m128i*) cursor, ones);
    cursor += 8; count -= 8;
  }

  // Write Residual
  while (count-- > 0)
    *(cursor++) = 0xFF;
}

// ----------------------------------
// Polygon line Rasterization: Smooth
// ----------------------------------

void polygon_line_coverage(polygon_line_t* line) {
  int fix0 = (line->x0 - line->offset) >> 4;
  int fix1 = (line->x1 - line->offset) >> 4;
  int x0 = fix0 >> 4;
  int x1 = fix1 >> 4;

  // Write Coverage Residuals
  unsigned short* smooth = line->smooth;
  if (x0 == x1) { smooth[x0] += fix1 - fix0; return; }
  if (fix0 & 0xF) { smooth[x0] += 16 - (fix0 & 0xF); x0++; }
  if (fix1 & 0xF) { smooth[x1] += fix1 & 0xF; }
  smooth += x0;

  __m128i xmm0, xmm1, xmm2, xmm3;
  __m128i xmm4, xmm5, xmm6, xmm7;
  // Coverage Un-Aligned 16 Bytes
  const __m128i ones = _mm_set1_epi16(16);
  for (; (x0 & 7) && x0 < x1; x0++)
    *(smooth++) += 16;

  // Write Aligned 128 Bytes
  int count = x1 - x0;
  while (count >= 64) {
    xmm0 = _mm_load_si128((__m128i*) smooth + 0);
    xmm1 = _mm_load_si128((__m128i*) smooth + 1);
    xmm2 = _mm_load_si128((__m128i*) smooth + 2);
    xmm3 = _mm_load_si128((__m128i*) smooth + 3);
    xmm4 = _mm_load_si128((__m128i*) smooth + 4);
    xmm5 = _mm_load_si128((__m128i*) smooth + 5);
    xmm6 = _mm_load_si128((__m128i*) smooth + 6);
    xmm7 = _mm_load_si128((__m128i*) smooth + 7);
    xmm0 = _mm_adds_epu16(xmm0, ones);
    xmm1 = _mm_adds_epu16(xmm1, ones);
    xmm2 = _mm_adds_epu16(xmm2, ones);
    xmm3 = _mm_adds_epu16(xmm3, ones);
    xmm4 = _mm_adds_epu16(xmm4, ones);
    xmm5 = _mm_adds_epu16(xmm5, ones);
    xmm6 = _mm_adds_epu16(xmm6, ones);
    xmm7 = _mm_adds_epu16(xmm7, ones);
    // Store Full Coveraged 128 Bytes
    _mm_store_si128((__m128i*) smooth + 0, xmm0);
    _mm_store_si128((__m128i*) smooth + 1, xmm1);
    _mm_store_si128((__m128i*) smooth + 2, xmm2);
    _mm_store_si128((__m128i*) smooth + 3, xmm3);
    _mm_store_si128((__m128i*) smooth + 4, xmm4);
    _mm_store_si128((__m128i*) smooth + 5, xmm5);
    _mm_store_si128((__m128i*) smooth + 6, xmm6);
    _mm_store_si128((__m128i*) smooth + 7, xmm7);
    smooth += 64; count -= 64;
  }

  // Write Aligned 64 Bytes
  if (count >= 32) {
    xmm0 = _mm_load_si128((__m128i*) smooth + 0);
    xmm1 = _mm_load_si128((__m128i*) smooth + 1);
    xmm2 = _mm_load_si128((__m128i*) smooth + 2);
    xmm3 = _mm_load_si128((__m128i*) smooth + 3);
    xmm0 = _mm_adds_epu16(xmm0, ones);
    xmm1 = _mm_adds_epu16(xmm1, ones);
    xmm2 = _mm_adds_epu16(xmm2, ones);
    xmm3 = _mm_adds_epu16(xmm3, ones);
    // Store Full Coveraged 64 Bytes
    _mm_store_si128((__m128i*) smooth + 0, xmm0);
    _mm_store_si128((__m128i*) smooth + 1, xmm1);
    _mm_store_si128((__m128i*) smooth + 2, xmm2);
    _mm_store_si128((__m128i*) smooth + 3, xmm3);
    smooth += 32; count -= 32;
  }

  // Write Aligned 32 Bytes
  if (count >= 16) {
    xmm0 = _mm_load_si128((__m128i*) smooth + 0);
    xmm1 = _mm_load_si128((__m128i*) smooth + 1);
    xmm0 = _mm_adds_epu16(xmm0, ones);
    xmm1 = _mm_adds_epu16(xmm1, ones);
    // Store Full Coveraged 32 Bytes
    _mm_store_si128((__m128i*) smooth + 0, xmm0);
    _mm_store_si128((__m128i*) smooth + 1, xmm1);
    smooth += 16; count -= 16;
  }

  // Write Aligned 16 Bytes
  if (count >= 8) {
    xmm0 = _mm_load_si128((__m128i*) smooth);
    xmm0 = _mm_adds_epu16(xmm0, ones);
    // Store Full Coveraged 16 Bytes
    _mm_store_si128((__m128i*) smooth, xmm0);
    smooth += 8; count -= 8;
  }

  // Write Aligned 8 Bytes
  if (count >= 4) {
    xmm0 = _mm_loadl_epi64((__m128i*) smooth);
    xmm0 = _mm_adds_epu16(xmm0, ones);
    // Store Full Coveraged 8 Bytes
    _mm_storel_epi64((__m128i*) smooth, xmm0);
    smooth += 4; count -= 4;
  }

  // Write Residual
  while (count-- > 0)
    *(smooth++) += 16;
}

void polygon_line_smooth(polygon_line_t* line) {
  unsigned short* smooth = line->smooth;
  unsigned char* cursor = line->cursor;
  int count = line->stride;

  __m128i xmm0, xmm1, xmm2, xmm3;
  __m128i xmm4, xmm5, xmm6, xmm7;
  const __m128i ones = _mm_set1_epi16(255);

  while (count >= 8) {
    xmm0 = _mm_load_si128((__m128i*) smooth + 0);
    xmm1 = _mm_load_si128((__m128i*) smooth + 1);
    xmm2 = _mm_load_si128((__m128i*) smooth + 2);
    xmm3 = _mm_load_si128((__m128i*) smooth + 3);
    xmm4 = _mm_load_si128((__m128i*) smooth + 4);
    xmm5 = _mm_load_si128((__m128i*) smooth + 5);
    xmm6 = _mm_load_si128((__m128i*) smooth + 6);
    xmm7 = _mm_load_si128((__m128i*) smooth + 7);

    xmm0 = _mm_mullo_epi16(xmm0, ones);
    xmm1 = _mm_mullo_epi16(xmm1, ones);
    xmm2 = _mm_mullo_epi16(xmm2, ones);
    xmm3 = _mm_mullo_epi16(xmm3, ones);
    xmm4 = _mm_mullo_epi16(xmm4, ones);
    xmm5 = _mm_mullo_epi16(xmm5, ones);
    xmm6 = _mm_mullo_epi16(xmm6, ones);
    xmm7 = _mm_mullo_epi16(xmm7, ones);

    xmm0 = _mm_srli_epi16(xmm0, 8);
    xmm1 = _mm_srli_epi16(xmm1, 8);
    xmm2 = _mm_srli_epi16(xmm2, 8);
    xmm3 = _mm_srli_epi16(xmm3, 8);
    xmm4 = _mm_srli_epi16(xmm4, 8);
    xmm5 = _mm_srli_epi16(xmm5, 8);
    xmm6 = _mm_srli_epi16(xmm6, 8);
    xmm7 = _mm_srli_epi16(xmm7, 8);

    xmm0 = _mm_packus_epi16(xmm0, xmm1);
    xmm2 = _mm_packus_epi16(xmm2, xmm3);
    xmm4 = _mm_packus_epi16(xmm4, xmm5);
    xmm6 = _mm_packus_epi16(xmm6, xmm7);

    if (__builtin_expect(count >= 64, 1)) {
      _mm_stream_si128((__m128i*) cursor + 0, xmm0);
      _mm_stream_si128((__m128i*) cursor + 1, xmm2);
      _mm_stream_si128((__m128i*) cursor + 2, xmm4);
      _mm_stream_si128((__m128i*) cursor + 3, xmm6);
      count -= 64; cursor += 64; smooth += 64;
      // Next 64 Bytes
      continue;
    }

    if (count >= 32) {
      _mm_stream_si128((__m128i*) cursor + 0, xmm0);
      _mm_stream_si128((__m128i*) cursor + 1, xmm2);
      xmm0 = xmm4; xmm2 = xmm6;
      // Next 32 Bytes
      count -= 32;
      cursor += 32;
    }

    if (count >= 16) {
      _mm_stream_si128((__m128i*) cursor, xmm0);
      xmm0 = xmm2;
      // Next 16 Bytes
      count -= 16;
      cursor += 16;
    }

    if (count >= 8) {
      _mm_storel_epi64((__m128i*) cursor, xmm0);
      // Next 8 Bytes
      count -= 8;
      cursor += 8;
    }
  }
}
