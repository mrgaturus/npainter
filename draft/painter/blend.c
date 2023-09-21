#include <smmintrin.h> // SSE4.1
// 8-Bit Blending Modes, (using 16-bit)
// SSE4.1 is used for fast unpacking

// Common Types
typedef unsigned int u32;
typedef short s16;

// Mask Constants
const __m128i mask_257 = {
  0x0101010101010101,
  0x0101010101010101
};

const __m128i mask_255 = {
  0x00FF00FF00FF00FF,
  0x00FF00FF00FF00FF
};

// -----------------
// Fast 255 Division
// -----------------

// ( x + ( (x + 257) >> 8 ) ) >> 8
static inline __m128i _mm_div_255(__m128i xmm0) {
  __m128i xmm1; // Auxiliar XMM1
  xmm1 = _mm_adds_epu16(xmm0, mask_257);
  xmm1 = _mm_srli_epi16(xmm1, 8);
  xmm1 = _mm_adds_epu16(xmm1, xmm0);
  xmm1 = _mm_srli_epi16(xmm1, 8);
  return xmm1; // Return 255 Div
}

// --------------------------------
// Blending Modes, 4 pixels at once
// --------------------------------

__m128i blend_normal(__m128i dst, __m128i src) {
  __m128i src_lo, src_hi;
  __m128i dst_lo, dst_hi;
  __m128i xmm0, xmm1;
  // Reserve a zeros register
  xmm0 = _mm_setzero_si128();
  // Unpack Source Pixels
  src_lo = _mm_unpacklo_epi8(src, xmm0);
  src_hi = _mm_unpackhi_epi8(src, xmm0);
  // Unpack Destination Pixels
  dst_lo = _mm_unpacklo_epi8(dst, xmm0);
  dst_hi = _mm_unpackhi_epi8(dst, xmm0);
  // Shuffle Low Source Alphas: Sa, Sa, Sa, Sa
  xmm0 = _mm_shufflelo_epi16(src_lo, 0xFF);
  xmm0 = _mm_shufflehi_epi16(xmm0, 0xFF);
  // Shuffle High Source Alphas: Sa, Sa, Sa, Sa
  xmm1 = _mm_shufflelo_epi16(src_hi, 0xFF);
  xmm1 = _mm_shufflehi_epi16(xmm1, 0xFF);
  
  // Substract Alphas with 255
  xmm0 = _mm_sub_epi16(mask_255, xmm0);
  xmm1 = _mm_sub_epi16(mask_255, xmm1);
  // Multiply Destination by: 255 - Sa
  dst_lo = _mm_mullo_epi16(dst_lo, xmm0);
  dst_hi = _mm_mullo_epi16(dst_hi, xmm1);
  // Divide Destination by 255
  dst_lo = _mm_div_255(dst_lo);
  dst_hi = _mm_div_255(dst_hi);
  // Sum Destination with Source
  dst_lo = _mm_add_epi16(dst_lo, src_lo);
  dst_hi = _mm_add_epi16(dst_hi, src_hi);
  // Return Four Packed Pixels
  return _mm_packus_epi16(dst_lo, dst_hi);
}

// ---------------------
// Stride Color Blending
// ---------------------

void blend(u32* dst, u32* src, u32 n) {
  __m128i xmm0;
  while (n > 0) {
    // Four Pixels
    if (n >= 4) {
      // Blend SRC with DST
      xmm0 = blend_normal(
        _mm_loadu_si128(dst),
        _mm_loadu_si128(src));
      // Replace Blended Pixels
      _mm_storeu_si128(dst, xmm0);
      dst += 4; src += 4; n -= 4;
      // Next Pixels
      continue; 
    }

    // Two Pixels
    if (n >= 2) {
      // Blend SRC with DST
      xmm0 = blend_normal(
        _mm_loadl_epi64(dst),
        _mm_loadl_epi64(src));
      // Replace Blended Pixels
      _mm_storel_epi64(dst, xmm0);
      dst += 2; src += 2; n -= 2;
    }

    // One Pixel
    if (n >= 1) {
      // Blend SRC with DST
      xmm0 = blend_normal(
        _mm_cvtsi32_si128(*dst),
        _mm_cvtsi32_si128(*src));
      // Replace Blended Pixels
      *dst = _mm_cvtsi128_si32(xmm0);
    }
    
    // Blended
    break;
  }
}