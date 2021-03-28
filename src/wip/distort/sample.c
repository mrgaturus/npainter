#include <math.h>
#include "distort.h"

// ( x + ( (x + 32769) >> 15 ) ) >> 15
static inline __m128i _mm_div_32767(__m128i xmm0) {
  __m128i xmm1; // Auxiliar
  const __m128i mask_div = 
    _mm_set1_epi32(32769);

  xmm1 = _mm_add_epi32(xmm0, mask_div);
  xmm1 = _mm_srai_epi32(xmm1, 15);
  xmm1 = _mm_add_epi32(xmm1, xmm0);
  xmm1 = _mm_srai_epi32(xmm1, 15);
  return xmm1; // 32767 Div
}

// -------------------------
// FUNDAMENTAL PIXEL LOADING
// -------------------------

static __m128i sample_pixel(fragment_t* render, int x, int y) {
  int w, h;
  __m128i pixel;

  w = render->src_w; 
  h = render->src_h;
  // Repeat Positon
  x %= w; y %= h;
  // Ajust Negative
  if (x < 0) x += w;
  if (y < 0) y += h;

  // Load 16 bit Pixel and Unpack
  int stride = (y * w + x) << 2;
  pixel = _mm_loadl_epi64( // Load
    (__m128i*) (render->src + stride) );
  // Return Unpacked Pixel to 32bit
  pixel = _mm_cvtepi16_epi32(pixel);

  // Return Pixel
  return pixel;
}

// --------------------------
// PIXEL RESAMPLING FILTERING
// --------------------------

__m128i sample_nearest(fragment_t* render, float u, float v) {
  // Just flooring
  int ui = floor(u + 0.5); 
  int vi = floor(v + 0.5);
  // Return Sampled Pixel
  return sample_pixel(render, ui, vi);
}

__m128i sample_bilinear(fragment_t* render, float u, float v) {
  // Floor Coordinates
  float uu = floor(u);
  float vv = floor(v);
  // Calculate Interpolator
  int su = (u - uu) * 32767.0;
  int sv = (v - vv) * 32767.0;
  // Pixel Coordinates
  int x1 = uu;
  int y1 = vv;
  int x2 = x1 + 1;
  int y2 = y1 + 1;

  // Load Four Pixels
  __m128i m00 = sample_pixel(render, x1, y1);
  __m128i m10 = sample_pixel(render, x2, y1);
  __m128i m01 = sample_pixel(render, x1, y2);
  __m128i m11 = sample_pixel(render, x2, y2);
  // Swizzle Linear Interpolator
  __m128i mu = _mm_set1_epi32(su);
  __m128i mv = _mm_set1_epi32(sv);

  // Interpolate between four pixels
  __m128i xmm0, xmm1;
  xmm0 = _mm_sub_epi32(m10, m00);
  xmm0 = _mm_mullo_epi32(xmm0, mu);
  xmm0 = _mm_div_32767(xmm0);
  xmm0 = _mm_add_epi32(xmm0, m00);

  xmm1 = _mm_sub_epi32(m11, m01);
  xmm1 = _mm_mullo_epi32(xmm1, mu);
  xmm1 = _mm_div_32767(xmm1);
  xmm1 = _mm_add_epi32(xmm1, m01);

  xmm1 = _mm_sub_epi32(xmm1, xmm0);
  xmm1 = _mm_mullo_epi32(xmm1, mv);
  xmm1 = _mm_div_32767(xmm1);
  xmm1 = _mm_add_epi32(xmm0, xmm1);

  return xmm1;
}

// -- Bicubic Resampling
static __m128 bicubic_weight(float x) {
  float w;
  // Absolute Value
  if (x < 0.0)
    x = -x;

  // Calculate Bicubic Weight
  if (x < 1.0)
    w = 9.0 * x*x*x - 15.0 * x*x + 6.0;
  else if (x < 2.0)
    w = -3.0 * x*x*x + 15.0 * x*x - 24.0 * x + 12.0;
  w /= 6.0;

  // Swizzle Weight
  return _mm_set1_ps(w);
}

__m128i sample_bicubic(fragment_t* render, float u, float v) {
  __m128i pixel, clamp;
  // Convolution Auxiliars
  __m128 w, w_row, sum_w;
  __m128 w_pixel, sum_pixel;

  int u0, ui, v0, vj;
  // Initial Position
  u0 = floor(u);
  v0 = floor(v);

  sum_w = _mm_setzero_ps();
  sum_pixel = _mm_setzero_ps();
  for (int j = 0; j < 4; j++) {
    vj = v0 - 1 + j;
    // Calculate Y Weight
    w_row = bicubic_weight(v - vj);
    for (int i = 0; i < 4; i++) {
      ui = u0 - 1 + i;
      // Calculate Y * X Weight
      w = bicubic_weight(u - ui);
      w = _mm_mul_ps(w, w_row);
      // Lookup Pixel of Current Position
      pixel = sample_pixel(render, ui, vj);
      // Multiply Pixel By Weight
      w_pixel = _mm_cvtepi32_ps(pixel);
      w_pixel = _mm_mul_ps(w_pixel, w);
      // Sum Pixel and Weight
      sum_pixel = _mm_add_ps(
        sum_pixel, w_pixel);
      sum_w = _mm_add_ps(sum_w, w);
    }
  }

  // Divide by Weighted Sum
  w_pixel = _mm_div_ps(
    sum_pixel, sum_w);
  // Convert Pixel back to integer
  pixel = _mm_cvtps_epi32(w_pixel);
  // Clamp Pixel For Avoid Artifacts
  clamp = _mm_set1_epi32(32767);
  pixel = _mm_min_epi32(pixel, clamp);
  clamp = _mm_setzero_si128();
  pixel = _mm_max_epi32(pixel, clamp);

  // Return Pixel
  return pixel;
}

// ------------------------------
// One Pixel Basic Alpha Blending
// ------------------------------

void sample_blend_store(__m128i src, int16_t* dst) {
  __m128i alpha, xmm0;
  const __m128i mask_one = 
    _mm_set1_epi32(32767);
  // Load Destination Pixels
  xmm0 = _mm_loadl_epi64(
    (__m128i*) dst);
  xmm0 = _mm_cvtepi16_epi32(xmm0);
  // Swizzle Source Alpha - Sa Sa Sa Sa
  alpha = _mm_shuffle_epi32(src, 0xFF);
  alpha = _mm_sub_epi32(mask_one, alpha);
  // Perform Premultiplied Alpha Blending
  xmm0 = _mm_mullo_epi32(xmm0, alpha);
  xmm0 = _mm_div_32767(xmm0);
  xmm0 = _mm_add_epi32(src, xmm0);
  // Store and Pack Blended Pixel
  xmm0 = _mm_packs_epi32(xmm0, xmm0);
  _mm_storel_epi64( (__m128i*) dst, xmm0 );
}
