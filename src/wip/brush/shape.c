// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2021 Cristian Camilo Ruiz <mrgaturus>
#include <math.h>
#include "brush.h"

// --------------------------
// BRUSH TEXTURE LOOKUP PIXEL
// --------------------------

static int brush_texture_warp(brush_texture_t* tex, int x, int y) {
  const int w = tex->w;
  const int h = tex->h;
  // Warp Pixel
  if (x >= w) x -= w;
  if (y >= h) y -= h;

  // Lookup Pixel From Buffer
  int pixel = tex->buffer[y * w + x];

  // Return Pixel
  return pixel;
}

static int brush_texture_zero(brush_texture_t* tex, int x, int y) {
  // Dimensions
  const int w = tex->w;
  const int h = tex->h;

  int pixel;
  // Lookup Pixel From Buffer
  if (x >= 0 && y >= 0 && x < w && y < h) {
    pixel = tex->buffer[y * w + x];
  } else { pixel = 0; }

  return pixel;
}

// ----------------------------
// BRUSH TEXTURE BILINEAR PIXEL
// ----------------------------

static short brush_bilinear_warp(brush_texture_t* tex, int x, int y) {
  // Pixel Fractional
  const int fx = x & 65535;
  const int fy = y & 65535;
  // Pixel Position
  const int x0 = x >> 16;
  const int y0 = y >> 16;
  const int x1 = x0 + 1;
  const int y1 = y0 + 1;

  int m00, m10, m01, m11;
  // Load Four Pixels
  m00 = brush_texture_warp(tex, x0, y0);
  m10 = brush_texture_warp(tex, x1, y0);
  m01 = brush_texture_warp(tex, x0, y1);
  m11 = brush_texture_warp(tex, x1, y1);

  // Bilinear Interpolate
  m00 += (m10 - m00) * fx + 65535 >> 16;
  m01 += (m11 - m01) * fx + 65535 >> 16;
  m00 += (m01 - m00) * fy + 65535 >> 16;
  // Return Interpolated
  return m00;
}

static short brush_bilinear_zero(brush_texture_t* tex, int x, int y) {
  // Pixel Fractional
  const int fx = x & 32767;
  const int fy = y & 32767;
  // Pixel Position
  const int x0 = x >> 15;
  const int y0 = y >> 15;
  const int x1 = x0 + 1;
  const int y1 = y0 + 1;

  int m00, m10, m01, m11;
  // Load Four Pixels
  m00 = brush_texture_zero(tex, x0, y0);
  m10 = brush_texture_zero(tex, x1, y0);
  m01 = brush_texture_zero(tex, x0, y1);
  m11 = brush_texture_zero(tex, x1, y1);

  // Bilinear Interpolate
  m00 += (m10 - m00) * fx + 255 >> 15;
  m01 += (m11 - m01) * fx + 255 >> 15;
  m00 += (m01 - m00) * fy + 255 >> 15;
  // Return Interpolated
  return m00;
}

// ---------------------------
// BRUSH CIRCLE MASK RENDERING
// ---------------------------

void brush_circle_mask(brush_render_t* render, brush_circle_t* circle) {
  int z, w, h, stride, count;
  // Render Dimensions
  w = render->w;
  h = render->h;
  // Canvas Buffer Stride
  stride = render->canvas->stride;

  short *dst_y, *dst_x;
  // Load Mask Buffer Pointer
  dst_y = render->canvas->buffer0;
  // Locate Buffer Pointer to Render Position
  dst_y += (render->y * stride) + render->x;

  float size, smooth;
  // Load Circle Size
  size = circle->size;
  // Calculate Smoothstep
  smooth = circle->smooth;

  float alpha;
  // Load Shape Opacity
  alpha = (float) render->flow;

  // SIMD Center Positions
  __m128 xmm_cx, xmm_cy;
  // Load Circle Center Position
  xmm_cx = _mm_load1_ps(&circle->x);
  xmm_cy = _mm_load1_ps(&circle->y);

  // SIMD Pixel Positions
  __m128 xmm_x, xmm_y, xmm_row;
  // SIMD Circle Distance
  __m128 xmm_xx, xmm_yy;
  // SIMD Circle Smoothstep
  __m128 xmm_s0, xmm_s1;
  // SIMD Convert to Fix
  __m128i xmm_c;

  z = render->x;
  // Load X Initial Position
  xmm_c = _mm_set_epi32(z + 3, z + 2, z + 1, z);
  xmm_x = _mm_cvtepi32_ps(xmm_c);

  z = render->y;
  // Load Y Initial Position
  xmm_c = _mm_set1_epi32(render->y);
  xmm_y = _mm_cvtepi32_ps(xmm_c);

  // Set Render Position Steps
  const __m128 xmm_step_x = _mm_set1_ps(4.0);
  const __m128 xmm_step_y = _mm_set1_ps(1.0);

  // Set Smoothstep Constants
  const __m128 xmm_0 = _mm_set1_ps(0.0);
  const __m128 xmm_1 = _mm_set1_ps(1.0);
  const __m128 xmm_2 = _mm_set1_ps(2.0);
  const __m128 xmm_3 = _mm_set1_ps(3.0);
  
  const __m128 xmm_half = _mm_set1_ps(0.5);
  const __m128 xmm_fix = _mm_set1_ps(alpha);
  // Set Smoothstep Divisor Constant
  const __m128 xmm_smooth = _mm_load1_ps(&smooth);
  const __m128 xmm_rcp = _mm_set1_ps(1.0 / size);

  // Raster Each Four Pixels
  for (int y = 0; y < h; y++) {
    count = w;
    // Reset Row
    dst_x = dst_y;
    xmm_row = xmm_x;

    // Calculate Y Distance From Center
    xmm_yy = _mm_sub_ps(xmm_cy, xmm_y);
    xmm_yy = _mm_mul_ps(xmm_yy, xmm_yy);
    // Render Four Circle Pixels
    while (count > 0) {
      // Calculate X Distance From Center
      xmm_xx = _mm_sub_ps(xmm_cx, xmm_row);
      xmm_xx = _mm_mul_ps(xmm_xx, xmm_xx);
      
      // Calculate Vector Magnitude
      xmm_s0 = _mm_add_ps(xmm_xx, xmm_yy);

      xmm_s1 = _mm_rsqrt_ps(xmm_s0);
      xmm_s1 = _mm_mul_ps(xmm_s0, xmm_s1);
      xmm_s1 = _mm_mul_ps(xmm_s1, xmm_rcp);

      // Calculate Smoothstep Interpolation
      xmm_s1 = _mm_sub_ps(xmm_s1, xmm_half);
      xmm_s1 = _mm_mul_ps(xmm_s1, xmm_smooth);

      xmm_s1 = _mm_max_ps(xmm_s1, xmm_0);
      xmm_s1 = _mm_min_ps(xmm_s1, xmm_1);

      xmm_s0 = _mm_mul_ps(xmm_s1, xmm_2);
      xmm_s0 = _mm_sub_ps(xmm_3, xmm_s0);
      xmm_s1 = _mm_mul_ps(xmm_s1, xmm_s1);
      xmm_s1 = _mm_mul_ps(xmm_s1, xmm_s0);

      // Convert to Fixed 16-bit
      xmm_s1 = _mm_mul_ps(xmm_s1, xmm_fix);
      // Convert to Integer and Pack
      xmm_c = _mm_cvtps_epi32(xmm_s1);
      xmm_c = _mm_packus_epi32(xmm_c, xmm_c);

      // Store Four Pixels
      if (count >= 4) {
        // Store Calculated Circle Pixels
        _mm_storel_epi64((__m128i*) dst_x, xmm_c);
        // Step Four X Render Positions
        xmm_row = _mm_add_ps(xmm_row, xmm_step_x);
        // Step Four Pixels and Skip
        dst_x += 4; count -= 4; continue;
      }

      // Store Two Pixels
      if (count >= 2) {
        _mm_storeu_si32((__m128*) dst_x, xmm_c);
        // Step Two Pixels
        xmm_c = _mm_srli_si128(xmm_c, 4);
        dst_x += 2; count -= 2;
      }

      // Store One Pixel
      if (count == 1) {
        _mm_storeu_si16((__m128*) dst_x, xmm_c);
        // Step One Pixel
        dst_x++; count--;
      }
    }

    // Step Four Y Render Positions
    xmm_y = _mm_add_ps(xmm_y, xmm_step_y);
    // Step Stride
    dst_y += stride;
  }
}

// ----------------------------
// BRUSH BLOTMAP MASK RENDERING
// ----------------------------

void brush_blotmap_mask(brush_render_t* render, brush_blotmap_t* blot) {
  // Render Circle First
  brush_circle_mask(render, &blot->circle);
  
  int x1, x2, y1, y2;
  // Render Region
  x1 = render->x;
  y1 = render->y;
  x2 = x1 + render->w;
  y2 = y1 + render->h;

  int stride, flow;
  // Canvas Buffer Stride
  stride = render->canvas->stride;
  // Shape Current Flow
  flow = render->flow;

  unsigned short *dst_y, *dst_x;
  // Load Mask Buffer Pointer
  dst_y = render->canvas->buffer0;
  // Locate Buffer Pointer to Render Position
  dst_y += (render->y * stride) + render->x;

  brush_texture_t* tex;
  // Load Texture Pointer
  tex = blot->tex;
  // Load Texture Interpolation
  unsigned int fract = tex->fract;
  unsigned int invert = fract & 65536;
  fract = (fract & 65535) * flow + 65535 >> 16;
  // Load Texture Tone
  const int tone0 = tex->tone0;
  const int tone1 = tex->tone1;

  int row_xx, xx, yy;
  // Calculate Sized Scaled
  const int fixed = tex->fixed;
  const int fw = tex->w << 16;
  const int fh = tex->h << 16;
  // Calculate Fixed Interpolation
  xx = (x1 * fixed) % fw;
  yy = (y1 * fixed) % fh;

  unsigned int pixel, mask;
  // Apply Blotmap Difference
  for (int y = y1; y < y2; y++) {
    row_xx = xx;
    dst_x = dst_y;

    for (int x = x1; x < x2; x++) {
      // Check if is not zero
      if (pixel = *dst_x) {
        mask = brush_bilinear_warp(tex, row_xx, yy);
        if (invert) mask = 255 - mask;
        // Ajust Current Blotmap Pixel
        mask = mask * fract + fract >> 8;

        // Calculate Pixel Difference
        if (pixel > mask)
          mask = pixel - mask;
        else mask = 0;
        // Ajust Pixel Thresholding
        if (mask > tone0)
          mask = tone0;
        mask = mask * tone1 >> 16;

        // Replace Pixel
        *dst_x = mask;
      }

      // Step Pixel
      dst_x++;
      // Step Scaler
      row_xx += fixed;
      if (row_xx >= fw)
        row_xx -= fw;
    }

    // Step Stride
    dst_y += stride;
    // Step Scaler
    yy += fixed;
    if (yy >= fh)
      yy -= fh;
  }
}

// ---------------------------
// BRUSH BITMAP MASK RENDERING
// ---------------------------

void brush_bitmap_mask(brush_render_t* render, brush_bitmap_t* bitmap) {
  int x1, x2, y1, y2;
  // Render Region
  x1 = render->x;
  y1 = render->y;
  x2 = x1 + render->w;
  y2 = y1 + render->h;

  int stride, flow;
  // Canvas Buffer Stride
  stride = render->canvas->stride;
  // Shape Current Flow
  flow = render->flow;

  unsigned int pixel;
  unsigned short *dst_y, *dst_x;
  // Load Mask Buffer Pointer
  dst_y = render->canvas->buffer0;
  // Locate Buffer Pointer to Render Position
  dst_y += (render->y * stride) + render->x;

  brush_texture_t* tex;
  // Load Texture Pointer
  tex = bitmap->tex;

  // Load X Affine Transform
  const int a = bitmap->a;
  const int b = bitmap->b;
  const int c = bitmap->c;
  // Load Y Affine Transform
  const int d = bitmap->d;
  const int e = bitmap->e;
  const int f = bitmap->f;

  int xx, yy, row_xx, row_yy;
  // Locate Affine Transform
  xx = a * x1 + b * y1 + c - 16384;
  yy = d * x1 + e * y1 + f - 16384;

  for (int y = y1; y < y2; y++) {
    dst_x = dst_y;
    row_xx = xx;
    row_yy = yy;

    for (int x = x1; x < x2; x++) {
      // Lookup Current Pixel
      pixel = brush_bilinear_zero(tex, row_xx, row_yy);
      pixel = (pixel << 8) | pixel;
      pixel = pixel * flow + flow >> 16;
      // Replace Current Pixel
      *(dst_x) = pixel;

      // Step X Affine
      row_xx += a;
      row_yy += d;
      // Step Pixel
      dst_x++;
    }

    // Step Y Affine
    xx += b;
    yy += e;
    // Step Stride
    dst_y += stride;
  }
}

// ----------------------------------
// BRUSH TEXTURE APPLY MASK RENDERING
// ----------------------------------

void brush_texture_mask(brush_render_t* render, brush_texture_t* tex) {
  int x1, x2, y1, y2;
  // Render Region
  x1 = render->x;
  y1 = render->y;
  x2 = x1 + render->w;
  y2 = y1 + render->h;

  int stride, flow;
  // Canvas Buffer Stride
  stride = render->canvas->stride;

  unsigned short *dst_y, *dst_x;
  // Load Mask Buffer Pointer
  dst_y = render->canvas->buffer0;
  // Locate Buffer Pointer to Render Position
  dst_y += (render->y * stride) + render->x;

  unsigned int fract, froct, invert;
  // Load Texture Interpolation
  fract = tex->fract;
  invert = fract & 65536;
  fract &= 65535;
  // Load Inverse Interpolation
  froct = 65535 - fract;
  froct = 65535 * froct + froct >> 16;
  // Load Texture Tone
  const int tone0 = 65535 - tex->tone0;
  const int tone1 = tex->tone1;

  int row_xx, xx, yy;
  // Calculate Sized Scaled
  const int fixed = tex->fixed;
  const int fw = tex->w << 16;
  const int fh = tex->h << 16;
  // Calculate Fixed Interpolation
  xx = (x1 * fixed) % fw;
  yy = (y1 * fixed) % fh;

  unsigned int pixel, mask;
  // Apply Blotmap Difference
  for (int y = y1; y < y2; y++) {
    row_xx = xx;
    dst_x = dst_y;

    for (int x = x1; x < x2; x++) {
      // Check if is not zero
      if (pixel = *dst_x) {
        mask = brush_bilinear_warp(tex, row_xx, yy);
        if (invert) mask = 255 - mask;
        // Ajust Current Texture Pixel
        mask = mask * fract + fract >> 8;
        // Ajust Interpolation
        mask += froct;

        // Calculate Texture Scratch
        if (mask < tone0) mask = tone0;
        mask = (mask - tone0) * tone1 >> 16;

        // Apply Texture Multiply
        mask = pixel * mask + 65535 >> 16;
        // Replace Pixel
        *dst_x = mask;
      }

      // Step Pixel
      dst_x++;
      // Step Scaler
      row_xx += fixed;
      if (row_xx >= fw)
        row_xx -= fw;
    }

    // Step Stride
    dst_y += stride;
    // Step Scaler
    yy += fixed;
    if (yy >= fh)
      yy -= fh;
  }
}
