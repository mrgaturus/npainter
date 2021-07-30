#include <math.h>
#include "brush.h"

static inline short div_32767(int a) {
  return ( a + ( (a + 32769) >> 15 ) ) >> 15;
}

static short brush_texture_warp(brush_texture_t* tex, int x, int y) {
  int w, h;

  w = tex->w;
  h = tex->h;
  // Warp Pixel
  x %= w; y %= h;

  short pixel;
  // Lookup Pixel From Buffer
  pixel = tex->buffer[y * w + x];
  pixel = (pixel << 7) | pixel;

  // Return Pixel
  return pixel;
}

static short brush_texture_zero(brush_texture_t* tex, int x, int y) {
  int w, h;
  // Dimensions
  w = tex->w;
  h = tex->h;

  short pixel;
  // Lookup Pixel From Buffer
  if (x >= 0 && x < w && y >= 0 && y < h) {
    pixel = tex->buffer[y * w + x];
    pixel = (pixel << 7) | pixel;
  } else { pixel = 0; }

  return pixel;
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
      xmm_c = _mm_packs_epi32(xmm_c, xmm_c);

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

  int stride;
  // Canvas Buffer Stride
  stride = render->canvas->stride;

  short *dst_y, *dst_x;
  // Load Mask Buffer Pointer
  dst_y = render->canvas->buffer0;
  // Locate Buffer Pointer to Render Position
  dst_y += (render->y * stride) + render->x;

  brush_texture_t* tex;
  // Load Texture Pointer
  tex = blot->texture;

  short fract;
  // Load Interpolation
  fract = tex->fract;

  int pixel, mask, calc;
  // Apply Blotmap Difference
  for (int y = y1; y < y2; y++) {
    dst_x = dst_y;

    for (int x = x1; x < x2; x++) {
      // Check if is not zero
      if (pixel = *dst_x) {
        mask = brush_texture_warp(tex, x, y);
        // Calculate Pixel Difference
        mask = mask - pixel;
        if (mask < 0)
          mask = 0;

        // Interpolate Both Pixels
        calc = (mask - pixel) * fract;
        calc = pixel + div_32767(calc);
        // Replace Pixel
        *dst_x = calc;
      }

      // Step Pixel
      dst_x++;
    }

    // Step Stride
    dst_y += stride;
  }
}

// ---------------------------
// BRUSH BITMAP MASK RENDERING
// ---------------------------

static short brush_bitmap_one(brush_bitmap_t* bitmap, int x, int y) {
  short result;
  // Affine Calculation
  float calc_x, calc_y;

  calc_x = bitmap->a * x + bitmap->b * y + bitmap->c;
  calc_y = bitmap->d * x + bitmap->e * y + bitmap->f;

  x = (int) floor(calc_x + 0.5);
  y = (int) floor(calc_y + 0.5);

  // Lookup Pixel From Texture
  result = brush_texture_zero(bitmap->texture, x, y);
  // Return Bitmap Pixel
  return result;
}

static short brush_bitmap_area(brush_bitmap_t* bitmap, int x, int y, int level) {
  int size, area;
  // Calculate Area
  size = 1 << level;
  area = size << level;

  float calc, du, dv;
  // Reciprocal Subpixel Size
  const float rcp = 1.0 / (float) size;
  // 2x2 Inverse Affine with Partial Derivatives
  __m128 row_xxxx, xxxx, dudx, dvdx;
  __m128 row_yyyy, yyyy, dudy, dvdy;
  // Nearest Interpolation
  __m128 near_xxxx, near_yyyy;
  // Convert Position To Integer
  __m128i cvt_xxxx, cvt_yyyy;

  // -- Initialize X Derivatives
  du = bitmap->a; dv = bitmap->b;
  // Initialize X Position with Nearest Offset
  calc = du * x + dv * y + bitmap->c + 0.5;

  du *= rcp; dv *= rcp;
  // Initialize 2x2 X Position
  row_xxxx = _mm_set_ps(
    calc + du + dv,
    calc + dv,
    calc + du,
    calc);
  // Initialize X Derivative Steps
  dudx = _mm_set1_ps(du * 2.0);
  dvdx = _mm_set1_ps(dv * 2.0);

  // -- Initialize Y Derivatives
  du = bitmap->d; dv = bitmap->e;
  // Initialize Y Position with Nearest Offset
  calc = du * x + dv * y + bitmap->f + 0.5;

  du *= rcp; dv *= rcp;
  // Initialize 2x2 Y Position
  row_yyyy = _mm_set_ps(
    calc + du + dv,
    calc + dv,
    calc + du,
    calc);
  // Initialize Y Derivative Steps
  dudy = _mm_set1_ps(du * 2.0);
  dvdy = _mm_set1_ps(dv * 2.0);

  // Subpixel Sum
  int result = 0;
  // Load Texture Pointer
  brush_texture_t* tex;
  // Bitmap Texture Pointer
  tex = bitmap->texture;

  // Calculate Subpixel Sumation
  for (int sub_y = 0; sub_y < size; sub_y += 2) {
    xxxx = row_xxxx; yyyy = row_yyyy;

    for (int sub_x = 0; sub_x < size; sub_x += 2) {
      near_xxxx = _mm_round_ps(xxxx, 9);
      near_yyyy = _mm_round_ps(yyyy, 9);
      // Convert To Positions to Integer
      cvt_xxxx = _mm_cvtps_epi32(near_xxxx);
      cvt_yyyy = _mm_cvtps_epi32(near_yyyy);

      // Sum Each Pixel of 2x2
      for (int i = 0; i < 4; i++) {
        x = _mm_cvtsi128_si32(cvt_xxxx);
        y = _mm_cvtsi128_si32(cvt_xxxx);

        // Add Pixel to Subpixel Sumation
        result += brush_texture_zero(tex, x, y);
        // Shift One Pixel Position
        cvt_xxxx = _mm_srli_si128(cvt_xxxx, 4);
        cvt_yyyy = _mm_srli_si128(cvt_yyyy, 4);
      }

      // Step X Position
      xxxx = _mm_add_ps(xxxx, dudx);
      yyyy = _mm_add_ps(yyyy, dudy);
    }

    // Step Y Position
    row_xxxx = _mm_add_ps(row_xxxx, dvdx);
    row_yyyy = _mm_add_ps(row_yyyy, dvdy);
  }

  // Divide by area
  result >>= area;
  // Return Pixel
  return result;
}

void brush_bitmap_mask(brush_render_t* render, brush_bitmap_t* bitmap) {
  int x1, x2, y1, y2;
  // Render Region
  x1 = render->x;
  y1 = render->y;
  x2 = x1 + render->w;
  y2 = y1 + render->h;

  int level, stride;
  // Subpixel Level
  level = bitmap->level;
  // Canvas Buffer Stride
  stride = render->canvas->stride;

  short *dst_y, *dst_x, pixel;
  // Load Mask Buffer Pointer
  dst_y = render->canvas->buffer0;
  // Locate Buffer Pointer to Render Position
  dst_y += (render->y * stride) + render->x;

  for (int y = y1; y < y2; y++) {
    dst_x = dst_y;

    for (int x = x1; x < x2; x++) {
      if (level > 0) { // Check if needs Subpixel or not
        pixel = brush_bitmap_area(bitmap, x, y, level);
      } else { pixel = brush_texture_zero(bitmap, x, y); }

      // Replace Pixel
      *(dst_x) = pixel;
      // Step Pixel
      dst_x++;
    }

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

  int stride;
  // Canvas Buffer Stride
  stride = render->canvas->stride;

  short *dst_y, *dst_x;
  // Load Mask Buffer Pointer
  dst_y = render->canvas->buffer0;
  // Locate Buffer Pointer to Render Position
  dst_y += (render->y * stride) + render->x;

  short fract;
  // Load Interpolation
  fract = tex->fract;

  int pixel, mask, calc;
  // Apply Blotmap Difference
  for (int y = y1; y < y2; y++) {
    dst_x = dst_y;

    for (int x = x1; x < x2; x++) {
      // Check if is not zero
      if (pixel = *dst_x) {
        mask = brush_texture_warp(tex, x, y);
        // Calculate Pixel Multiply
        mask = div_32767(mask * pixel);

        // Interpolate Both Pixels
        calc = (mask - pixel) * fract;
        calc = pixel + div_32767(calc);
        // Replace Pixel
        *(dst_x) = calc;
      }

      // Step Pixel
      dst_x++;
    }

    // Step Stride
    dst_y += stride;
  }
}
