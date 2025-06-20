// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Cristian Camilo Ruiz <mrgaturus>
#include "mask.h"

// --------------------------
// Polygon Combine Mask: Blit
// --------------------------

void polygon_mask_blit(mask_combine_t* co) {
  image_combine_t c = co->co;
  __m128i xmm0, xmm1, xmm2, xmm3;

  // Load Mask Opacity
  __m128i alpha = _mm_loadu_si32(&co->alpha);
  alpha = _mm_shuffle_epi32(alpha, 0);
  alpha = _mm_shufflelo_epi16(alpha, 0);
  alpha = _mm_shufflehi_epi16(alpha, 0);

  // Combine Mask: Blitting
  for (int y = 0; y < c.src.h; y++) {
    unsigned char* src = c.src.buffer;
    unsigned char* dst = c.dst.buffer;
    int count = c.src.w;

    while (count >= 32) {
      xmm0 = _mm_load_si128((__m128i*) src + 0);
      xmm2 = _mm_load_si128((__m128i*) src + 1);
      // Unpack Source Pixels to 16-Bit
      xmm3 = _mm_unpackhi_epi8(xmm2, xmm2);
      xmm2 = _mm_unpacklo_epi8(xmm2, xmm2);
      xmm1 = _mm_unpackhi_epi8(xmm0, xmm0);
      xmm0 = _mm_unpacklo_epi8(xmm0, xmm0);

      xmm0 = _mm_mul_fix16(xmm0, alpha);
      xmm1 = _mm_mul_fix16(xmm1, alpha);
      xmm2 = _mm_mul_fix16(xmm2, alpha);
      xmm3 = _mm_mul_fix16(xmm3, alpha);

      _mm_store_si128((__m128i*) dst + 0, xmm0);
      _mm_store_si128((__m128i*) dst + 1, xmm1);
      _mm_store_si128((__m128i*) dst + 2, xmm2);
      _mm_store_si128((__m128i*) dst + 3, xmm3);
      // Step 32 Pixels
      src += 32;
      dst += 64;
      count -= 32;
    }

    // Next Stride
    c.src.buffer += c.src.stride;
    c.dst.buffer += c.dst.stride;
  }
}

// --------------------------------
// Polygon Combine Mask: Operations
// --------------------------------

__attribute__((always_inline))
static inline void polygon_mask(mask_combine_t* co, const mask_mode_t mode) {
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
      src_xmm2 = _mm_load_si128((__m128i*) src + 1);
      // Load Destination Pixels
      dst_xmm0 = _mm_load_si128((__m128i*) dst + 0);
      dst_xmm1 = _mm_load_si128((__m128i*) dst + 1);
      dst_xmm2 = _mm_load_si128((__m128i*) dst + 2);
      dst_xmm3 = _mm_load_si128((__m128i*) dst + 3);

      // Unpack Source Pixels to 16-Bit
      src_xmm3 = _mm_unpackhi_epi8(src_xmm2, src_xmm2);
      src_xmm2 = _mm_unpacklo_epi8(src_xmm2, src_xmm2);
      src_xmm1 = _mm_unpackhi_epi8(src_xmm0, src_xmm0);
      src_xmm0 = _mm_unpacklo_epi8(src_xmm0, src_xmm0);

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
      src += 32; dst += 64;
      count -= 32;
    }

    // Next Stride
    c.src.buffer += c.src.stride;
    c.dst.buffer += c.dst.stride;
  }
}

void polygon_mask_union(mask_combine_t* co) {
  polygon_mask(co, maskUnion);
}

void polygon_mask_exclude(mask_combine_t* co) {
  polygon_mask(co, maskExclude);
}

void polygon_mask_intersect(mask_combine_t* co) {
  polygon_mask(co, maskIntersect);
}

// ---------------------------------
// Polygon Combine Color: Blit 16bit
// ---------------------------------

void polygon_color_blit16(mask_combine_t* co) {
  image_combine_t c = co->co;

  __m128i xmm0, xmm1, xmm2, xmm3;
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
      // Unpack Mask to 4x[AAAA, AAAA]
      xmm0 = _mm_loadl_epi64((__m128i*) src);
      xmm0 = _mm_unpacklo_epi8(xmm0, xmm0);
      xmm1 = _mm_unpackhi_epi16(xmm0, xmm0);
      xmm0 = _mm_unpacklo_epi16(xmm0, xmm0);
      xmm3 = _mm_unpackhi_epi32(xmm1, xmm1);
      xmm2 = _mm_unpacklo_epi32(xmm1, xmm1);
      xmm1 = _mm_unpackhi_epi32(xmm0, xmm0);
      xmm0 = _mm_unpacklo_epi32(xmm0, xmm0);

      xmm0 = _mm_mul_fix16(color, xmm0);
      xmm1 = _mm_mul_fix16(color, xmm1);
      xmm2 = _mm_mul_fix16(color, xmm2);
      xmm3 = _mm_mul_fix16(color, xmm3);

      // Store 8 RGBA 16-bit Pixels
      _mm_store_si128((__m128i*) dst + 0, xmm0);
      _mm_store_si128((__m128i*) dst + 1, xmm1);
      _mm_store_si128((__m128i*) dst + 2, xmm2);
      _mm_store_si128((__m128i*) dst + 3, xmm3);
      // Step 8 RGBA Pixels
      src += 8;
      dst += 64;
      count -= 8;
    }

    // Next Stride
    c.src.buffer += c.src.stride;
    c.dst.buffer += c.dst.stride;
  }
}

// --------------------------------
// Polygon Combine Color: Blit 8bit
// --------------------------------

void polygon_color_blit8(mask_combine_t* co) {
  image_combine_t c = co->co;

  __m128i xmm0, xmm1, xmm2, xmm3;
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
      // Unpack Mask to 4x[AAAA, AAAA]
      xmm0 = _mm_loadl_epi64((__m128i*) src);
      xmm0 = _mm_unpacklo_epi8(xmm0, xmm0);
      xmm1 = _mm_unpackhi_epi16(xmm0, xmm0);
      xmm0 = _mm_unpacklo_epi16(xmm0, xmm0);
      xmm3 = _mm_unpackhi_epi32(xmm1, xmm1);
      xmm2 = _mm_unpacklo_epi32(xmm1, xmm1);
      xmm1 = _mm_unpackhi_epi32(xmm0, xmm0);
      xmm0 = _mm_unpacklo_epi32(xmm0, xmm0);

      xmm0 = _mm_mul_fix16(color, xmm0);
      xmm1 = _mm_mul_fix16(color, xmm1);
      xmm2 = _mm_mul_fix16(color, xmm2);
      xmm3 = _mm_mul_fix16(color, xmm3);

      // Pack 16Bit RGBA to 8bit RGBA
      xmm0 = _mm_srli_epi16(xmm0, 8);
      xmm1 = _mm_srli_epi16(xmm1, 8);
      xmm2 = _mm_srli_epi16(xmm2, 8);
      xmm3 = _mm_srli_epi16(xmm3, 8);
      xmm0 = _mm_packus_epi16(xmm0, xmm1);
      xmm1 = _mm_packus_epi16(xmm2, xmm3);
      _mm_store_si128((__m128i*) dst + 0, xmm0);
      _mm_store_si128((__m128i*) dst + 1, xmm1);
      // Step 8 RGBA Pixels
      src += 8;
      dst += 32;
      count -= 8;
    }

    // Next Stride
    c.src.buffer += c.src.stride;
    c.dst.buffer += c.dst.stride;
  }
}

// -------------------------------------
// Polygon Combine Color: Blending 16bit
// -------------------------------------

__attribute__((always_inline))
static inline void polygon_color16(mask_combine_t* co, const int eraser) {
  image_combine_t c = co->co;

  __m128i color, ones;
  __m128i xmm0, xmm1, xmm2, xmm3;
  __m128i mask0, mask1, mask2, mask3;

  if (eraser == 0) {
    ones = _mm_setzero_si128();
    color = _mm_loadl_epi64((__m128i*) &co->color);
    color = _mm_unpacklo_epi64(color, color);
    // Load Alpha and Apply to Color
    xmm0 = _mm_loadu_si32(&co->alpha);
    xmm0 = _mm_unpacklo_epi16(xmm0, xmm0);
    xmm0 = _mm_shuffle_epi32(xmm0, 0);
    color = _mm_mul_fix16(color, xmm0);
  } else {
    ones = _mm_cmpeq_epi16(ones, ones);
    color = _mm_loadu_si32(&co->alpha);
    color = _mm_unpacklo_epi16(color, color);
    color = _mm_shuffle_epi32(color, 0);
  }

  // Combine Mask: Color Convert 16
  for (int y = 0; y < c.src.h; y++) {
    unsigned char* src = c.src.buffer;
    unsigned char* dst = c.dst.buffer;
    int count = c.src.w;

    while (count >= 8) {
      mask0 = _mm_loadl_epi64((__m128i*) src);
      mask0 = _mm_xor_si128(mask0, ones);

      // Load Destination 16 bit RGBA Pixels
      xmm0 = _mm_load_si128((__m128i*) dst + 0);
      xmm1 = _mm_load_si128((__m128i*) dst + 1);
      xmm2 = _mm_load_si128((__m128i*) dst + 2);
      xmm3 = _mm_load_si128((__m128i*) dst + 3);

      // Unpack Mask to 4x[AAAA, AAAA]
      mask0 = _mm_unpacklo_epi8(mask0, mask0);
      mask1 = _mm_unpackhi_epi16(mask0, mask0);
      mask0 = _mm_unpacklo_epi16(mask0, mask0);
      mask3 = _mm_unpackhi_epi32(mask1, mask1);
      mask2 = _mm_unpacklo_epi32(mask1, mask1);
      mask1 = _mm_unpackhi_epi32(mask0, mask0);
      mask0 = _mm_unpacklo_epi32(mask0, mask0);

      if (eraser == 0) {
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
      } else {
        // Apply Opacity to Mask
        mask0 = _mm_alpha_mask16(mask0, color);
        mask1 = _mm_alpha_mask16(mask1, color);
        mask2 = _mm_alpha_mask16(mask2, color);
        mask3 = _mm_alpha_mask16(mask3, color);
        // Apply Mask to Destination
        xmm0 = _mm_mul_fix16(xmm0, mask0);
        xmm1 = _mm_mul_fix16(xmm1, mask1);
        xmm2 = _mm_mul_fix16(xmm2, mask2);
        xmm3 = _mm_mul_fix16(xmm3, mask3);
      }

      // Store 8 RGBA 16-bit Pixels
      _mm_store_si128((__m128i*) dst + 0, xmm0);
      _mm_store_si128((__m128i*) dst + 1, xmm1);
      _mm_store_si128((__m128i*) dst + 2, xmm2);
      _mm_store_si128((__m128i*) dst + 3, xmm3);
      // Step 8 RGBA Pixels
      src += 8;
      dst += 64;
      count -= 8;
    }

    // Next Stride
    c.src.buffer += c.src.stride;
    c.dst.buffer += c.dst.stride;
  }
}

void polygon_color_blend16(mask_combine_t* co) {
  polygon_color16(co, 0);
}

void polygon_color_erase16(mask_combine_t* co) {
  polygon_color16(co, 1);
}

// ------------------------------------
// Polygon Combine Color: Blending 8bit
// ------------------------------------

__attribute__((always_inline))
static inline void polygon_color8(mask_combine_t* co, const int eraser) {
  image_combine_t c = co->co;

  __m128i color, ones;
  __m128i xmm0, xmm1, xmm2, xmm3;
  __m128i mask0, mask1, mask2, mask3;

  if (eraser == 0) {
    ones = _mm_setzero_si128();
    color = _mm_loadl_epi64((__m128i*) &co->color);
    color = _mm_unpacklo_epi64(color, color);
    // Load Alpha and Apply to Color
    xmm0 = _mm_loadu_si32(&co->alpha);
    xmm0 = _mm_unpacklo_epi16(xmm0, xmm0);
    xmm0 = _mm_shuffle_epi32(xmm0, 0);
    color = _mm_mul_fix16(color, xmm0);
  } else {
    ones = _mm_cmpeq_epi16(ones, ones);
    color = _mm_loadu_si32(&co->alpha);
    color = _mm_unpacklo_epi16(color, color);
    color = _mm_shuffle_epi32(color, 0);
  }

  // Combine Mask: Color Convert 16
  for (int y = 0; y < c.src.h; y++) {
    unsigned char* src = c.src.buffer;
    unsigned char* dst = c.dst.buffer;
    int count = c.src.w;

    while (count >= 8) {
      mask0 = _mm_loadl_epi64((__m128i*) src);
      mask0 = _mm_xor_si128(mask0, ones);

      // Unpack 8Bit RGBA to 16Bit RGBA
      xmm0 = _mm_load_si128((__m128i*) dst + 0);
      xmm2 = _mm_load_si128((__m128i*) dst + 1);
      xmm1 = _mm_unpackhi_epi8(xmm0, xmm0);
      xmm3 = _mm_unpackhi_epi8(xmm2, xmm2);
      xmm0 = _mm_unpacklo_epi8(xmm0, xmm0);
      xmm2 = _mm_unpacklo_epi8(xmm2, xmm2);

      // Unpack Mask to 4x[AAAA, AAAA]
      mask0 = _mm_unpacklo_epi8(mask0, mask0);
      mask1 = _mm_unpackhi_epi16(mask0, mask0);
      mask0 = _mm_unpacklo_epi16(mask0, mask0);
      mask3 = _mm_unpackhi_epi32(mask1, mask1);
      mask2 = _mm_unpacklo_epi32(mask1, mask1);
      mask1 = _mm_unpackhi_epi32(mask0, mask0);
      mask0 = _mm_unpacklo_epi32(mask0, mask0);

      if (eraser == 0) {
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
      } else {
        // Apply Opacity to Mask
        mask0 = _mm_alpha_mask16(mask0, color);
        mask1 = _mm_alpha_mask16(mask1, color);
        mask2 = _mm_alpha_mask16(mask2, color);
        mask3 = _mm_alpha_mask16(mask3, color);
        // Apply Mask to Destination
        xmm0 = _mm_mul_fix16(xmm0, mask0);
        xmm1 = _mm_mul_fix16(xmm1, mask1);
        xmm2 = _mm_mul_fix16(xmm2, mask2);
        xmm3 = _mm_mul_fix16(xmm3, mask3);
      }

      // Pack 16Bit RGBA to 8bit RGBA
      xmm0 = _mm_srli_epi16(xmm0, 8);
      xmm1 = _mm_srli_epi16(xmm1, 8);
      xmm2 = _mm_srli_epi16(xmm2, 8);
      xmm3 = _mm_srli_epi16(xmm3, 8);
      xmm0 = _mm_packus_epi16(xmm0, xmm1);
      xmm1 = _mm_packus_epi16(xmm2, xmm3);
      _mm_store_si128((__m128i*) dst + 0, xmm0);
      _mm_store_si128((__m128i*) dst + 1, xmm1);
      // Step 8 RGBA Pixels
      src += 8;
      dst += 32;
      count -= 8;
    }

    // Next Stride
    c.src.buffer += c.src.stride;
    c.dst.buffer += c.dst.stride;
  }
}

void polygon_color_blend8(mask_combine_t* co) {
  polygon_color8(co, 0);
}

void polygon_color_erase8(mask_combine_t* co) {
  polygon_color8(co, 1);
}
