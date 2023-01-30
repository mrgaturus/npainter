// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2021 Cristian Camilo Ruiz <mrgaturus>
#include "brush.h"

static __m128i _mm_mix_65535(__m128i xmm0, __m128i xmm1, __m128i fract) {
  const __m128i one = _mm_set1_epi32(65535);
  // Calculate Interpolation
  xmm1 = _mm_mullo_epi32(xmm1, fract);
  fract = _mm_sub_epi32(one, fract);
  xmm0 = _mm_mullo_epi32(xmm0, fract);
  xmm0 = _mm_add_epi32(xmm0, xmm1);
  // Ajust 16bit Fixed Point
  xmm0 = _mm_add_epi32(xmm0, one);
  xmm0 = _mm_srli_epi32(xmm0, 16);
  // Return Interpolated
  return xmm0;
}

// ----------------------------
// BRUSH SIMPLE COLOR AVERAGING
// ----------------------------

void brush_water_first(brush_render_t* render) {
  int x1, x2, y1, y2;
  // Render Region
  x1 = render->x;
  y1 = render->y;
  x2 = x1 + render->w;
  y2 = y1 + render->h;

  __m128i color0, color1, xmm0;
  // Initialize Acumulator
  color0 = _mm_setzero_si128();
  // Initialize Count
  int count0 = 0;

  int s_shape, s_dst;
  // Brush Shape Mask Stride
  s_shape = render->canvas->stride;
  // Brush Destination Stride
  s_dst = s_shape << 2;

  short *dst_y, *dst_x;
  // Load Pixel Buffer Pointer
  dst_y = render->canvas->dst;
  // Locate Destination Pointer to Render Position
  dst_y += (render->y * s_shape + render->x) << 2;

  short *sh_y, *sh_x, sh;
  // Load Mask Buffer Pointer
  sh_y = render->canvas->buffer0;
  // Locate Shape Pointer to Render Position
  sh_y += (render->y * s_shape) + render->x;

  brush_average_t* avg;
  // Load Current Average Block
  avg = (brush_average_t*) render->opaque;

  // Apply Blending Mode
  for (int y = y1; y < y2; y++) {
    sh_x = sh_y;
    dst_x = dst_y;

    for (int x = x1; x < x2; x++) {
      // Check if is not zero
      if (sh = *sh_x) {
        color1 = _mm_loadl_epi64((__m128i*) dst_x);
        color1 = _mm_cvtepu16_epi32(color1);
        // Check if Pixel is Visible Enough
        xmm0 = _mm_srli_epi32(color1, 8);

        // Sum Color Accumulation
        if (_mm_testz_si128(xmm0, xmm0) == 0)
          color0 = _mm_add_epi32(color0, color1);
        // Sum Color Count
        count0++;
      }
      // Step Shape & Color
      sh_x++; dst_x += 4;
    }

    // Step Stride
    sh_y += s_shape;
    dst_y += s_dst;
  }

  // Replace Counters
  avg->count = count0;
  // Replace Acumulated Color
  _mm_storeu_si128((__m128i*) avg->total, color0);
}

// ------------------------------
// BRUSH AVERAGED FIXLINEAR BLEND
// ------------------------------

static __m128i brush_water_pixel(short* buffer, int stride, int u, int v) {
  int x, y;
  // Pixel Position
  x = u >> 16;
  y = v >> 16;
  // Buffer Position
  x = (y * stride + x) << 2;
  y = x + (stride << 2);

  __m128i fx, fy;
  // Remainder
  fx = _mm_set1_epi32(u & 0xFFFF);
  fy = _mm_set1_epi32(v & 0xFFFF);
  __m128i xmm0, m00, m10, m01, m11;
  // Load Top Two Pixels
  xmm0 = _mm_loadu_si128(
    (__m128i*) (buffer + x));
  // Unpack Top Two Pixels
  m00 = _mm_cvtepu16_epi32(xmm0);
  xmm0 = _mm_srli_si128(xmm0, 8);
  m10 = _mm_cvtepu16_epi32(xmm0);
  // Load Top Two Pixels
  xmm0 = _mm_loadu_si128(
    (__m128i*) (buffer + y));
  // Unpack Top Two Pixels
  m01 = _mm_cvtepu16_epi32(xmm0);
  xmm0 = _mm_srli_si128(xmm0, 8);
  m11 = _mm_cvtepu16_epi32(xmm0);

  __m128i result;
  // Interpolate Horizontally
  m00 = _mm_mix_65535(m00, m10, fx);
  m11 = _mm_mix_65535(m01, m11, fx);
  // Interpolate Vertically
  result = _mm_mix_65535(m00, m11, fy);

  // Return Interpolated
  return result;
}

void brush_water_blend(brush_render_t* render) {
  int x1, x2, y1, y2;
  // Render Region
  x1 = render->x;
  y1 = render->y;
  x2 = x1 + render->w;
  y2 = y1 + render->h;

  int s_shape, s_dst;
  // Brush Shape Mask Stride
  s_shape = render->canvas->stride;
  // Brush Destination Stride
  s_dst = s_shape << 2;

  short *dst_y, *dst_x;
  // Load Pixel Buffer Pointer
  dst_y = render->canvas->dst;
  // Locate Destination Pointer to Render Position
  dst_y += (render->y * s_shape + render->x) << 2;

  brush_water_t* water;
  // Load Watercolor Pointer
  water = (brush_water_t*) render->opaque;

  short* blur; int stride, size;
  int xx, row_xx, yy, fx, fy;
  // Load Watercolor Buffer
  blur = render->canvas->buffer1;
  // Load Watercolor Stride
  stride = water->stride;
  // Load Watercolor Interpolation
  fx = water->fx; xx = water->x;
  fy = water->fy; yy = water->y;

  unsigned short *sh_y, *sh_x, sh;
  // Load Mask Buffer Pointer
  sh_y = render->canvas->buffer0;
  // Locate Shape Pointer to Render Position
  sh_y += (render->y * s_shape) + render->x;

  __m128i color, alpha, xmm0, xmm1;
  // Load Unpacked Color Ones
  const __m128i one = _mm_set1_epi32(65535);

  // Apply Blending Mode
  for (int y = y1; y < y2; y++) {
    sh_x = sh_y;
    dst_x = dst_y;
    row_xx = xx;

    for (int x = x1; x < x2; x++) {
      // Check if is not zero
      if (sh = *sh_x) {
        alpha = _mm_cvtsi32_si128(sh);
        alpha = _mm_shuffle_epi32(alpha, 0);
        // Load Destination Pixel
        xmm0 = _mm_loadl_epi64((__m128i*) dst_x);
        xmm0 = _mm_cvtepu16_epi32(xmm0);
        // Load Color From Blur Buffer
        color = brush_water_pixel(
          blur, stride, row_xx, yy);

        // Interpolate To Color
        xmm1 = _mm_sub_epi32(one, alpha);
        xmm0 = _mm_mullo_epi32(xmm0, xmm1);
        xmm1 = _mm_mullo_epi32(color, alpha);
        xmm0 = _mm_add_epi32(xmm0, xmm1);
        // Ajust Color Fix16
        xmm0 = _mm_add_epi32(xmm0, one);
        xmm0 = _mm_srli_epi32(xmm0, 16);

        // Pack to Fix16 and Store
        xmm0 = _mm_packus_epi32(xmm0, xmm0);
        _mm_storel_epi64((__m128i*) dst_x, xmm0);
      }
      // Step Shape & Color
      sh_x++; dst_x += 4;
      // Step X Fixlinear
      row_xx += fx;
    }

    // Step Stride
    sh_y += s_shape;
    dst_y += s_dst;
    // Step Y Fixlinear
    yy += fy;
  }
}
