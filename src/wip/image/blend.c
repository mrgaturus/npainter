// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
#include "image.h"

__m128i blend_normal(__m128i src, __m128i dst) {
  dst = _mm_shuffle_epi32(dst, 0xFF);
  src = _mm_multiply_color(src, dst);

  return src;
}

// -------------------------
// Darker Blending Functions
// -------------------------

__m128i blend_multiply(__m128i src, __m128i dst) {
  return _mm_multiply_color(src, dst);
}

__m128i blend_darken(__m128i src, __m128i dst) {
  __m128i xmm0, xmm1;
  xmm0 = _mm_shuffle_epi32(src, 0xFF);
  xmm1 = _mm_shuffle_epi32(dst, 0xFF);
  // min(src, dst) * sa * da
  src = _mm_multiply_color(src, xmm1);
  dst = _mm_multiply_color(dst, xmm0); 
  xmm0 = _mm_min_epi32(src, dst);

  return xmm0;
}

__m128i blend_colorburn(__m128i src, __m128i dst) {
  const __m128 zeros = _mm_setzero_ps();
  const __m128 ones = _mm_set1_ps(1.0);
  const __m128 xmm65535 = _mm_set1_ps(65535.0);
  const __m128 rcp65535 = _mm_rcp_ps(xmm65535);

  __m128 xmm0, xmm1;
  // Convert to Float and Normalize
  __m128 src0 = _mm_cvtepi32_ps(src);
  __m128 dst0 = _mm_cvtepi32_ps(dst);
  src0 = _mm_mul_ps(src0, rcp65535);
  dst0 = _mm_mul_ps(dst0, rcp65535);
  // Convert to Straight Alpha
  __m128 sa = _mm_shuffle_ps(src0, src0, 0xFF);
  __m128 da = _mm_shuffle_ps(dst0, dst0, 0xFF);
  src0 = _mm_div_ps(src0, sa);
  dst0 = _mm_div_ps(dst0, da);
  // Calculate Clamping
  xmm0 = _mm_cmpeq_ps(src0, zeros);
  xmm1 = _mm_cmpeq_ps(dst0, ones);
  // 1.0 - (1.0 - d) / s
  src0 = _mm_rcp_ps(src0);
  dst0 = _mm_sub_ps(ones, dst0);
  src0 = _mm_mul_ps(dst0, src0);
  src0 = _mm_sub_ps(ones, src0);
  // Apply Clamping
  src0 = _mm_max_ps(src0, zeros);
  src0 = _mm_blendv_ps(src0, zeros, xmm0);
  src0 = _mm_blendv_ps(src0, ones, xmm1);

  // Convert to Premultiply
  xmm0 = _mm_mul_ps(sa, da);
  src0 = _mm_mul_ps(src0, xmm0);
  // Convert Back to Integer
  src0 = _mm_mul_ps(src0, xmm65535);
  return _mm_cvtps_epi32(src0);
}

__m128i blend_linearburn(__m128i src, __m128i dst) {
  __m128i xmm0, xmm1, xmm2;
  xmm0 = _mm_shuffle_epi32(src, 0xFF);
  xmm1 = _mm_shuffle_epi32(dst, 0xFF);
  // Apply Premultipled Complement
  xmm2 = _mm_multiply_color(xmm0, xmm1);
  src = _mm_multiply_color(src, xmm1);
  dst = _mm_multiply_color(dst, xmm0);
  // s + d - 1.0
  xmm0 = _mm_add_epi32(src, dst);
  xmm0 = _mm_sub_epi32(xmm0, xmm2);
  
  return xmm0;
}

__m128i blend_darkercolor(__m128i src, __m128i dst) {
  const __m128i gray = _mm_set_epi32(0, 3736, 19234, 9798);
  __m128i xmm0, xmm1;
  
  xmm0 = _mm_shuffle_epi32(src, 0xFF);
  xmm1 = _mm_shuffle_epi32(dst, 0xFF);
  // Apply Premultipled Complement
  src = _mm_multiply_color(src, xmm1);
  dst = _mm_multiply_color(dst, xmm0);
  // Convert to Gray Scale
  xmm0 = _mm_mullo_epi32(src, gray);
  xmm1 = _mm_mullo_epi32(dst, gray);

  // Calculate Darker Color
  xmm0 = _mm_hadd_epi32(xmm0, xmm1);
  xmm0 = _mm_hadd_epi32(xmm0, xmm0);
  xmm0 = _mm_srli_epi32(xmm0, 15);
  xmm1 = _mm_shuffle_epi32(xmm0, 0xFF);
  xmm0 = _mm_shuffle_epi32(xmm0, 0);
  // Decide Which is Darker
  xmm0 = _mm_cmplt_epi32(xmm0, xmm1);
  xmm0 = _mm_blendv_epi8(dst, src, xmm0);

  return xmm0;
}

// -------------------------
// Light Blendings Functions
// -------------------------

__m128i blend_screen(__m128i src, __m128i dst) {
  __m128i xmm0, xmm1, xmm2;
  
  xmm0 = _mm_shuffle_epi32(src, 0xFF);
  xmm1 = _mm_shuffle_epi32(dst, 0xFF);
  // Apply Premultipled Complement
  xmm2 = _mm_multiply_color(src, dst);
  src = _mm_multiply_color(src, xmm1);
  dst = _mm_multiply_color(dst, xmm0);
  // s + d - s * d
  xmm0 = _mm_add_epi32(src, dst);
  xmm0 = _mm_sub_epi32(xmm0, xmm2);

  return xmm0;
}

__m128i blend_lighten(__m128i src, __m128i dst) {
  __m128i xmm0, xmm1;
  xmm0 = _mm_shuffle_epi32(src, 0xFF);
  xmm1 = _mm_shuffle_epi32(dst, 0xFF);
  // max(src, dst) * sa * da
  src = _mm_multiply_color(src, xmm1);
  dst = _mm_multiply_color(dst, xmm0); 
  xmm0 = _mm_max_epi32(src, dst);

  return xmm0;
}

__m128i blend_colordodge(__m128i src, __m128i dst) {
  const __m128 zeros = _mm_setzero_ps();
  const __m128 ones = _mm_set1_ps(1.0);
  const __m128 xmm65535 = _mm_set1_ps(65535.0);
  const __m128 rcp65535 = _mm_rcp_ps(xmm65535);

  __m128 xmm0, xmm1;
  // Convert to Float and Normalize
  __m128 src0 = _mm_cvtepi32_ps(src);
  __m128 dst0 = _mm_cvtepi32_ps(dst);
  src0 = _mm_mul_ps(src0, rcp65535);
  dst0 = _mm_mul_ps(dst0, rcp65535);
  // Convert to Straight Alpha
  __m128 sa = _mm_shuffle_ps(src0, src0, 0xFF);
  __m128 da = _mm_shuffle_ps(dst0, dst0, 0xFF);
  src0 = _mm_div_ps(src0, sa);
  dst0 = _mm_div_ps(dst0, da);
  // Calculate Clamping
  xmm0 = _mm_cmpeq_ps(src0, ones);
  xmm1 = _mm_cmpeq_ps(dst0, zeros);
  // d / (1 - s)
  src0 = _mm_sub_ps(ones, src0);
  src0 = _mm_div_ps(dst0, src0);
  // Apply Clamping
  src0 = _mm_min_ps(src0, ones);
  src0 = _mm_blendv_ps(src0, ones, xmm0);
  src0 = _mm_blendv_ps(src0, zeros, xmm1);

  // Convert to Premultiply
  xmm0 = _mm_mul_ps(sa, da);
  src0 = _mm_mul_ps(src0, xmm0);
  // Convert Back to Integer
  src0 = _mm_mul_ps(src0, xmm65535);
  return _mm_cvtps_epi32(src0);
}

__m128i blend_lineardodge(__m128i src, __m128i dst) {
  __m128i xmm0, xmm1, alpha;
  xmm0 = _mm_shuffle_epi32(src, 0xFF);
  xmm1 = _mm_shuffle_epi32(dst, 0xFF);
  alpha = _mm_multiply_color(xmm0, xmm1);

  // s + d
  src = _mm_multiply_color(src, xmm1);
  dst = _mm_multiply_color(dst, xmm0);
  xmm0 = _mm_add_epi32(src, dst);
  xmm0 = _mm_min_epi32(xmm0, alpha);

  return xmm0;
}

__m128i blend_lightercolor(__m128i src, __m128i dst) {
  const __m128i gray = _mm_set_epi32(0, 3736, 19234, 9798);
  __m128i xmm0, xmm1;
  
  xmm0 = _mm_shuffle_epi32(src, 0xFF);
  xmm1 = _mm_shuffle_epi32(dst, 0xFF);
  // Apply Premultipled Complement
  src = _mm_multiply_color(src, xmm1);
  dst = _mm_multiply_color(dst, xmm0);
  // Convert to Gray Scale
  xmm0 = _mm_mullo_epi32(src, gray);
  xmm1 = _mm_mullo_epi32(dst, gray);

  // Calculate Darker Color
  xmm0 = _mm_hadd_epi32(xmm0, xmm1);
  xmm0 = _mm_hadd_epi32(xmm0, xmm0);
  xmm0 = _mm_srli_epi32(xmm0, 15);
  xmm1 = _mm_shuffle_epi32(xmm0, 0xFF);
  xmm0 = _mm_shuffle_epi32(xmm0, 0);
  // Decide Which is Darker
  xmm0 = _mm_cmpgt_epi32(xmm0, xmm1);
  xmm0 = _mm_blendv_epi8(dst, src, xmm0);

  return xmm0;
}

// ---------------------------
// Contrast Blending Functions
// ---------------------------

__m128i blend_overlay(__m128i src, __m128i dst) {
  __m128i xmm0, xmm1, alpha, mullo;
  xmm0 = _mm_shuffle_epi32(src, 0xFF);
  xmm1 = _mm_shuffle_epi32(dst, 0xFF);
  // Apply Premultipled Complement
  alpha = _mm_multiply_color(xmm0, xmm1);
  mullo = _mm_multiply_color(src, dst);
  src = _mm_multiply_color(src, xmm1);
  dst = _mm_multiply_color(dst, xmm0);

  xmm0 = _mm_add_epi32(src, dst);
  xmm1 = _mm_add_epi32(alpha, mullo);
  xmm0 = _mm_sub_epi32(xmm1, xmm0);
  // if d < 0.5: 2 * s + d
  // else: 1 - 2 * (1 - d) * (1 - s)
  xmm0 = _mm_add_epi32(xmm0, xmm0);
  xmm1 = _mm_add_epi32(mullo, mullo);
  xmm0 = _mm_sub_epi32(alpha, xmm0);

  // Decide Overlay Half
  alpha = _mm_srli_epi32(alpha, 1);
  alpha = _mm_cmplt_epi32(dst, alpha);
  src = _mm_blendv_epi8(xmm0, xmm1, alpha);

  return src;
}

__m128i blend_softlight(__m128i src, __m128i dst) {
  const __m128 zeros = _mm_setzero_ps();
  const __m128 ones = _mm_set1_ps(1.0);
  // Checking Constants
  const __m128 half = _mm_set1_ps(0.5);
  const __m128 quad = _mm_set1_ps(0.25);
  // Converting Constants
  const __m128 xmm65535 = _mm_set1_ps(65535.0);
  const __m128 rcp65535 = _mm_rcp_ps(xmm65535);

  __m128 xmm0, xmm1, xmm2, xmm3;
  // Convert to Float and Normalize
  __m128 src0 = _mm_cvtepi32_ps(src);
  __m128 dst0 = _mm_cvtepi32_ps(dst);
  src0 = _mm_mul_ps(src0, rcp65535);
  dst0 = _mm_mul_ps(dst0, rcp65535);
  // Convert to Straight Alpha
  __m128 sa = _mm_shuffle_ps(src0, src0, 0xFF);
  __m128 da = _mm_shuffle_ps(dst0, dst0, 0xFF);
  src0 = _mm_div_ps(src0, sa);
  dst0 = _mm_div_ps(dst0, da);

  // d0 = 4 * d
  // d1 = 3 * d
  // d2 = 4 * d * d
  xmm0 = _mm_add_ps(dst0, dst0);
  xmm1 = _mm_add_ps(xmm0, dst0);
  xmm0 = _mm_add_ps(xmm0, xmm0);
  xmm2 = _mm_mul_ps(xmm0, dst0);
  // d3 = sqrt(d)
  // d2 = d0 * (d2 - d1 + 1)
  xmm3 = _mm_sqrt_ps(dst0);
  xmm2 = _mm_sub_ps(xmm2, xmm1);
  xmm2 = _mm_add_ps(xmm2, ones);
  xmm2 = _mm_mul_ps(xmm0, xmm2);
  // d2 = (d < 0.25) ? d2 : d3
  xmm0 = _mm_cmplt_ps(dst0, quad);
  xmm2 = _mm_blendv_ps(xmm3, xmm2, xmm0);

  // s0 = (2 * s - 1)
  // s1 = d * (1 - d)
  // s2 = d2 - d
  xmm0 = _mm_add_ps(src0, src0);
  xmm0 = _mm_sub_ps(xmm0, ones);
  xmm1 = _mm_mul_ps(dst0, dst0);
  xmm1 = _mm_sub_ps(dst0, xmm1);
  xmm2 = _mm_sub_ps(xmm2, dst0);
  // s3 = (s < 0.5) ? s1 : s2
  xmm3 = _mm_cmpgt_ps(src0, half);
  xmm3 = _mm_blendv_ps(xmm1, xmm2, xmm3);
  // s0 = d + s0 * s3
  xmm0 = _mm_mul_ps(xmm3, xmm0);
  xmm0 = _mm_add_ps(dst0, xmm0);

  // Convert to Premultiply
  xmm1 = _mm_mul_ps(sa, da);
  src0 = _mm_mul_ps(xmm0, xmm1);
  xmm2 = _mm_cmpgt_ps(xmm1, zeros);
  src0 = _mm_and_ps(src0, xmm2);
  // Convert Back to Integer
  src0 = _mm_mul_ps(src0, xmm65535);
  return _mm_cvtps_epi32(src0);
}

__m128i blend_hardlight(__m128i src, __m128i dst) {
  return blend_overlay(dst, src);
}

__m128i blend_vividlight(__m128i src, __m128i dst) {
  const __m128 zeros = _mm_setzero_ps();
  const __m128 ones = _mm_set1_ps(1.0);
  const __m128 xmm65535 = _mm_set1_ps(65535.0);
  const __m128 rcp65535 = _mm_rcp_ps(xmm65535);

  __m128 xmm0, xmm1, xmm2, xmm3;
  // Convert to Float and Normalize
  __m128 src0 = _mm_cvtepi32_ps(src);
  __m128 dst0 = _mm_cvtepi32_ps(dst);
  src0 = _mm_mul_ps(src0, rcp65535);
  dst0 = _mm_mul_ps(dst0, rcp65535);
  // Convert to Straight Alpha
  __m128 sa = _mm_shuffle_ps(src0, src0, 0xFF);
  __m128 da = _mm_shuffle_ps(dst0, dst0, 0xFF);
  src0 = _mm_div_ps(src0, sa);
  dst0 = _mm_div_ps(dst0, da);

  // s1 = (d + 2 * s - 1) / 2 * s
  xmm0 = _mm_add_ps(src0, src0);
  xmm1 = _mm_sub_ps(dst0, ones);
  xmm1 = _mm_add_ps(xmm1, xmm0);
  xmm1 = _mm_div_ps(xmm1, xmm0);

  // s2 = d / (2 - 2 * s)
  xmm3 = _mm_add_ps(ones, ones);
  xmm2 = _mm_sub_ps(xmm3, xmm0);
  xmm2 = _mm_div_ps(dst0, xmm2);
  // Decide Formula
  xmm0 = _mm_rcp_ps(xmm3);
  xmm0 = _mm_cmpgt_ps(src0, xmm0);
  xmm0 = _mm_blendv_ps(xmm1, xmm2, xmm0);
  // Clamp Formulas
  xmm1 = _mm_cmpgt_ps(src0, zeros);
  xmm0 = _mm_min_ps(xmm0, ones);
  xmm0 = _mm_max_ps(xmm0, zeros);
  xmm0 = _mm_and_ps(xmm0, xmm1);

  // Convert to Premultiply
  xmm1 = _mm_mul_ps(sa, da);
  src0 = _mm_mul_ps(xmm0, xmm1);
  src0 = _mm_mul_ps(src0, xmm65535);
  return _mm_cvtps_epi32(src0);
}

__m128i blend_linearlight(__m128i src, __m128i dst) {
  __m128i xmm0, xmm1, alpha;
  xmm0 = _mm_shuffle_epi32(src, 0xFF);
  xmm1 = _mm_shuffle_epi32(dst, 0xFF);
  // Apply Premultipled Complement
  alpha = _mm_multiply_color(xmm0, xmm1);
  src = _mm_multiply_color(src, xmm1);
  dst = _mm_multiply_color(dst, xmm0);
  
  // 2 * s + d - 1
  src = _mm_add_epi32(src, src);
  dst = _mm_sub_epi32(dst, alpha);
  src = _mm_add_epi32(src, dst);
  src = _mm_min_epi32(src, alpha);

  return src;
}

__m128i blend_pinlight(__m128i src, __m128i dst) {
  __m128i xmm0, xmm1, xmm2;
  xmm0 = _mm_shuffle_epi32(src, 0xFF);
  xmm1 = _mm_shuffle_epi32(dst, 0xFF);
  // Apply Premultipled Complement
  const __m128i half = _mm_set1_epi32(32767);
  src = _mm_multiply_color(src, xmm1);
  dst = _mm_multiply_color(dst, xmm0);

  xmm0 = _mm_cmpgt_epi32(src, half);
  xmm2 = _mm_sub_epi32(src, half);
  xmm1 = _mm_add_epi32(src, src);
  xmm2 = _mm_add_epi32(xmm2, xmm2);
  // (s < 0.5) ? max(2 * s, d) : min(2 * s - 1)
  xmm1 = _mm_min_epi32(xmm1, dst);
  xmm2 = _mm_max_epi32(xmm2, dst);
  src = _mm_blendv_epi8(xmm1, xmm2, xmm0);

  return src;
}

__m128i blend_hardmix(__m128i src, __m128i dst) {
  __m128i xmm0, xmm1, alpha;
  xmm0 = _mm_shuffle_epi32(src, 0xFF);
  xmm1 = _mm_shuffle_epi32(dst, 0xFF);
  // Apply Premultiplied Complement
  const __m128i zeros = _mm_setzero_si128();
  alpha = _mm_multiply_color(xmm0, xmm1);
  src = _mm_multiply_color(src, xmm1);
  dst = _mm_multiply_color(dst, xmm0);

  // (s + d) > 1 ? 1 : 0
  xmm0 = _mm_add_epi32(src, dst);
  xmm1 = _mm_cmpgt_epi32(xmm0, alpha);
  xmm0 = _mm_blendv_epi8(zeros, alpha, xmm1);
  
  return xmm0;
}

// --------------------------
// Compare Blending Functions
// --------------------------

__m128i blend_difference(__m128i src, __m128i dst) {
  __m128i xmm0, xmm1, alpha;
  xmm0 = _mm_shuffle_epi32(src, 0xFF);
  xmm1 = _mm_shuffle_epi32(dst, 0xFF);
  // Apply Premultipled Complement
  alpha = _mm_multiply_color(xmm0, xmm1);
  src = _mm_multiply_color(src, xmm1);
  dst = _mm_multiply_color(dst, xmm0);

  // abs(s - d)
  xmm0 = _mm_sub_epi32(src, dst);
  xmm0 = _mm_abs_epi32(xmm0);
  xmm0 = _mm_blend_epi16(xmm0, alpha, 0xC0);

  return xmm0;
}

__m128i blend_exclusion(__m128i src, __m128i dst) {
  __m128i xmm0, xmm1, alpha, mullo;
  xmm0 = _mm_shuffle_epi32(src, 0xFF);
  xmm1 = _mm_shuffle_epi32(dst, 0xFF);
  // Apply Premultipled Complement
  alpha = _mm_multiply_color(xmm0, xmm1);
  mullo = _mm_multiply_color(src, dst);
  src = _mm_multiply_color(src, xmm1);
  dst = _mm_multiply_color(dst, xmm0);

  // s + d - 2 * s * d
  xmm0 = _mm_add_epi32(src, dst);
  xmm1 = _mm_add_epi32(mullo, mullo);
  xmm0 = _mm_sub_epi32(xmm0, xmm1);
  xmm0 = _mm_blend_epi16(xmm0, alpha, 0xC0);

  return xmm0;
}

__m128i blend_substract(__m128i src, __m128i dst) {
  __m128i xmm0, xmm1, alpha;
  xmm0 = _mm_shuffle_epi32(src, 0xFF);
  xmm1 = _mm_shuffle_epi32(dst, 0xFF);
  // Apply Premultipled Complement
  alpha = _mm_multiply_color(xmm0, xmm1);
  src = _mm_multiply_color(src, xmm1);
  dst = _mm_multiply_color(dst, xmm0);

  // d - s
  xmm0 = _mm_sub_epi32(dst, src);
  xmm0 = _mm_blend_epi16(xmm0, alpha, 0xC0);

  return xmm0;
}

__m128i blend_divide(__m128i src, __m128i dst) {
  const __m128 zeros = _mm_setzero_ps();
  const __m128 ones = _mm_set1_ps(1.0);
  const __m128 xmm65535 = _mm_set1_ps(65535.0);
  const __m128 rcp65535 = _mm_rcp_ps(xmm65535);

  __m128 xmm0, xmm1, xmm2, xmm3;
  // Convert to Float and Normalize
  __m128 src0 = _mm_cvtepi32_ps(src);
  __m128 dst0 = _mm_cvtepi32_ps(dst);
  src0 = _mm_mul_ps(src0, rcp65535);
  dst0 = _mm_mul_ps(dst0, rcp65535);
  // Convert to Straight Alpha
  __m128 sa = _mm_shuffle_ps(src0, src0, 0xFF);
  __m128 da = _mm_shuffle_ps(dst0, dst0, 0xFF);
  src0 = _mm_div_ps(src0, sa);
  dst0 = _mm_div_ps(dst0, da);

  // clamp(d / s, 0, 1)
  src0 = _mm_div_ps(dst0, src0);
  src0 = _mm_max_ps(src0, zeros);
  src0 = _mm_min_ps(src0, ones);

  // Convert to Premultiply
  xmm0 = _mm_mul_ps(sa, da);
  src0 = _mm_mul_ps(src0, xmm0);
  src0 = _mm_blend_ps(src0, xmm0, 0x8);
  // Convert Back to Integer
  src0 = _mm_mul_ps(src0, xmm65535);
  return _mm_cvtps_epi32(src0);
}

// ----------------------
// Composite Blending HSL
// ----------------------

static inline __m128 hsl_minmax(__m128 color) {
  __m128 r, g, b, min, max;
  r = _mm_shuffle_ps(color, color, _MM_SHUFFLE(0, 0, 0, 0));
  g = _mm_shuffle_ps(color, color, _MM_SHUFFLE(1, 1, 1, 1));
  b = _mm_shuffle_ps(color, color, _MM_SHUFFLE(2, 2, 2, 2));
  // Calculate Minimum And Maximun
  min = _mm_min_ps(r, g);
  max = _mm_max_ps(r, g);
  min = _mm_min_ps(min, b);
  max = _mm_max_ps(max, b);
  // [MIN, MIN, MAX, MAX]
  return _mm_shuffle_ps(min, max, 0);
}

static inline __m128 hsl_saturation(__m128 minmax) {
  __m128 min = _mm_shuffle_ps(minmax, minmax, 0);
  __m128 max = _mm_shuffle_ps(minmax, minmax, 0xFF);
  // Substract Maximun and Minimun
  return _mm_sub_ps(max, min);
}

static inline __m128 hsl_luminosity(__m128 color) {
  const __m128 gray = _mm_set_ps(0.0, 0.11, 0.59, 0.30);
  return _mm_dp_ps(color, gray, 0x7F);
}

static inline __m128 hsl_setclip(__m128 color) {
  const __m128 zeros = _mm_setzero_ps();
  const __m128 ones = _mm_set1_ps(1.0);
  __m128 xmm0, xmm1, xmm2;
  __m128i check;

  xmm0 = hsl_minmax(color);
  // Calculate Luminosity, Min and Max
  __m128 lum = hsl_luminosity(color);
  __m128 min = _mm_shuffle_ps(xmm0, xmm0, 0);
  __m128 max = _mm_shuffle_ps(xmm0, xmm0, 0xFF);

  xmm2 = _mm_cmplt_ps(min, zeros);
  check = _mm_castps_si128(xmm2);
  // xmm0 = (color - lum) * lum
  // xmm1 = rcp(lum - min)
  // xmm0 = lum + xmm0 * xmm1
  if (_mm_testz_si128(check, check) == 0) {
    xmm1 = _mm_sub_ps(lum, min);
    xmm0 = _mm_sub_ps(color, lum);
    xmm1 = _mm_rcp_ps(xmm1);
    xmm0 = _mm_mul_ps(xmm0, lum);
    xmm0 = _mm_mul_ps(xmm0, xmm1);
    color = _mm_add_ps(lum, xmm0);
  }

  xmm2 = _mm_cmpgt_ps(max, ones);
  check = _mm_castps_si128(xmm2);
  // xmm0 = (color - lum) * (1 - lum)
  // xmm1 = rcp(max - lum)
  // xmm0 = lum + xmm0 * xmm1
  if (_mm_testz_si128(check, check) == 0) {
    xmm1 = _mm_sub_ps(max, lum);
    xmm0 = _mm_sub_ps(color, lum);
    xmm2 = _mm_mul_ps(xmm0, lum);
    xmm1 = _mm_rcp_ps(xmm1);
    xmm0 = _mm_sub_ps(xmm0, xmm2);
    xmm0 = _mm_mul_ps(xmm0, xmm1);
    color = _mm_add_ps(lum,  xmm0);
  }

  return color;
}

static inline __m128 hsl_setlum(__m128 color, __m128 lum) {
  __m128 l0 = hsl_luminosity(color);
  __m128 l1 = hsl_luminosity(lum);
  // color + (l1 - l0)
  l0 = _mm_sub_ps(l1, l0);
  color = _mm_add_ps(color, l0);

  return hsl_setclip(color);
}

static inline __m128 hsl_setlumsat(__m128 color, __m128 sat, __m128 lum) {
  __m128 xmm0, xmm1;
  xmm0 = hsl_minmax(color);
  xmm1 = hsl_minmax(sat);

  __m128 min = _mm_shuffle_ps(xmm0, xmm0, 0);
  __m128 sat0 = hsl_saturation(xmm0);
  __m128 sat1 = hsl_saturation(xmm1);

  // (color - min) * sat1 / sat0
  xmm0 = _mm_sub_ps(color, min);
  xmm0 = _mm_mul_ps(xmm0, sat1);
  xmm1 = _mm_rcp_ps(sat0);
  xmm0 = _mm_mul_ps(xmm0, xmm1);
  // Avoid Zero Division
  min = _mm_setzero_ps();
  xmm1 = _mm_cmpgt_ps(sat0, min);
  color = _mm_and_ps(xmm0, xmm1);

  return hsl_setlum(color, lum);
}

// ----------------------------
// Composite Blending Functions
// ----------------------------

__m128i blend_hue(__m128i src, __m128i dst) {
  const __m128 zeros = _mm_setzero_ps();
  const __m128 xmm65535 = _mm_set1_ps(65535.0);
  const __m128 rcp65535 = _mm_rcp_ps(xmm65535);
  // Convert to Float and Straight 
  __m128 src0 = _mm_cvtepi32_ps(src);
  __m128 dst0 = _mm_cvtepi32_ps(dst);
  src0 = _mm_mul_ps(src0, rcp65535);
  dst0 = _mm_mul_ps(dst0, rcp65535);
  __m128 sa = _mm_shuffle_ps(src0, src0, 0xFF);
  __m128 da = _mm_shuffle_ps(dst0, dst0, 0xFF);
  src0 = _mm_div_ps(src0, sa);
  dst0 = _mm_div_ps(dst0, da);

  // Apply Blending Mode
  src0 = hsl_setlumsat(src0, dst0, dst0);
  // Convert to Premultiplied
  dst0 = _mm_mul_ps(sa, da);
  src0 = _mm_mul_ps(src0, dst0);
  src0 = _mm_max_ps(src0, zeros);
  src0 = _mm_blend_ps(src0, dst0, 0x8);
  // Convert Back to Integer
  src0 = _mm_mul_ps(src0, xmm65535);
  return _mm_cvtps_epi32(src0);
}

__m128i blend_saturation(__m128i src, __m128i dst) {
  const __m128 zeros = _mm_setzero_ps();
  const __m128 xmm65535 = _mm_set1_ps(65535.0);
  const __m128 rcp65535 = _mm_rcp_ps(xmm65535);
  // Convert to Float and Straight 
  __m128 src0 = _mm_cvtepi32_ps(src);
  __m128 dst0 = _mm_cvtepi32_ps(dst);
  src0 = _mm_mul_ps(src0, rcp65535);
  dst0 = _mm_mul_ps(dst0, rcp65535);
  __m128 sa = _mm_shuffle_ps(src0, src0, 0xFF);
  __m128 da = _mm_shuffle_ps(dst0, dst0, 0xFF);
  src0 = _mm_div_ps(src0, sa);
  dst0 = _mm_div_ps(dst0, da);

  // Apply Blending Mode
  src0 = hsl_setlumsat(dst0, src0, dst0);
  // Convert to Premultiplied
  dst0 = _mm_mul_ps(sa, da);
  src0 = _mm_mul_ps(src0, dst0);
  src0 = _mm_max_ps(src0, zeros);
  src0 = _mm_blend_ps(src0, dst0, 0x8);
  // Convert Back to Integer
  src0 = _mm_mul_ps(src0, xmm65535);
  return _mm_cvtps_epi32(src0);
}

__m128i blend_color(__m128i src, __m128i dst) {
  const __m128 zeros = _mm_setzero_ps();
  const __m128 xmm65535 = _mm_set1_ps(65535.0);
  const __m128 rcp65535 = _mm_rcp_ps(xmm65535);
  // Convert to Float and Straight 
  __m128 src0 = _mm_cvtepi32_ps(src);
  __m128 dst0 = _mm_cvtepi32_ps(dst);
  src0 = _mm_mul_ps(src0, rcp65535);
  dst0 = _mm_mul_ps(dst0, rcp65535);
  __m128 sa = _mm_shuffle_ps(src0, src0, 0xFF);
  __m128 da = _mm_shuffle_ps(dst0, dst0, 0xFF);
  src0 = _mm_div_ps(src0, sa);
  dst0 = _mm_div_ps(dst0, da);

  // Apply Blending Mode
  src0 = hsl_setlum(src0, dst0);
  // Convert to Premultiplied
  dst0 = _mm_mul_ps(sa, da);
  src0 = _mm_mul_ps(src0, dst0);
  src0 = _mm_max_ps(src0, zeros);
  src0 = _mm_blend_ps(src0, dst0, 0x8);
  // Convert Back to Integer
  src0 = _mm_mul_ps(src0, xmm65535);
  return _mm_cvtps_epi32(src0);
}

__m128i blend_luminosity(__m128i src, __m128i dst) {
  const __m128 zeros = _mm_setzero_ps();
  const __m128 xmm65535 = _mm_set1_ps(65535.0);
  const __m128 rcp65535 = _mm_rcp_ps(xmm65535);
  // Convert to Float and Straight 
  __m128 src0 = _mm_cvtepi32_ps(src);
  __m128 dst0 = _mm_cvtepi32_ps(dst);
  src0 = _mm_mul_ps(src0, rcp65535);
  dst0 = _mm_mul_ps(dst0, rcp65535);
  __m128 sa = _mm_shuffle_ps(src0, src0, 0xFF);
  __m128 da = _mm_shuffle_ps(dst0, dst0, 0xFF);
  src0 = _mm_div_ps(src0, sa);
  dst0 = _mm_div_ps(dst0, da);

  // Apply Blending Mode
  src0 = hsl_setlum(dst0, src0);
  // Convert to Premultiplied
  dst0 = _mm_mul_ps(sa, da);
  src0 = _mm_mul_ps(src0, dst0);
  src0 = _mm_max_ps(src0, zeros);
  src0 = _mm_blend_ps(src0, dst0, 0x8);
  // Convert Back to Integer
  src0 = _mm_mul_ps(src0, xmm65535);
  return _mm_cvtps_epi32(src0);
}

// ---------------
// Array Blendings
// ---------------

const blend_proc_t blend_procs[] = {
  blend_normal,
  blend_normal,
  // Darker Blendings
  blend_multiply,
  blend_darken,
  blend_colorburn,
  blend_linearburn,
  blend_darkercolor,
  // Light Blendings
  blend_screen,
  blend_lighten,
  blend_colordodge,
  blend_lineardodge,
  blend_lightercolor,
  // Contrast Blendings
  blend_overlay,
  blend_softlight,
  blend_hardlight,
  blend_vividlight,
  blend_linearlight,
  blend_pinlight,
  blend_hardmix,
  // Compare Blendings
  blend_difference,
  blend_exclusion,
  blend_substract,
  blend_divide,
  // Composite Blendings
  blend_hue,
  blend_saturation,
  blend_color,
  blend_luminosity
};
