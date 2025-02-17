// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Cristian Camilo Ruiz <mrgaturus>
#include "mask.h"

// ---------------------------------
// Combine Mask Operations: Blending
// ---------------------------------

__attribute__((always_inline))
static inline void combine_mask(mask_combine_t* co, const mask_mode_t mode) {
  image_combine_t c = co->co;

  // Load Mask Opacity
  __m128i alpha = _mm_loadu_si32(&co->alpha);
  alpha = _mm_shuffle_epi32(alpha, 0);
  alpha = _mm_shufflelo_epi16(alpha, 0);
  alpha = _mm_shufflehi_epi16(alpha, 0);
  __m128i src_xmm0, src_xmm1, src_xmm2, src_xmm3;
  __m128i dst_xmm0, dst_xmm1, dst_xmm2, dst_xmm3;

  // Combine Mask: Union
  for (int y = 0; y < c.src.h; y++) {
    unsigned char* src = c.src.buffer;
    unsigned char* dst = c.dst.buffer;
    int count = c.src.w;

    while (count >= 32) {
      // Load Source Pixels
      src_xmm0 = _mm_load_si128((__m128i*) src + 0);
      src_xmm1 = _mm_load_si128((__m128i*) src + 1);
      src_xmm2 = _mm_load_si128((__m128i*) src + 2);
      src_xmm3 = _mm_load_si128((__m128i*) src + 3);
      // Load Destination Pixels
      dst_xmm0 = _mm_load_si128((__m128i*) dst + 0);
      dst_xmm1 = _mm_load_si128((__m128i*) dst + 1);
      dst_xmm2 = _mm_load_si128((__m128i*) dst + 2);
      dst_xmm3 = _mm_load_si128((__m128i*) dst + 3);

      if (mode != maskIntersect) {
        src_xmm0 = _mm_mul_fix16(src_xmm0, alpha);
        src_xmm1 = _mm_mul_fix16(src_xmm1, alpha);
        src_xmm2 = _mm_mul_fix16(src_xmm2, alpha);
        src_xmm3 = _mm_mul_fix16(src_xmm3, alpha);
      } else {
        src_xmm0 = _mm_alpha_mask16(src_xmm0, alpha);
        src_xmm1 = _mm_alpha_mask16(src_xmm1, alpha);
        src_xmm2 = _mm_alpha_mask16(src_xmm2, alpha);
        src_xmm3 = _mm_alpha_mask16(src_xmm3, alpha);
      }

      switch (mode) {
        case maskUnion:
          dst_xmm0 = _mm_union_mask(src_xmm0, dst_xmm0);
          dst_xmm1 = _mm_union_mask(src_xmm1, dst_xmm1);
          dst_xmm2 = _mm_union_mask(src_xmm2, dst_xmm2);
          dst_xmm3 = _mm_union_mask(src_xmm3, dst_xmm3);
          break;
        case maskExclude:
          dst_xmm0 = _mm_exclude_mask(src_xmm0, dst_xmm0);
          dst_xmm1 = _mm_exclude_mask(src_xmm1, dst_xmm1);
          dst_xmm2 = _mm_exclude_mask(src_xmm2, dst_xmm2);
          dst_xmm3 = _mm_exclude_mask(src_xmm3, dst_xmm3);
          break;
        case maskIntersect:
          dst_xmm0 = _mm_mul_fix16(src_xmm0, dst_xmm0);
          dst_xmm1 = _mm_mul_fix16(src_xmm1, dst_xmm1);
          dst_xmm2 = _mm_mul_fix16(src_xmm2, dst_xmm2);
          dst_xmm3 = _mm_mul_fix16(src_xmm3, dst_xmm3);
          break;
      }

      _mm_store_si128((__m128i*) dst + 0, dst_xmm0);
      _mm_store_si128((__m128i*) dst + 1, dst_xmm1);
      _mm_store_si128((__m128i*) dst + 2, dst_xmm2);
      _mm_store_si128((__m128i*) dst + 3, dst_xmm3);
      // Step 32 Pixels
      src += 64; dst += 64;
      count -= 32;
    }

    // Next Stride
    c.src.buffer += c.src.stride;
    c.dst.buffer += c.dst.stride;
  }
}

void combine_mask_union(mask_combine_t* co) {
  combine_mask(co, maskUnion);
}

void combine_mask_exclude(mask_combine_t* co) {
  combine_mask(co, maskExclude);
}

void combine_mask_intersect(mask_combine_t* co) {
  combine_mask(co, maskIntersect);
}

// -------------------------------
// Combine Mask Operations: Invert
// -------------------------------

void combine_mask_invert(mask_combine_t* co) {
  image_combine_t c = co->co;
  __m128i xmm0, xmm1, xmm2, xmm3;
  const __m128i ones = _mm_cmpeq_epi16(xmm0, xmm0);

  // Combine Mask: Union
  for (int y = 0; y < c.src.h; y++) {
    unsigned char* src = c.src.buffer;
    unsigned char* dst = c.dst.buffer;
    int count = c.src.w;

    while (count >= 32) {
      // Load Source Pixels
      xmm0 = _mm_load_si128((__m128i*) src + 0);
      xmm1 = _mm_load_si128((__m128i*) src + 1);
      xmm2 = _mm_load_si128((__m128i*) src + 2);
      xmm3 = _mm_load_si128((__m128i*) src + 3);

      xmm0 = _mm_xor_si128(xmm0, ones);
      xmm1 = _mm_xor_si128(xmm1, ones);
      xmm2 = _mm_xor_si128(xmm2, ones);
      xmm3 = _mm_xor_si128(xmm3, ones);

      _mm_store_si128((__m128i*) dst + 0, xmm0);
      _mm_store_si128((__m128i*) dst + 1, xmm1);
      _mm_store_si128((__m128i*) dst + 2, xmm2);
      _mm_store_si128((__m128i*) dst + 3, xmm3);
      // Step 32 Pixels
      src += 64;
      dst += 64;
      count -= 32;
    }

    // Next Destination Stride
    c.src.buffer += c.src.stride;
    c.dst.buffer += c.dst.stride;
  }
}

// ----------------------------
// Combine Color to Mask: Color
// ----------------------------

__attribute__((always_inline))
static inline void convert_color_mask(mask_combine_t* co, const int rgba8) {
  image_combine_t c = co->co;

  __m128i lo0, lo1, hi0, hi1;
  __m128i xmm0, xmm1, xmm2, xmm3;
  // Combine Mask: Color Convert
  for (int y = 0; y < c.src.h; y++) {
    unsigned char* src = c.src.buffer;
    unsigned char* dst = c.dst.buffer;
    int count = c.src.w;

    while (count >= 8) {
      if (rgba8 == 0) { // Load RGBA 16 Bit
        xmm0 = _mm_load_si128((__m128i*) src + 0);
        xmm1 = _mm_load_si128((__m128i*) src + 1);
        xmm2 = _mm_load_si128((__m128i*) src + 2);
        xmm3 = _mm_load_si128((__m128i*) src + 3);
        src += 64;
      } else { // Unpack RGBA 8 Bit
        xmm0 = _mm_load_si128((__m128i*) src + 0);
        xmm2 = _mm_load_si128((__m128i*) src + 1);
        xmm1 = _mm_unpackhi_epi8(xmm0, xmm0);
        xmm3 = _mm_unpackhi_epi8(xmm2, xmm2);
        xmm0 = _mm_unpacklo_epi8(xmm0, xmm0);
        xmm2 = _mm_unpacklo_epi8(xmm2, xmm2);
        src += 32;
      }

      // Unpack 8xRGBA to 8xAlpha
      lo0 = _mm_unpacklo_epi16(xmm0, xmm1);
      lo1 = _mm_unpacklo_epi16(xmm2, xmm3);
      hi0 = _mm_unpackhi_epi16(xmm0, xmm1);
      hi1 = _mm_unpackhi_epi16(xmm2, xmm3);
      xmm0 = _mm_unpackhi_epi16(lo0, hi0);
      xmm1 = _mm_unpackhi_epi16(lo1, hi1);
      xmm0 = _mm_unpackhi_epi64(xmm0, xmm1);

      // Store 8xAlpha to Mask
      _mm_stream_si128((__m128i*) dst, xmm0);
      // Step 8 Mask Pixels
      dst += 16;
      count -= 8;
    }

    // Next Stride
    c.src.buffer += c.src.stride;
    c.dst.buffer += c.dst.stride;
  }
}

void convert_color16_mask(mask_combine_t* co) {
  convert_color_mask(co, 0);
}

void convert_color8_mask(mask_combine_t* co) {
  convert_color_mask(co, 1);
}

// --------------------------------
// Combine Color to Mask: Grayscale
// --------------------------------

__attribute__((always_inline))
static inline void convert_gray_mask(mask_combine_t* co, const int rgba8) {
  image_combine_t c = co->co;

  // Source Pixel Values
  __m128i xmm0, xmm1, xmm2, xmm3;
  __m128i xmm4, xmm5, xmm6, xmm7;
  const __m128i gray = _mm_set_epi32(0, 3736, 19234, 9798);
  const __m128i ones = _mm_cmpeq_epi32(gray, gray);
  const __m128i zeros = _mm_setzero_si128();

  // Combine Mask: Color Convert
  for (int y = 0; y < c.src.h; y++) {
    unsigned char* src = c.src.buffer;
    unsigned char* dst = c.dst.buffer;
    int count = c.src.w;

    while (count >= 8) {
      if (rgba8 == 0) { // Load RGBA 16 Bit
        xmm4 = _mm_load_si128((__m128i*) src + 0);
        xmm5 = _mm_load_si128((__m128i*) src + 1);
        xmm6 = _mm_load_si128((__m128i*) src + 2);
        xmm7 = _mm_load_si128((__m128i*) src + 3);
        src += 64;
      } else { // Unpack RGBA 8 Bit
        xmm4 = _mm_load_si128((__m128i*) src + 0);
        xmm6 = _mm_load_si128((__m128i*) src + 1);
        xmm5 = _mm_unpackhi_epi8(xmm4, xmm4);
        xmm7 = _mm_unpackhi_epi8(xmm6, xmm6);
        xmm4 = _mm_unpacklo_epi8(xmm4, xmm4);
        xmm6 = _mm_unpacklo_epi8(xmm6, xmm6);
        src += 32;
      }

      // Invert the Image Colors: Alphas
      xmm0 = _mm_shufflelo_epi16(xmm4, 0xFF);
      xmm1 = _mm_shufflelo_epi16(xmm5, 0xFF);
      xmm2 = _mm_shufflelo_epi16(xmm6, 0xFF);
      xmm3 = _mm_shufflelo_epi16(xmm7, 0xFF);
      xmm0 = _mm_shufflehi_epi16(xmm0, 0xFF);
      xmm1 = _mm_shufflehi_epi16(xmm1, 0xFF);
      xmm2 = _mm_shufflehi_epi16(xmm2, 0xFF);
      xmm3 = _mm_shufflehi_epi16(xmm3, 0xFF);
      // Invert the Image Colors: Color
      xmm4 = _mm_subs_epu16(xmm0, xmm4);
      xmm5 = _mm_subs_epu16(xmm1, xmm5);
      xmm6 = _mm_subs_epu16(xmm2, xmm6);
      xmm7 = _mm_subs_epu16(xmm3, xmm7);

      // Unpack 16-bit to 32-bit
      xmm0 = _mm_unpacklo_epi16(xmm4, zeros);
      xmm1 = _mm_unpackhi_epi16(xmm4, zeros);
      xmm2 = _mm_unpacklo_epi16(xmm5, zeros);
      xmm3 = _mm_unpackhi_epi16(xmm5, zeros);
      xmm4 = _mm_unpacklo_epi16(xmm6, zeros);
      xmm5 = _mm_unpackhi_epi16(xmm6, zeros);
      xmm6 = _mm_unpacklo_epi16(xmm7, zeros);
      xmm7 = _mm_unpackhi_epi16(xmm7, zeros);

      // Convert to Grayscale
      xmm0 = _mm_mullo_epi32(xmm0, gray);
      xmm1 = _mm_mullo_epi32(xmm1, gray);
      xmm2 = _mm_mullo_epi32(xmm2, gray);
      xmm3 = _mm_mullo_epi32(xmm3, gray);
      xmm4 = _mm_mullo_epi32(xmm4, gray);
      xmm5 = _mm_mullo_epi32(xmm5, gray);
      xmm6 = _mm_mullo_epi32(xmm6, gray);
      xmm7 = _mm_mullo_epi32(xmm7, gray);
      // Convert to Grayscale: Pack 1
      xmm0 = _mm_hadd_epi32(xmm0, xmm1);
      xmm1 = _mm_hadd_epi32(xmm2, xmm3);
      xmm2 = _mm_hadd_epi32(xmm4, xmm5);
      xmm3 = _mm_hadd_epi32(xmm6, xmm7);
      // Convert to Grayscale: Pack 2
      xmm0 = _mm_hadd_epi32(xmm0, xmm1);
      xmm1 = _mm_hadd_epi32(xmm2, xmm3);
      xmm0 = _mm_srli_epi32(xmm0, 15);
      xmm1 = _mm_srli_epi32(xmm1, 15);

      // Convert to Grayscale: Pack Store
      xmm0 = _mm_packus_epi32(xmm0, xmm1);
      _mm_stream_si128((__m128i*) dst, xmm0);
      // Step 8 Mask Pixels
      dst += 16;
      count -= 8;
    }

    // Next Stride
    c.src.buffer += c.src.stride;
    c.dst.buffer += c.dst.stride;
  }
}

void convert_gray16_mask(mask_combine_t* co) {
  convert_gray_mask(co, 0);
}

void convert_gray8_mask(mask_combine_t* co) {
  convert_gray_mask(co, 1);
}

// ---------------------------
// Combine Mask to Color: Blit
// ---------------------------

__attribute__((always_inline))
static inline void convert_mask_color(mask_combine_t* co, const int rgba8) {
  image_combine_t c = co->co;

  // Load Color and Initialize Zeros
  __m128i mask0, mask1, mask2, mask3;
  __m128i color = _mm_loadl_epi64((__m128i*) &co->color);
  color = _mm_unpacklo_epi64(color, color);
  // Load Alpha and Apply to Color
  mask0 = _mm_loadu_si32(&co->alpha);
  mask0 = _mm_unpacklo_epi16(mask0, mask0);
  mask0 = _mm_shuffle_epi32(mask0, 0);
  color = _mm_mul_fix16(color, mask0);

  // Combine Mask: Color Convert 16
  for (int y = 0; y < c.src.h; y++) {
    unsigned char* src = c.src.buffer;
    unsigned char* dst = c.dst.buffer;
    int count = c.src.w;

    while (count >= 8) {
      mask0 = _mm_load_si128((__m128i*) src);

      // Unpack Mask to 4x[AAAA, AAAA]
      mask1 = _mm_unpackhi_epi16(mask0, mask0);
      mask0 = _mm_unpacklo_epi16(mask0, mask0);
      mask3 = _mm_unpackhi_epi32(mask1, mask1);
      mask2 = _mm_unpacklo_epi32(mask1, mask1);
      mask1 = _mm_unpackhi_epi32(mask0, mask0);
      mask0 = _mm_unpacklo_epi32(mask0, mask0);

      // Apply Mask to Source Color
      mask0 = _mm_mul_fix16(color, mask0);
      mask1 = _mm_mul_fix16(color, mask1);
      mask2 = _mm_mul_fix16(color, mask2);
      mask3 = _mm_mul_fix16(color, mask3);

      if (rgba8 == 0) {
        _mm_store_si128((__m128i*) dst + 0, mask0);
        _mm_store_si128((__m128i*) dst + 1, mask1);
        _mm_store_si128((__m128i*) dst + 2, mask2);
        _mm_store_si128((__m128i*) dst + 3, mask3);
        dst += 64;
      } else {
        mask0 = _mm_srli_epi16(mask0, 8);
        mask1 = _mm_srli_epi16(mask1, 8);
        mask2 = _mm_srli_epi16(mask2, 8);
        mask3 = _mm_srli_epi16(mask3, 8);
        mask0 = _mm_packus_epi16(mask0, mask1);
        mask1 = _mm_packus_epi16(mask2, mask3);
        _mm_store_si128((__m128i*) dst + 0, mask0);
        _mm_store_si128((__m128i*) dst + 1, mask1);
        dst += 32;
      }

      // Step 8 RGBA Pixels
      src += 16;
      count -= 8;
    }

    // Next Stride
    c.src.buffer += c.src.stride;
    c.dst.buffer += c.dst.stride;
  }
}

void convert_mask_color16(mask_combine_t* co) {
  convert_mask_color(co, 0);
}

void convert_mask_color8(mask_combine_t* co) {
  convert_mask_color(co, 1);
}

// -------------------------------
// Combine Mask to Color: Blending
// -------------------------------

__attribute__((always_inline))
static inline void convert_mask_blend(mask_combine_t* co, const int rgba8) {
  image_combine_t c = co->co;

  __m128i xmm0, xmm1, xmm2, xmm3;
  __m128i mask0, mask1, mask2, mask3;
  // Load Color and Initialize Zeros
  __m128i color = _mm_loadl_epi64((__m128i*) &co->color);
  color = _mm_unpacklo_epi64(color, color);
  // Load Alpha and Apply to Color
  xmm0 = _mm_loadu_si32(&co->alpha);
  xmm0 = _mm_unpacklo_epi16(xmm0, xmm0);
  xmm0 = _mm_shuffle_epi32(xmm0, 0);
  color = _mm_mul_fix16(color, xmm0);

  // Combine Mask: Color Convert 16
  for (int y = 0; y < c.src.h; y++) {
    unsigned char* src = c.src.buffer;
    unsigned char* dst = c.dst.buffer;
    int count = c.src.w;

    while (count >= 8) {
      mask0 = _mm_load_si128((__m128i*) src);

      if (rgba8 == 0) {
        xmm0 = _mm_load_si128((__m128i*) dst + 0);
        xmm1 = _mm_load_si128((__m128i*) dst + 1);
        xmm2 = _mm_load_si128((__m128i*) dst + 2);
        xmm3 = _mm_load_si128((__m128i*) dst + 3);
      } else {
        xmm0 = _mm_load_si128((__m128i*) dst + 0);
        xmm2 = _mm_load_si128((__m128i*) dst + 1);
        xmm1 = _mm_unpackhi_epi8(xmm0, xmm0);
        xmm3 = _mm_unpackhi_epi8(xmm2, xmm2);
        xmm0 = _mm_unpacklo_epi8(xmm0, xmm0);
        xmm2 = _mm_unpacklo_epi8(xmm2, xmm2);
      }

      // Unpack Mask to 4x[AAAA, AAAA]
      mask1 = _mm_unpackhi_epi16(mask0, mask0);
      mask0 = _mm_unpacklo_epi16(mask0, mask0);
      mask3 = _mm_unpackhi_epi32(mask1, mask1);
      mask2 = _mm_unpacklo_epi32(mask1, mask1);
      mask1 = _mm_unpackhi_epi32(mask0, mask0);
      mask0 = _mm_unpacklo_epi32(mask0, mask0);

      // Apply Mask to Source Color
      mask0 = _mm_mul_fix16(color, mask0);
      mask1 = _mm_mul_fix16(color, mask1);
      mask2 = _mm_mul_fix16(color, mask2);
      mask3 = _mm_mul_fix16(color, mask3);
      // Blend Mask Color to Destination
      xmm0 = _mm_color_mask(mask0, xmm0);
      xmm1 = _mm_color_mask(mask1, xmm1);
      xmm2 = _mm_color_mask(mask2, xmm2);
      xmm3 = _mm_color_mask(mask3, xmm3);

      if (rgba8 == 0) {
        _mm_store_si128((__m128i*) dst + 0, xmm0);
        _mm_store_si128((__m128i*) dst + 1, xmm1);
        _mm_store_si128((__m128i*) dst + 2, xmm2);
        _mm_store_si128((__m128i*) dst + 3, xmm3);
        dst += 64;
      } else {
        xmm0 = _mm_srli_epi16(xmm0, 8);
        xmm1 = _mm_srli_epi16(xmm1, 8);
        xmm2 = _mm_srli_epi16(xmm2, 8);
        xmm3 = _mm_srli_epi16(xmm3, 8);
        xmm0 = _mm_packus_epi16(xmm0, xmm1);
        xmm1 = _mm_packus_epi16(xmm2, xmm3);
        _mm_store_si128((__m128i*) dst + 0, xmm0);
        _mm_store_si128((__m128i*) dst + 1, xmm1);
        dst += 32;
      }

      // Step 8 RGBA Pixels
      src += 16;
      count -= 8;
    }

    // Next Stride
    c.src.buffer += c.src.stride;
    c.dst.buffer += c.dst.stride;
  }
}

void convert_mask_blend16(mask_combine_t* co) {
  convert_mask_blend(co, 0);
}

void convert_mask_blend8(mask_combine_t* co) {
  convert_mask_blend(co, 1);
}

// -----------------------------
// Combine Mask to Color: Eraser
// -----------------------------

__attribute__((always_inline))
static inline void convert_mask_erase(mask_combine_t* co,
const int clip, const int rgba8) {
  image_combine_t c = co->co;

  __m128i xmm0, xmm1, xmm2, xmm3;
  __m128i mask0, mask1, mask2, mask3;
  // Load Alpha and Apply to Color
  __m128i alpha = _mm_loadu_si32(&co->alpha);
  alpha = _mm_unpacklo_epi16(alpha, alpha);
  alpha = _mm_shuffle_epi32(alpha, 0);

  // Combine Mask: Color Convert 16
  for (int y = 0; y < c.src.h; y++) {
    unsigned char* src = c.src.buffer;
    unsigned char* dst = c.dst.buffer;
    int count = c.src.w;

    while (count >= 8) {
      mask0 = _mm_load_si128((__m128i*) src);

      if (clip == 0) {
        mask1 = _mm_cmpeq_epi16(mask0, mask0);
        mask0 = _mm_xor_si128(mask0, mask1);
        mask0 = _mm_alpha_mask16(mask0, alpha);
      } else { mask0 = _mm_mul_fix16(mask0, alpha); }

      if (rgba8 == 0) {
        xmm0 = _mm_load_si128((__m128i*) dst + 0);
        xmm1 = _mm_load_si128((__m128i*) dst + 1);
        xmm2 = _mm_load_si128((__m128i*) dst + 2);
        xmm3 = _mm_load_si128((__m128i*) dst + 3);
      } else {
        xmm0 = _mm_load_si128((__m128i*) dst + 0);
        xmm2 = _mm_load_si128((__m128i*) dst + 1);
        xmm1 = _mm_unpackhi_epi8(xmm0, xmm0);
        xmm3 = _mm_unpackhi_epi8(xmm2, xmm2);
        xmm0 = _mm_unpacklo_epi8(xmm0, xmm0);
        xmm2 = _mm_unpacklo_epi8(xmm2, xmm2);
      }

      // Unpack Mask to 4x[AAAA, AAAA]
      mask1 = _mm_unpackhi_epi16(mask0, mask0);
      mask0 = _mm_unpacklo_epi16(mask0, mask0);
      mask3 = _mm_unpackhi_epi32(mask1, mask1);
      mask2 = _mm_unpacklo_epi32(mask1, mask1);
      mask1 = _mm_unpackhi_epi32(mask0, mask0);
      mask0 = _mm_unpacklo_epi32(mask0, mask0);

      // Apply Mask to Destination
      xmm0 = _mm_mul_fix16(xmm0, mask0);
      xmm1 = _mm_mul_fix16(xmm1, mask1);
      xmm2 = _mm_mul_fix16(xmm2, mask2);
      xmm3 = _mm_mul_fix16(xmm3, mask3);

      if (rgba8 == 0) {
        _mm_store_si128((__m128i*) dst + 0, xmm0);
        _mm_store_si128((__m128i*) dst + 1, xmm1);
        _mm_store_si128((__m128i*) dst + 2, xmm2);
        _mm_store_si128((__m128i*) dst + 3, xmm3);
        dst += 64;
      } else {
        xmm0 = _mm_srli_epi16(xmm0, 8);
        xmm1 = _mm_srli_epi16(xmm1, 8);
        xmm2 = _mm_srli_epi16(xmm2, 8);
        xmm3 = _mm_srli_epi16(xmm3, 8);
        xmm0 = _mm_packus_epi16(xmm0, xmm1);
        xmm1 = _mm_packus_epi16(xmm2, xmm3);
        _mm_store_si128((__m128i*) dst + 0, xmm0);
        _mm_store_si128((__m128i*) dst + 1, xmm1);
        dst += 32;
      }

      // Step 8 RGBA Pixels
      src += 16;
      count -= 8;
    }

    // Next Stride
    c.src.buffer += c.src.stride;
    c.dst.buffer += c.dst.stride;
  }
}

void convert_mask_erase16(mask_combine_t* co) {
  convert_mask_erase(co, 0, 0);
}

void convert_mask_erase8(mask_combine_t* co) {
  convert_mask_erase(co, 0, 1);
}

void convert_mask_clip16(mask_combine_t* co) {
  convert_mask_erase(co, 1, 0);
}

void convert_mask_clip8(mask_combine_t* co) {
  convert_mask_erase(co, 1, 1);
}
