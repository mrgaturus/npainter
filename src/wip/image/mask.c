// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
#include "image.h"

// -----------------
// Composite Masking
// -----------------

void composite_mask(image_composite_t* co) {

}

void composite_mask_uniform(image_composite_t* co) {

}

// ---------------------
// Composite Passthrough
// ---------------------

__attribute__((always_inline))
static inline __m128i _mm_mix_color(__m128i xmm0, __m128i xmm1, __m128i fract) {
  const __m128i one = _mm_set1_epi32(65535);
  // Calculate Interpolation
  xmm1 = _mm_mullo_epi32(xmm1, fract);
  fract = _mm_sub_epi32(one, fract);
  xmm0 = _mm_mullo_epi32(xmm0, fract);
  xmm0 = _mm_add_epi32(xmm0, xmm1);
  // Adjust 16bit Fixed Point
  xmm0 = _mm_add_epi32(xmm0, one);
  xmm0 = _mm_srli_epi32(xmm0, 16);
  // Return Interpolated
  return xmm0;
}

void composite_pass(image_composite_t* co) {
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

  for (int y = 0; y < h; y++) {
    dst_x = dst_y;
    src_x = src_y;
    int count = w;
    
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

      // Blend Passthrough Pixel Colors
      dst_xmm0 = _mm_mix_color(dst_xmm0, src_xmm0, alpha);
      dst_xmm1 = _mm_mix_color(dst_xmm1, src_xmm1, alpha);
      dst_xmm2 = _mm_mix_color(dst_xmm2, src_xmm2, alpha);
      dst_xmm3 = _mm_mix_color(dst_xmm3, src_xmm3, alpha);
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

// --------------------------
// Composite Passthrough Mask
// --------------------------

void composite_passmask(image_composite_t* co) {

}

void composite_passmask_uniform(image_composite_t* co) {

}
