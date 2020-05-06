#include <smmintrin.h> // SSE4.1
// 8-Bit Blending Modes, (using 16-bit)
// SSE4.1 is used for fast unpacking

// Common Types
typedef unsigned int u32;
typedef short s16;

// Mask Constants
__m128i mask_257 = (__m128i) {
  0x0101010101010101, // Usable
  0x0000000000000000  // Unused
};

__m128i mask_255 = (__m128i) {
  0x00FF00FF00FF00FF, // Usable
  0x0000000000000000  // Unused
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

// --------------
// Blending Funcs
// --------------

u32 blend_normal(u32 dst, u32 src) {
  u32 alpha = // DA + SA
    (src >> 24) +
    (dst >> 24);
  if (alpha > 255)
    alpha = 255;
  alpha <<= 24;
  // Unpack Colors
  __m128i xmm1 = // SRC
    _mm_cvtepu8_epi16(
      _mm_cvtsi32_si128(src));
  __m128i xmm2 = // DST
    _mm_cvtepu8_epi16(
      _mm_cvtsi32_si128(dst));
  __m128i xmm3, xmm4;
  // Multiply src channels by src alpha
  xmm3 = _mm_shufflelo_epi16(xmm1, 0xFF);
  xmm4 = _mm_mullo_epi16(xmm1, xmm3);
  xmm4 = _mm_div_255(xmm4);
  // Multiply dst channels by 255-src alpha
  xmm3 = _mm_sub_epi16(mask_255, xmm3);
  xmm3 = _mm_mullo_epi16(xmm3, xmm2);
  xmm3 = _mm_div_255(xmm3);
  // Sum Both Multiplications
  xmm3 = _mm_add_epi16(xmm3, xmm4);
  // Return New Blended Color
  xmm3 = _mm_packus_epi16(xmm3, xmm3);
  return _mm_cvtsi128_si32(xmm3)
    & 0x00FFFFFF | alpha;
}
