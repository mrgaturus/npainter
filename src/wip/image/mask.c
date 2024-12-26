// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
#include "image.h"

// -----------------
// Composite Masking
// -----------------

__attribute__((always_inline))
static inline __m128i _mm_multiply_mask(__m128i xmm0, __m128i fract) {
  const __m128i ones = _mm_cmpeq_epi32(xmm0, xmm0);
  xmm0 = _mm_xor_si128(xmm0, ones);

  __m128i xmm1 = _mm_mullo_epi32(xmm0, fract);
  xmm1 = _mm_add_epi32(xmm1, ones);
  xmm1 = _mm_srli_epi32(xmm1, 16);
  // xmm0 + (fract - fract * xmm0)
  fract = _mm_sub_epi32(fract, xmm1);
  xmm0 = _mm_add_epi32(xmm0, fract);

  return xmm1;
}

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
  // Load Alpha and Unpack to 4x32
  __m128i alpha = _mm_loadu_si32(&co->alpha);
  alpha = _mm_shuffle_epi32(alpha, 0);

  for (int y = 0; y < h; y++) {
    dst_x = dst_y;
    src_x = src_y;
    int count = w;
    
    // Blend Pixels
    while (count > 0) {
      __m128i mask =  _mm_loadl_epi64((__m128i*) src_x);
      dst_xmm0 = _mm_load_si128((__m128i*) dst_x);
      dst_xmm2 = _mm_load_si128((__m128i*) dst_x + 1);
      mask = _mm_cvtepu16_epi32(mask);
      // Unpack Source Mask Pixels
      src_xmm0 = _mm_shuffle_epi32(mask, _MM_SHUFFLE(0, 0, 0, 0));
      src_xmm1 = _mm_shuffle_epi32(mask, _MM_SHUFFLE(1, 1, 1, 1));
      src_xmm2 = _mm_shuffle_epi32(mask, _MM_SHUFFLE(2, 2, 2, 2));
      src_xmm3 = _mm_shuffle_epi32(mask, _MM_SHUFFLE(3, 3, 3, 3));
      // Unpack Destination Color Pixels
      dst_xmm1 = _mm_unpacklo_epi16(dst_xmm0, zeros);
      dst_xmm0 = _mm_unpackhi_epi16(dst_xmm0, zeros);
      dst_xmm3 = _mm_unpacklo_epi16(dst_xmm2, zeros);
      dst_xmm2 = _mm_unpackhi_epi16(dst_xmm2, zeros);

      // Apply Mask Pixel Opacity
      src_xmm0 = _mm_multiply_mask(src_xmm0, alpha);
      src_xmm1 = _mm_multiply_mask(src_xmm1, alpha);
      src_xmm2 = _mm_multiply_mask(src_xmm2, alpha);
      src_xmm3 = _mm_multiply_mask(src_xmm3, alpha);
      // Apply Source Mask Pixel
      dst_xmm0 = _mm_multiply_color(dst_xmm0, src_xmm0);
      dst_xmm1 = _mm_multiply_color(dst_xmm1, src_xmm1);
      dst_xmm2 = _mm_multiply_color(dst_xmm2, src_xmm2);
      dst_xmm3 = _mm_multiply_color(dst_xmm3, src_xmm3);
      // Pack Destination Pixels to 8x16 bit channels
      dst_xmm0 = _mm_packus_epi32(dst_xmm1, dst_xmm0);
      dst_xmm2 = _mm_packus_epi32(dst_xmm3, dst_xmm2);

      // Store 4 Pixels
      if (__builtin_expect(count >= 4, 1)) {
        _mm_store_si128((__m128i*) dst_x, dst_xmm0);
        _mm_store_si128((__m128i*) dst_x + 1, dst_xmm2);

        // Next 4 Pixels
        dst_x += 32;
        src_x += 8;
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
  // Load Alpha and Unpack to 4x32
  __m128i mask = _mm_loadl_epi64((__m128i*) co->src.buffer);
  __m128i alpha = _mm_loadu_si32(&co->alpha);
  mask = _mm_cvtepu16_epi32(mask);
  alpha = _mm_shuffle_epi32(alpha, 0);
  mask = _mm_multiply_mask(mask, alpha);

  for (int y = 0; y < h; y++) {
    dst_x = dst_y;
    int count = w;
    
    // Blend Pixels
    while (count > 0) {
      dst_xmm0 = _mm_load_si128((__m128i*) dst_x);
      dst_xmm2 = _mm_load_si128((__m128i*) dst_x + 1);
      // Unpack Destination Color Pixels
      dst_xmm1 = _mm_unpacklo_epi16(dst_xmm0, zeros);
      dst_xmm0 = _mm_unpackhi_epi16(dst_xmm0, zeros);
      dst_xmm3 = _mm_unpacklo_epi16(dst_xmm2, zeros);
      dst_xmm2 = _mm_unpackhi_epi16(dst_xmm2, zeros);

      // Apply Source Mask Pixel
      dst_xmm0 = _mm_multiply_color(dst_xmm0, mask);
      dst_xmm1 = _mm_multiply_color(dst_xmm1, mask);
      dst_xmm2 = _mm_multiply_color(dst_xmm2, mask);
      dst_xmm3 = _mm_multiply_color(dst_xmm3, mask);
      // Pack Destination Pixels to 8x16 bit channels
      dst_xmm0 = _mm_packus_epi32(dst_xmm1, dst_xmm0);
      dst_xmm2 = _mm_packus_epi32(dst_xmm3, dst_xmm2);

      // Store 4 Pixels
      if (__builtin_expect(count >= 4, 1)) {
        _mm_store_si128((__m128i*) dst_x, dst_xmm0);
        _mm_store_si128((__m128i*) dst_x + 1, dst_xmm2);

        // Next 4 Pixels
        dst_x += 32;
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
  }
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
  // Load Alpha and Unpack to 4x32
  __m128i alpha = _mm_loadu_si32(&co->alpha);
  alpha = _mm_shuffle_epi32(alpha, 0);

  for (int y = 0; y < h; y++) {
    dst_x = dst_y;
    src_x = src_y;
    ext_x = ext_y;
    int count = w;
    
    // Blend Pixels
    while (count > 0) {
      __m128i mask =  _mm_loadl_epi64((__m128i*) src_x);
      dst_xmm0 = _mm_load_si128((__m128i*) dst_x);
      dst_xmm2 = _mm_load_si128((__m128i*) dst_x + 1);
      ext_xmm0 = _mm_load_si128((__m128i*) ext_x);
      ext_xmm2 = _mm_load_si128((__m128i*) ext_x + 1);
      mask = _mm_cvtepu16_epi32(mask);
      // Unpack Source Mask Pixels
      src_xmm0 = _mm_shuffle_epi32(mask, _MM_SHUFFLE(0, 0, 0, 0));
      src_xmm1 = _mm_shuffle_epi32(mask, _MM_SHUFFLE(1, 1, 1, 1));
      src_xmm2 = _mm_shuffle_epi32(mask, _MM_SHUFFLE(2, 2, 2, 2));
      src_xmm3 = _mm_shuffle_epi32(mask, _MM_SHUFFLE(3, 3, 3, 3));
      // Unpack Destination Color Pixels
      dst_xmm1 = _mm_unpacklo_epi16(dst_xmm0, zeros);
      dst_xmm0 = _mm_unpackhi_epi16(dst_xmm0, zeros);
      dst_xmm3 = _mm_unpacklo_epi16(dst_xmm2, zeros);
      dst_xmm2 = _mm_unpackhi_epi16(dst_xmm2, zeros);
      // Unpack Lower Scope Color Pixels
      ext_xmm1 = _mm_unpacklo_epi16(ext_xmm0, zeros);
      ext_xmm0 = _mm_unpackhi_epi16(ext_xmm0, zeros);
      ext_xmm3 = _mm_unpacklo_epi16(ext_xmm2, zeros);
      ext_xmm2 = _mm_unpackhi_epi16(ext_xmm2, zeros);

      // Apply Mask Pixel Opacity
      src_xmm0 = _mm_multiply_mask(src_xmm0, alpha);
      src_xmm1 = _mm_multiply_mask(src_xmm1, alpha);
      src_xmm2 = _mm_multiply_mask(src_xmm2, alpha);
      src_xmm3 = _mm_multiply_mask(src_xmm3, alpha);
      // Apply Source Mask Pixel
      dst_xmm0 = _mm_mix_color(dst_xmm0, ext_xmm0, src_xmm0);
      dst_xmm1 = _mm_mix_color(dst_xmm1, ext_xmm1, src_xmm1);
      dst_xmm2 = _mm_mix_color(dst_xmm2, ext_xmm2, src_xmm2);
      dst_xmm3 = _mm_mix_color(dst_xmm3, ext_xmm3, src_xmm3);
      // Pack Destination Pixels to 8x16 bit channels
      dst_xmm0 = _mm_packus_epi32(dst_xmm1, dst_xmm0);
      dst_xmm2 = _mm_packus_epi32(dst_xmm3, dst_xmm2);

      // Store 4 Pixels
      if (__builtin_expect(count >= 4, 1)) {
        _mm_store_si128((__m128i*) dst_x, dst_xmm0);
        _mm_store_si128((__m128i*) dst_x + 1, dst_xmm2);

        // Next 4 Pixels
        dst_x += 32;
        ext_x += 32;
        src_x += 8;
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
  // Load Alpha and Unpack to 4x32
  __m128i mask = _mm_loadl_epi64((__m128i*) co->src.buffer);
  __m128i alpha = _mm_loadu_si32(&co->alpha);
  mask = _mm_cvtepu16_epi32(mask);
  alpha = _mm_shuffle_epi32(alpha, 0);
  mask = _mm_multiply_mask(mask, alpha);

  for (int y = 0; y < h; y++) {
    dst_x = dst_y;
    src_x = src_y;
    ext_x = ext_y;
    int count = w;
    
    // Blend Pixels
    while (count > 0) {
      dst_xmm0 = _mm_load_si128((__m128i*) dst_x);
      dst_xmm2 = _mm_load_si128((__m128i*) dst_x + 1);
      ext_xmm0 = _mm_load_si128((__m128i*) ext_x);
      ext_xmm2 = _mm_load_si128((__m128i*) ext_x + 1);
      // Unpack Destination Color Pixels
      dst_xmm1 = _mm_unpacklo_epi16(dst_xmm0, zeros);
      dst_xmm0 = _mm_unpackhi_epi16(dst_xmm0, zeros);
      dst_xmm3 = _mm_unpacklo_epi16(dst_xmm2, zeros);
      dst_xmm2 = _mm_unpackhi_epi16(dst_xmm2, zeros);
      // Unpack Lower Scope Color Pixels
      ext_xmm1 = _mm_unpacklo_epi16(ext_xmm0, zeros);
      ext_xmm0 = _mm_unpackhi_epi16(ext_xmm0, zeros);
      ext_xmm3 = _mm_unpacklo_epi16(ext_xmm2, zeros);
      ext_xmm2 = _mm_unpackhi_epi16(ext_xmm2, zeros);

      // Apply Source Mask Pixel
      dst_xmm0 = _mm_mix_color(dst_xmm0, ext_xmm0, mask);
      dst_xmm1 = _mm_mix_color(dst_xmm1, ext_xmm1, mask);
      dst_xmm2 = _mm_mix_color(dst_xmm2, ext_xmm2, mask);
      dst_xmm3 = _mm_mix_color(dst_xmm3, ext_xmm3, mask);
      // Pack Destination Pixels to 8x16 bit channels
      dst_xmm0 = _mm_packus_epi32(dst_xmm1, dst_xmm0);
      dst_xmm2 = _mm_packus_epi32(dst_xmm3, dst_xmm2);

      // Store 4 Pixels
      if (__builtin_expect(count >= 4, 1)) {
        _mm_store_si128((__m128i*) dst_x, dst_xmm0);
        _mm_store_si128((__m128i*) dst_x + 1, dst_xmm2);

        // Next 4 Pixels
        dst_x += 32;
        ext_x += 32;
        src_x += 8;
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
    ext_y += s_ext;
  }
}
