// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
#include "image.h"
#include <string.h>

static inline __m128i _mm_blend_color(__m128i src, __m128i dst) {
  __m128i xmm0, xmm1;

  // Apply Source Alpha to Destination
  xmm0 = _mm_shuffle_epi32(src, 0xFF);
  xmm1 = _mm_mullo_epi32(dst, xmm0);
  xmm1 = _mm_add_epi32(xmm1, xmm0);
  xmm1 = _mm_srli_epi32(xmm1, 16);
  // SRC + (DST - DST * A_SRC)
  xmm1 = _mm_sub_epi32(dst, xmm1);
  xmm1 = _mm_add_epi32(src, xmm1);

  return xmm1;
}

static inline __m128i _mm_weight_color(__m128i src, __m128i dst) {
  __m128i xmm0, xmm1;

  // Apply Destination Alpha to Source
  xmm0 = _mm_shuffle_epi32(dst, 0xFF);
  xmm1 = _mm_mullo_epi32(src, xmm0);
  xmm1 = _mm_add_epi32(xmm1, xmm0);
  xmm1 = _mm_srli_epi32(xmm1, 16);
  // SRC - SRC * A_DST
  xmm1 = _mm_sub_epi32(src, xmm1);

  return xmm1;
}

// -------------------------
// Composite Normal Blending
// -------------------------

void composite_blend(image_composite_t* co) {
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

  // Pixel Values
  __m128i src_xmm0, src_xmm1, src_xmm2, src_xmm3;
  __m128i dst_xmm0, dst_xmm1, dst_xmm2, dst_xmm3;
  const __m128i zeros = _mm_setzero_si128();
  // Load Alpha and Unpack to 4x32
  __m128i alpha = _mm_loadu_si32(&co->alpha);
  alpha = _mm_shuffle_epi32(alpha, 0);

  for (int count, y = 0; y < h; y++) {
    dst_x = dst_y;
    src_x = src_y;
    count = w;

    // Blend Pixels
    while (count > 0) {
      src_xmm0 = _mm_load_si128((__m128i*) src_x);
      src_xmm2 = _mm_load_si128((__m128i*) src_x + 1);
      dst_xmm0 = _mm_load_si128((__m128i*) dst_x);
      dst_xmm2 = _mm_load_si128((__m128i*) dst_x + 1);

      // Unpack to 4x32 bit Color
      src_xmm1 = _mm_unpacklo_epi16(src_xmm0, zeros);
      dst_xmm1 = _mm_unpacklo_epi16(dst_xmm0, zeros);
      src_xmm0 = _mm_unpackhi_epi16(src_xmm0, zeros);
      dst_xmm0 = _mm_unpackhi_epi16(dst_xmm0, zeros);
      src_xmm3 = _mm_unpacklo_epi16(src_xmm2, zeros);
      dst_xmm3 = _mm_unpacklo_epi16(dst_xmm2, zeros);
      src_xmm2 = _mm_unpackhi_epi16(src_xmm2, zeros);
      dst_xmm2 = _mm_unpackhi_epi16(dst_xmm2, zeros);

      // Apply Opacity to Source Pixels
      src_xmm0 = _mm_multiply_color(src_xmm0, alpha);
      src_xmm1 = _mm_multiply_color(src_xmm1, alpha);
      src_xmm2 = _mm_multiply_color(src_xmm2, alpha);
      src_xmm3 = _mm_multiply_color(src_xmm3, alpha);
      // Apply Blending to Destination Pixels
      dst_xmm0 = _mm_blend_color(src_xmm0, dst_xmm0);
      dst_xmm1 = _mm_blend_color(src_xmm1, dst_xmm1);
      dst_xmm2 = _mm_blend_color(src_xmm2, dst_xmm2);
      dst_xmm3 = _mm_blend_color(src_xmm3, dst_xmm3);
      // Pack Destination Pixels to 8x16 bit channels
      dst_xmm0 = _mm_packus_epi32(dst_xmm1, dst_xmm0);
      dst_xmm2 = _mm_packus_epi32(dst_xmm3, dst_xmm2);

      // Store 4 Pixels
      if (__builtin_expect(count >= 4, 1)) {
        _mm_store_si128((__m128i*) dst_x, dst_xmm0);
        _mm_store_si128((__m128i*) dst_x + 1, dst_xmm2);

        // Next 4 Pixels
        dst_x += 32;
        src_x += 32;
        count -= 4;
        continue;
      }

      // Store 2 Pixels
      if (count >= 2) {
        _mm_store_si128((__m128i*) dst_x, dst_xmm0);
        dst_xmm0 = dst_xmm2;
        // Next 2 Pixels
        dst_x += 16;
        count -= 2;
      }

      // Store 1 Pixel
      if (count == 1) {
        _mm_storel_epi64((__m128i*) dst_x, dst_xmm0);
        // No More Pixels
        count--;
      }
    }

    // Step Y Buffers
    dst_y += s_dst;
    src_y += s_src;
  }
}

void composite_blend_uniform(image_composite_t* co) {
  // Load Buffer Pointers
  unsigned char *dst_x, *dst_y;
  dst_y = co->dst.buffer;

  int w, h, s_dst;
  // Load Region
  w = co->src.w;
  h = co->src.h;
  // Load Strides
  s_dst = co->dst.stride;

  __m128i color, xmm0, xmm1, xmm2, xmm3;
  // Load Color and Initialize Zeros
  const __m128i zeros = _mm_setzero_si128();
  color = _mm_loadl_epi64((__m128i*) co->src.buffer);
  color = _mm_cvtepu16_epi32(color);
  // Load Alpha and Apply to Color
  xmm0 = _mm_loadu_si32(&co->alpha);
  xmm0 = _mm_shuffle_epi32(xmm0, 0);
  color = _mm_multiply_color(color, xmm0);

  for (int count, y = 0; y < h; y++) {
    dst_x = dst_y;
    count = w;

    // Blend Pixels
    while (count > 0) {
      xmm0 = _mm_load_si128((__m128i*) dst_x);
      xmm1 = _mm_load_si128((__m128i*) dst_x + 1);
      // Unpack to 4x32 bit Color
      xmm3 = _mm_unpackhi_epi16(xmm1, zeros);
      xmm2 = _mm_unpacklo_epi16(xmm1, zeros);
      xmm1 = _mm_unpackhi_epi16(xmm0, zeros);
      xmm0 = _mm_unpacklo_epi16(xmm0, zeros);
      // Blend Normal Mode Pixels
      xmm0 = _mm_blend_color(color, xmm0);
      xmm1 = _mm_blend_color(color, xmm1);
      xmm2 = _mm_blend_color(color, xmm2);
      xmm3 = _mm_blend_color(color, xmm3);
      // Pack to 8x16 bit Color
      xmm0 = _mm_packus_epi32(xmm0, xmm1);
      xmm2 = _mm_packus_epi32(xmm2, xmm3);

      // Store 4 Pixels
      if (__builtin_expect(count >= 4, 1)) {
        _mm_store_si128((__m128i*) dst_x, xmm0);
        _mm_store_si128((__m128i*) dst_x + 1, xmm2);
        // Next 4 Pixels
        dst_x += 32;
        count -= 4;
        continue;
      }

      // Store 2 Pixels
      if (count >= 2) {
        _mm_store_si128((__m128i*) dst_x, xmm0);
        xmm0 = xmm2;
        // Next 2 Pixels
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
    dst_y += s_dst;
  }
}

// ---------------------------
// Composite Function Blending
// ---------------------------

void composite_fn(image_composite_t* co) {
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
  // Load Blending Function
  blend_proc_t fn = co->fn;

  // Pixel Values
  __m128i src_xmm0, src_xmm1, src_xmm2, src_xmm3;
  __m128i dst_xmm0, dst_xmm1, dst_xmm2, dst_xmm3;
  const __m128i zeros = _mm_setzero_si128();
  // Load Alpha and Unpack to 4x32
  __m128i alpha = _mm_loadu_si32(&co->alpha);
  alpha = _mm_shuffle_epi32(alpha, 0);
  // Load Clipping and Unpack to 4x32
  __m128i clip = _mm_loadu_si32(&co->clip);
  clip = _mm_shuffle_epi32(clip, 0);
  clip = _mm_cmpeq_epi32(clip, zeros);

  for (int count, y = 0; y < h; y++) {
    dst_x = dst_y;
    src_x = src_y;
    count = w;

    // Blend Pixels
    while (count > 0) {
      src_xmm0 = _mm_load_si128((__m128i*) src_x);
      dst_xmm0 = _mm_load_si128((__m128i*) dst_x);
      // Unpack to 4x32 bit Color
      src_xmm1 = _mm_unpacklo_epi16(src_xmm0, zeros);
      dst_xmm1 = _mm_unpacklo_epi16(dst_xmm0, zeros);
      src_xmm0 = _mm_unpackhi_epi16(src_xmm0, zeros);
      dst_xmm0 = _mm_unpackhi_epi16(dst_xmm0, zeros);
      // Apply Opacity to Source Pixels
      src_xmm0 = _mm_multiply_color(src_xmm0, alpha);
      src_xmm1 = _mm_multiply_color(src_xmm1, alpha);

      // Porter-Duff Blending Function
      src_xmm2 = fn(src_xmm0, dst_xmm0);
      src_xmm3 = fn(src_xmm1, dst_xmm1);
      // Porter-Duff Source/Destination Weights
      dst_xmm2 = _mm_weight_color(dst_xmm0, src_xmm0);
      dst_xmm3 = _mm_weight_color(dst_xmm1, src_xmm1);
      src_xmm0 = _mm_weight_color(src_xmm0, dst_xmm0);
      src_xmm1 = _mm_weight_color(src_xmm1, dst_xmm1);
      src_xmm0 = _mm_and_si128(src_xmm0, clip);
      src_xmm1 = _mm_and_si128(src_xmm1, clip);
      // fn + (s - s * da) + (d - d * sa)
      dst_xmm2 = _mm_add_epi32(src_xmm0, dst_xmm2);
      dst_xmm3 = _mm_add_epi32(src_xmm1, dst_xmm3);
      dst_xmm0 = _mm_add_epi32(src_xmm2, dst_xmm2);
      dst_xmm1 = _mm_add_epi32(src_xmm3, dst_xmm3);
      // Pack Destination Pixels to 8x16 bit channels
      dst_xmm0 = _mm_packus_epi32(dst_xmm1, dst_xmm0);

      // Store 2 Pixels
      if (__builtin_expect(count >= 2, 1)) {
        _mm_store_si128((__m128i*) dst_x, dst_xmm0);
        // Next 2 Pixels
        dst_x += 16;
        src_x += 16;
        count -= 2;
        continue;
      }

      // Store 1 Pixel
      if (count == 1) {
        _mm_storel_epi64((__m128i*) dst_x, dst_xmm0);
        // No More Pixels
        count--;
      }
    }

    // Step Y Buffers
    dst_y += s_dst;
    src_y += s_src;
  }
}

void composite_fn_uniform(image_composite_t* co) {
  // Load Buffer Pointers
  unsigned char *dst_x, *dst_y;
  dst_y = co->dst.buffer;

  int w, h, s_dst;
  // Load Region
  w = co->src.w;
  h = co->src.h;
  // Load Strides
  s_dst = co->dst.stride;
  // Load Blending Function
  blend_proc_t fn = co->fn;

  __m128i color, clip;
  __m128i src_xmm0, src_xmm1, src_xmm2, src_xmm3;
  __m128i dst_xmm0, dst_xmm1, dst_xmm2, dst_xmm3;
  // Load Color and Initialize Zeros
  const __m128i zeros = _mm_setzero_si128();
  color = _mm_loadl_epi64((__m128i*) co->src.buffer);
  color = _mm_cvtepu16_epi32(color);
 // Load Clipping and Unpack to 4x32
  clip = _mm_loadu_si32(&co->clip);
  clip = _mm_shuffle_epi32(clip, 0);
  clip = _mm_cmpeq_epi32(clip, zeros);
  // Load Alpha and Apply to Color
  src_xmm0 = _mm_loadu_si32(&co->alpha);
  src_xmm0 = _mm_shuffle_epi32(src_xmm0, 0);
  color = _mm_multiply_color(color, src_xmm0);

  for (int count, y = 0; y < h; y++) {
    dst_x = dst_y;
    count = w;

    // Blend Pixels
    while (count > 0) {
      dst_xmm0 = _mm_load_si128((__m128i*) dst_x);
      // Unpack to 4x32 bit Color
      dst_xmm1 = _mm_unpacklo_epi16(dst_xmm0, zeros);
      dst_xmm0 = _mm_unpackhi_epi16(dst_xmm0, zeros);

      // Porter-Duff Blending Function
      src_xmm0 = fn(color, dst_xmm0);
      src_xmm1 = fn(color, dst_xmm1);
      // Porter-Duff Source/Destination Weights
      src_xmm2 = _mm_weight_color(color, dst_xmm0);
      src_xmm3 = _mm_weight_color(color, dst_xmm1);
      dst_xmm2 = _mm_weight_color(dst_xmm0, color);
      dst_xmm3 = _mm_weight_color(dst_xmm1, color);
      src_xmm2 = _mm_and_si128(src_xmm2, clip);
      src_xmm3 = _mm_and_si128(src_xmm3, clip);
      // fn + (s - s * da) + (d - d * sa)
      dst_xmm2 = _mm_add_epi32(src_xmm2, dst_xmm2);
      dst_xmm3 = _mm_add_epi32(src_xmm3, dst_xmm3);
      dst_xmm0 = _mm_add_epi32(src_xmm0, dst_xmm2);
      dst_xmm1 = _mm_add_epi32(src_xmm1, dst_xmm3);
      // Pack Destination Pixels to 8x16 bit channels
      dst_xmm0 = _mm_packus_epi32(dst_xmm1, dst_xmm0);

      // Store 2 Pixels
      if (__builtin_expect(count >= 2, 1)) {
        _mm_store_si128((__m128i*) dst_x, dst_xmm0);
        // Next 2 Pixels
        dst_x += 16;
        count -= 2;
        continue;
      }

      // Store 1 Pixel
      if (count == 1) {
        _mm_storel_epi64((__m128i*) dst_x, dst_xmm0);
        // No More Pixels
        count--;
      }
    }

    // Step Y Buffers
    dst_y += s_dst;
  }
}
