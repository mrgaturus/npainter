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
// BILINEAR INTERPOLATION PROCS
// ----------------------------

static __m128i brush_smudge_sample(short* src, int w, int h, int x, int y) {
  if (x < 0) x = 0; else if (x >= w) x = w - 1;
  if (y < 0) y = 0; else if (y >= h) y = h - 1;

  __m128i pixel;
  // Locate Pixel and Unpack
  src += (y * w + x) << 2;
  pixel = _mm_loadl_epi64((__m128i*) src);
  pixel = _mm_cvtepu16_epi32(pixel);

  // Return Pixel
  return pixel;
}

static __m128i brush_smudge_bilinear(short* src, int w, int h, int u, int v) {
  // Pixel Position
  const int x = u >> 16;
  const int y = v >> 16;

  __m128i m00, m10, m01, m11, fx, fy;
  // Position Fractional Part
  fx = _mm_set1_epi32(u & 0xFFFF);
  fy = _mm_set1_epi32(v & 0xFFFF);
  // Sample Four Clammped Pixels
  m00 = brush_smudge_sample(src, w, h, x + 0, y + 0);
  m10 = brush_smudge_sample(src, w, h, x + 1, y + 0);
  m01 = brush_smudge_sample(src, w, h, x + 0, y + 1);
  m11 = brush_smudge_sample(src, w, h, x + 1, y + 1);

  // Interpolate Horizontally
  m00 = _mm_mix_65535(m00, m10, fx);
  m11 = _mm_mix_65535(m01, m11, fx);
  // Interpolate Vertically
  m00 = _mm_mix_65535(m00, m11, fy);

  // Return Interpolated
  return m00;
}

// ----------------------------
// SMUDGE BUFFER BLENDING PROCS
// ----------------------------

void brush_smudge_first(brush_render_t* render) {
  __m128i xmm0;
  // Destination Region
  int x1 = render->x;
  int y1 = render->y;
  int x2 = x1 + render->w;
  int y2 = y1 + render->h;
  // Canvas Dimensions
  const int w = render->canvas->w;
  const int h = render->canvas->h;

  const brush_smudge_t* s = (brush_smudge_t*) render->opaque;
  // Load Position Delta
  int dx0, dx = (x1 << 16) - s->dx;
  int dy = (y1 << 16) - s->dy;

  short *src, *dst, *dst0;
  int stride = render->canvas->stride;
  // Canvas Pixel Buffer Stride
  src = render->canvas->dst;
  dst = render->canvas->buffer1;
  // Locate Pixel Buffer
  dst += (y1 * stride + x1) << 2;
  // Ajust Stride to Pixels
  stride <<= 2;

  for (int y = y1; y < y2; y++) {
    dst0 = dst;
    dx0 = dx;

    for (int x = x1; x < x2; x++) {
      // Sample Bilinear Clammped Pixel
      xmm0 = brush_smudge_bilinear(src, w, h, dx0, dy);
      xmm0 = _mm_packus_epi32(xmm0, xmm0);
      // Store Current Pixel
      _mm_storel_epi64((__m128i*) dst0, xmm0);

      // Step Pixel
      dst0 += 4;
      // Step Src
      dx0 += 65536;
    }

    // Step Stride
    dst += stride;
    // Step Src Stride
    dy += 65536;
  }
}

void brush_smudge_blend(brush_render_t* render) {
  int x1, x2, y1, y2;
  // Render Region
  x1 = render->x;
  y1 = render->y;
  x2 = x1 + render->w;
  y2 = y1 + render->h;

  __m128i alpha, xmm0, xmm1, xmm2;
  // Load Unpacked Shape Color Ones
  const __m128i one = _mm_set1_epi32(65535);

  int s_shape, s_pixel;
  // Brush Shape Mask Stride
  s_shape = render->canvas->stride;
  // Brush Destination Stride
  s_pixel = s_shape << 2;

  short *dst_y, *dst_x;
  // Load Pixel Buffer Pointer
  dst_y = render->canvas->dst;
  // Locate Destination Pointer to Render Position
  dst_y += (render->y * s_shape + render->x) << 2;

  short *src_y, *src_x;
  // Load Pixel Buffer Pointer
  src_y = render->canvas->buffer1;
  // Locate Destination Pointer to Render Position
  src_y += (render->y * s_shape + render->x) << 2;

  unsigned short *sh_y, *sh_x; int sh;
  // Load Mask Buffer Pointer
  sh_y = render->canvas->buffer0;
  // Locate Shape Pointer to Render Position
  sh_y += (render->y * s_shape) + render->x;

  // Apply Blending Mode
  for (int y = y1; y < y2; y++) {
    sh_x = sh_y;
    dst_x = dst_y;
    src_x = src_y;

    for (int x = x1; x < x2; x++) {
      // Check if is not zero
      if (sh = *sh_x) {
        // Load Four Opacity
        alpha = _mm_cvtsi32_si128(sh);
        alpha = _mm_shuffle_epi32(alpha, 0);
        // Load Destination Pixel
        xmm1 = _mm_loadl_epi64((__m128i*) src_x);
        xmm0 = _mm_loadl_epi64((__m128i*) dst_x);
        xmm0 = _mm_cvtepu16_epi32(xmm0);
        xmm1 = _mm_cvtepu16_epi32(xmm1);
        // Interpolate To Color
        xmm2 = _mm_sub_epi32(one, alpha);
        xmm0 = _mm_mullo_epi32(xmm0, xmm2);
        xmm2 = _mm_mullo_epi32(xmm1, alpha);
        xmm0 = _mm_add_epi32(xmm0, xmm2);
        // Ajust Color Fix16
        xmm0 = _mm_add_epi32(xmm0, one);
        xmm0 = _mm_srli_epi32(xmm0, 16);
        // Pack to Fix16 and Store
        xmm0 = _mm_packus_epi32(xmm0, xmm0);
        _mm_storel_epi64((__m128i*) dst_x, xmm0);
      }
      // Step Shape
      sh_x++; 
      // Step Color
      src_x += 4; 
      dst_x += 4;
    }

    // Step Shape Stride
    sh_y += s_shape;
    // Step Color Stride
    dst_y += s_pixel;
    src_y += s_pixel;
  }
}
