// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
#include "image.h"

// -----------------
// Composite Masking
// -----------------

void composite_mask(image_composite_t* co) {
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
  __m128i ones = _mm_cmpeq_epi32(zeros, zeros);
  if (co->clip) ones = zeros; // <- Stencil
  // Load Alpha and Unpack to 4x32
  __m128i alpha = _mm_loadu_si32(&co->alpha);
  alpha = _mm_unpacklo_epi16(alpha, alpha);
  alpha = _mm_shuffle_epi32(alpha, 0);

  for (int y = 0; y < h; y++) {
    dst_x = dst_y;
    src_x = src_y;
    int count = w;
    
    // Blend Pixels
    while (count > 0) {
      __m128i mask = _mm_load_si128((__m128i*) src_x);
      mask = _mm_xor_si128(mask, ones);
      mask = _mm_alpha_mask16(mask, alpha);

      // Load 8 Destination Pixels
      dst_xmm0 = _mm_load_si128((__m128i*) dst_x);
      dst_xmm1 = _mm_load_si128((__m128i*) dst_x + 1);
      dst_xmm2 = _mm_load_si128((__m128i*) dst_x + 2);
      dst_xmm3 = _mm_load_si128((__m128i*) dst_x + 3);
      // Unpack 8 Mask Pixels to RGBA
      src_xmm0 = _mm_unpacklo_epi16(mask, mask);
      src_xmm2 = _mm_unpackhi_epi16(mask, mask);
      src_xmm1 = _mm_unpackhi_epi32(src_xmm0, src_xmm0);
      src_xmm0 = _mm_unpacklo_epi32(src_xmm0, src_xmm0);
      src_xmm3 = _mm_unpackhi_epi32(src_xmm2, src_xmm2);
      src_xmm2 = _mm_unpacklo_epi32(src_xmm2, src_xmm2);

      // Apply Source Mask Pixel
      dst_xmm0 = _mm_mul_fix16(dst_xmm0, src_xmm0);
      dst_xmm1 = _mm_mul_fix16(dst_xmm1, src_xmm1);
      dst_xmm2 = _mm_mul_fix16(dst_xmm2, src_xmm2);
      dst_xmm3 = _mm_mul_fix16(dst_xmm3, src_xmm3);

      // Store 8 Pixels
      if (__builtin_expect(count >= 8, 1)) {
        _mm_store_si128((__m128i*) dst_x, dst_xmm0);
        _mm_store_si128((__m128i*) dst_x + 1, dst_xmm1);
        _mm_store_si128((__m128i*) dst_x + 2, dst_xmm2);
        _mm_store_si128((__m128i*) dst_x + 3, dst_xmm3);

        // Next 8 Pixels
        dst_x += 64;
        src_x += 16;
        count -= 8;
        continue;
      }

      // Store 4 Pixels
      if (count >= 4) {
        _mm_store_si128((__m128i*) dst_x, dst_xmm0);
        _mm_store_si128((__m128i*) dst_x + 1, dst_xmm1);
        dst_xmm0 = dst_xmm2;
        dst_xmm1 = dst_xmm3;
        // Next 2 Pixels
        dst_x += 32;
        count -= 4;
      }

      // Store 2 Pixels
      if (count >= 2) {
        _mm_store_si128((__m128i*) dst_x, dst_xmm0);
        dst_xmm0 = dst_xmm1;
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

void composite_mask_uniform(image_composite_t* co) {
  // Load Buffer Pointers
  unsigned char *dst_x, *dst_y;
  dst_y = co->dst.buffer;
  // Load Region
  int w = co->dst.w;
  int h = co->dst.h;
  int s_dst = co->dst.stride;

  // Pixel XMM Registers
  __m128i dst_xmm0, dst_xmm1, dst_xmm2, dst_xmm3;
  const __m128i zeros = _mm_setzero_si128();
  __m128i ones = _mm_cmpeq_epi32(zeros, zeros);
  if (co->clip) ones = zeros; // <- Stencil
  // Load Mask Uniform and Unpack to 4x32
  __m128i mask = _mm_loadl_epi64((__m128i*) co->src.buffer);
  __m128i alpha = _mm_loadu_si32(&co->alpha);
  mask = _mm_xor_si128(mask, ones);
  mask = _mm_unpacklo_epi64(mask, mask);
  alpha = _mm_unpacklo_epi16(alpha, alpha);
  alpha = _mm_shuffle_epi32(alpha, 0);
  mask = _mm_alpha_mask16(mask, alpha);

  for (int y = 0; y < h; y++) {
    dst_x = dst_y;
    int count = w;
    
    // Blend Pixels
    while (count > 0) {
      dst_xmm0 = _mm_load_si128((__m128i*) dst_x);
      dst_xmm1 = _mm_load_si128((__m128i*) dst_x + 1);
      dst_xmm2 = _mm_load_si128((__m128i*) dst_x + 2);
      dst_xmm3 = _mm_load_si128((__m128i*) dst_x + 3);
      // Apply Source Mask Pixel
      dst_xmm0 = _mm_mul_fix16(dst_xmm0, mask);
      dst_xmm1 = _mm_mul_fix16(dst_xmm1, mask);
      dst_xmm2 = _mm_mul_fix16(dst_xmm2, mask);
      dst_xmm3 = _mm_mul_fix16(dst_xmm3, mask);

      // Store 8 Pixels
      if (__builtin_expect(count >= 8, 1)) {
        _mm_store_si128((__m128i*) dst_x, dst_xmm0);
        _mm_store_si128((__m128i*) dst_x + 1, dst_xmm1);
        _mm_store_si128((__m128i*) dst_x + 2, dst_xmm2);
        _mm_store_si128((__m128i*) dst_x + 3, dst_xmm3);

        // Next 8 Pixels
        dst_x += 64;
        count -= 8;
        continue;
      }

      // Store 4 Pixels
      if (count >= 4) {
        _mm_store_si128((__m128i*) dst_x, dst_xmm0);
        _mm_store_si128((__m128i*) dst_x + 1, dst_xmm1);
        dst_xmm0 = dst_xmm2;
        dst_xmm1 = dst_xmm3;
        // Next 2 Pixels
        dst_x += 32;
        count -= 4;
      }

      // Store 2 Pixels
      if (count >= 2) {
        _mm_store_si128((__m128i*) dst_x, dst_xmm0);
        dst_xmm0 = dst_xmm1;
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
  }
}

// ---------------------
// Composite Passthrough
// ---------------------

__attribute__((always_inline))
static inline __m128i _mm_mix_color16(__m128i xmm0, __m128i xmm1, __m128i fract) {
  const __m128i one = _mm_cmpeq_epi16(fract, fract);
  const __m128i inv = _mm_xor_si128(fract, one);

  // mu0 = xmm1 * fract
  // mu1 = xmm0 * (65535 - fract)
  __m128i mu0 = _mm_mulhi_epu16(xmm1, fract);
  __m128i mu1 = _mm_mulhi_epu16(xmm0, inv);
  xmm0 = _mm_or_si128(xmm0, xmm1);
  fract = _mm_or_si128(fract, inv);
  mu0 = _mm_adds_epu16(mu0, mu1);
  // fix = xmm0 | xmm1 | fract | inv >> 15
  xmm0 = _mm_or_si128(xmm0, fract);
  xmm0 = _mm_srli_epi16(xmm0, 15);
  xmm0 = _mm_adds_epu16(mu0, xmm0);

  // mu0 + mu1 + fix
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
  // Load Alpha and Unpack to 4x32
  __m128i alpha = _mm_loadu_si32(&co->alpha);
  alpha = _mm_unpacklo_epi16(alpha, alpha);
  alpha = _mm_shuffle_epi32(alpha, 0);

  for (int y = 0; y < h; y++) {
    dst_x = dst_y;
    src_x = src_y;
    int count = w;
    
    // Blend Pixels
    while (count > 0) {
      src_xmm0 = _mm_load_si128((__m128i*) src_x);
      src_xmm1 = _mm_load_si128((__m128i*) src_x + 1);
      src_xmm2 = _mm_load_si128((__m128i*) src_x + 2);
      src_xmm3 = _mm_load_si128((__m128i*) src_x + 3);
      // Load 8 Destination Pixels
      dst_xmm0 = _mm_load_si128((__m128i*) dst_x);
      dst_xmm1 = _mm_load_si128((__m128i*) dst_x + 1);
      dst_xmm2 = _mm_load_si128((__m128i*) dst_x + 2);
      dst_xmm3 = _mm_load_si128((__m128i*) dst_x + 3);

      // Blend Passthrough Pixel Colors
      dst_xmm0 = _mm_mix_color16(dst_xmm0, src_xmm0, alpha);
      dst_xmm1 = _mm_mix_color16(dst_xmm1, src_xmm1, alpha);
      dst_xmm2 = _mm_mix_color16(dst_xmm2, src_xmm2, alpha);
      dst_xmm3 = _mm_mix_color16(dst_xmm3, src_xmm3, alpha);

      // Store 8 Pixels
      if (__builtin_expect(count >= 8, 1)) {
        _mm_store_si128((__m128i*) dst_x, dst_xmm0);
        _mm_store_si128((__m128i*) dst_x + 1, dst_xmm1);
        _mm_store_si128((__m128i*) dst_x + 2, dst_xmm2);
        _mm_store_si128((__m128i*) dst_x + 3, dst_xmm3);

        // Next 8 Pixels
        dst_x += 64;
        src_x += 64;
        count -= 8;
        continue;
      }

      // Store 4 Pixels
      if (count >= 4) {
        _mm_store_si128((__m128i*) dst_x, dst_xmm0);
        _mm_store_si128((__m128i*) dst_x + 1, dst_xmm1);
        dst_xmm0 = dst_xmm2;
        dst_xmm1 = dst_xmm3;
        // Next 2 Pixels
        dst_x += 32;
        count -= 4;
      }

      // Store 2 Pixels
      if (count >= 2) {
        _mm_store_si128((__m128i*) dst_x, dst_xmm0);
        dst_xmm0 = dst_xmm1;
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
  // Load Buffer Pointers
  unsigned char *dst_x, *dst_y;
  unsigned char *src_x, *src_y;
  unsigned char *ext_x, *ext_y;
  dst_y = co->dst.buffer;
  src_y = co->src.buffer;
  ext_y = co->ext.buffer;

  // Load Region
  int w = co->src.w;
  int h = co->src.h;
  // Load Strides
  int s_src = co->src.stride;
  int s_dst = co->dst.stride;
  int s_ext = co->ext.stride;

  // Pixel Values
  __m128i src_xmm0, src_xmm1, src_xmm2, src_xmm3;
  __m128i ext_xmm0, ext_xmm1, ext_xmm2, ext_xmm3;
  __m128i dst_xmm0, dst_xmm1, dst_xmm2, dst_xmm3;
  const __m128i zeros = _mm_setzero_si128();
  __m128i ones = _mm_cmpeq_epi32(zeros, zeros);
  if (co->clip) ones = zeros; // <- Stencil
  // Load Alpha and Unpack to 4x32
  __m128i alpha = _mm_loadu_si32(&co->alpha);
  alpha = _mm_unpacklo_epi16(alpha, alpha);
  alpha = _mm_shuffle_epi32(alpha, 0);

  for (int y = 0; y < h; y++) {
    dst_x = dst_y;
    src_x = src_y;
    ext_x = ext_y;
    int count = w;
    
    // Blend Pixels
    while (count > 0) {
      __m128i mask = _mm_load_si128((__m128i*) src_x);
      mask = _mm_xor_si128(mask, ones);
      mask = _mm_alpha_mask16(mask, alpha);

      // Load 8 Destination Pixels
      dst_xmm0 = _mm_load_si128((__m128i*) dst_x);
      dst_xmm1 = _mm_load_si128((__m128i*) dst_x + 1);
      dst_xmm2 = _mm_load_si128((__m128i*) dst_x + 2);
      dst_xmm3 = _mm_load_si128((__m128i*) dst_x + 3);
      // Load 8 Source Pixels
      ext_xmm0 = _mm_load_si128((__m128i*) ext_x);
      ext_xmm1 = _mm_load_si128((__m128i*) ext_x + 1);
      ext_xmm2 = _mm_load_si128((__m128i*) ext_x + 2);
      ext_xmm3 = _mm_load_si128((__m128i*) ext_x + 3);

      // Unpack 8 Mask Pixels to RGBA
      src_xmm0 = _mm_unpacklo_epi16(mask, mask);
      src_xmm2 = _mm_unpackhi_epi16(mask, mask);
      src_xmm1 = _mm_unpackhi_epi32(src_xmm0, src_xmm0);
      src_xmm0 = _mm_unpacklo_epi32(src_xmm0, src_xmm0);
      src_xmm3 = _mm_unpackhi_epi32(src_xmm2, src_xmm2);
      src_xmm2 = _mm_unpacklo_epi32(src_xmm2, src_xmm2);

      // Apply Source Mask Pixel
      dst_xmm0 = _mm_mix_color16(ext_xmm0, dst_xmm0, src_xmm0);
      dst_xmm1 = _mm_mix_color16(ext_xmm1, dst_xmm1, src_xmm1);
      dst_xmm2 = _mm_mix_color16(ext_xmm2, dst_xmm2, src_xmm2);
      dst_xmm3 = _mm_mix_color16(ext_xmm3, dst_xmm3, src_xmm3);

      // Store 8 Pixels
      if (__builtin_expect(count >= 8, 1)) {
        _mm_store_si128((__m128i*) dst_x, dst_xmm0);
        _mm_store_si128((__m128i*) dst_x + 1, dst_xmm1);
        _mm_store_si128((__m128i*) dst_x + 2, dst_xmm2);
        _mm_store_si128((__m128i*) dst_x + 3, dst_xmm3);

        // Next 8 Pixels
        dst_x += 64;
        ext_x += 64;
        src_x += 16;
        count -= 8;
        continue;
      }

      // Store 4 Pixels
      if (count >= 4) {
        _mm_store_si128((__m128i*) dst_x, dst_xmm0);
        _mm_store_si128((__m128i*) dst_x + 1, dst_xmm1);
        dst_xmm0 = dst_xmm2;
        dst_xmm1 = dst_xmm3;
        // Next 2 Pixels
        dst_x += 32;
        count -= 4;
      }

      // Store 2 Pixels
      if (count >= 2) {
        _mm_store_si128((__m128i*) dst_x, dst_xmm0);
        dst_xmm0 = dst_xmm1;
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
    ext_y += s_ext;
  }
}

void composite_passmask_uniform(image_composite_t* co) {
  // Load Buffer Pointers
  unsigned char *dst_x, *dst_y;
  unsigned char *src_x, *src_y;
  unsigned char *ext_x, *ext_y;
  dst_y = co->dst.buffer;
  src_y = co->src.buffer;
  ext_y = co->ext.buffer;

  // Load Region
  int w = co->src.w;
  int h = co->src.h;
  // Load Strides
  int s_src = co->src.stride;
  int s_dst = co->dst.stride;
  int s_ext = co->ext.stride;

  // Pixel Values
  __m128i src_xmm0, src_xmm1, src_xmm2, src_xmm3;
  __m128i ext_xmm0, ext_xmm1, ext_xmm2, ext_xmm3;
  __m128i dst_xmm0, dst_xmm1, dst_xmm2, dst_xmm3;
  const __m128i zeros = _mm_setzero_si128();
  __m128i ones = _mm_cmpeq_epi32(zeros, zeros);
  if (co->clip) ones = zeros; // <- Stencil
  // Load Mask Uniform and Unpack to 4x32
  __m128i mask = _mm_loadl_epi64((__m128i*) co->src.buffer);
  __m128i alpha = _mm_loadu_si32(&co->alpha);
  mask = _mm_xor_si128(mask, ones);
  mask = _mm_unpacklo_epi64(mask, mask);
  alpha = _mm_unpacklo_epi16(alpha, alpha);
  alpha = _mm_shuffle_epi32(alpha, 0);
  mask = _mm_alpha_mask16(mask, alpha);

  for (int y = 0; y < h; y++) {
    dst_x = dst_y;
    src_x = src_y;
    ext_x = ext_y;
    int count = w;
    
    // Blend Pixels
    while (count > 0) {
      dst_xmm0 = _mm_load_si128((__m128i*) dst_x);
      dst_xmm1 = _mm_load_si128((__m128i*) dst_x + 1);
      dst_xmm2 = _mm_load_si128((__m128i*) dst_x + 2);
      dst_xmm3 = _mm_load_si128((__m128i*) dst_x + 3);
      // Load 8 Source Pixels
      ext_xmm0 = _mm_load_si128((__m128i*) ext_x);
      ext_xmm1 = _mm_load_si128((__m128i*) ext_x + 1);
      ext_xmm2 = _mm_load_si128((__m128i*) ext_x + 2);
      ext_xmm3 = _mm_load_si128((__m128i*) ext_x + 3);

      // Apply Source Mask Pixel
      dst_xmm0 = _mm_mix_color16(ext_xmm0, dst_xmm0, mask);
      dst_xmm1 = _mm_mix_color16(ext_xmm1, dst_xmm1, mask);
      dst_xmm2 = _mm_mix_color16(ext_xmm2, dst_xmm2, mask);
      dst_xmm3 = _mm_mix_color16(ext_xmm3, dst_xmm3, mask);

      // Store 8 Pixels
      if (__builtin_expect(count >= 8, 1)) {
        _mm_store_si128((__m128i*) dst_x, dst_xmm0);
        _mm_store_si128((__m128i*) dst_x + 1, dst_xmm1);
        _mm_store_si128((__m128i*) dst_x + 2, dst_xmm2);
        _mm_store_si128((__m128i*) dst_x + 3, dst_xmm3);

        // Next 8 Pixels
        dst_x += 64;
        ext_x += 64;
        src_x += 16;
        count -= 8;
        continue;
      }

      // Store 4 Pixels
      if (count >= 4) {
        _mm_store_si128((__m128i*) dst_x, dst_xmm0);
        _mm_store_si128((__m128i*) dst_x + 1, dst_xmm1);
        dst_xmm0 = dst_xmm2;
        dst_xmm1 = dst_xmm3;
        // Next 2 Pixels
        dst_x += 32;
        count -= 4;
      }

      // Store 2 Pixels
      if (count >= 2) {
        _mm_store_si128((__m128i*) dst_x, dst_xmm0);
        dst_xmm0 = dst_xmm1;
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
    ext_y += s_ext;
  }
}
