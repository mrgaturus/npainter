#include "brush.h"

void brush_normal_blend(brush_render_t* render) {
  int x1, x2, y1, y2;
  // Render Region
  x1 = render->x;
  y1 = render->y;
  x2 = x1 + render->w;
  y2 = y1 + render->h;

  __m128i color, alpha;
  __m128i xmm0, xmm1;
  // Load Unpacked Shape Color
  color = _mm_loadu_si128(render->color);
  // Load Unpacked Shape Color Ones
  const __m128i one = _mm_set1_epi32(65535);

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

  unsigned short *sh_y, *sh_x, sh;
  // Load Mask Buffer Pointer
  sh_y = render->canvas->buffer0;
  // Locate Shape Pointer to Render Position
  sh_y += (render->y * s_shape) + render->x;

  // Apply Blending Mode
  for (int y = y1; y < y2; y++) {
    sh_x = sh_y;
    dst_x = dst_y;

    for (int x = x1; x < x2; x++) {
      // Check if is not zero
      if (sh = *sh_x) {
        alpha = _mm_cvtsi32_si128(sh);
        alpha = _mm_shuffle_epi32(alpha, 0);
        // Load Destination Pixel
        xmm0 = _mm_loadl_epi64((__m128i*) dst_x);
        xmm0 = _mm_cvtepu16_epi32(xmm0);
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
    }

    // Step Stride
    sh_y += s_shape;
    dst_y += s_dst;
  }
}

void brush_func_blend(brush_render_t* render) {}

void brush_flat_blend(brush_render_t* render) {
  int x1, x2, y1, y2;
  // Render Region
  x1 = render->x;
  y1 = render->y;
  x2 = x1 + render->w;
  y2 = y1 + render->h;

  __m128i color, alpha, flow;
  // Color Calculation SIMD
  __m128i xmm0, xmm1, xmm2;
  // Load Current Flat Opacity
  flow = _mm_cvtsi32_si128(render->alpha);
  flow = _mm_shuffle_epi32(flow, 0);
  // Load Unpacked Shape Color
  color = _mm_loadu_si128(render->color);
  // Load Unpacked Shape Color Ones
  const __m128i one = _mm_set1_epi32(65535);

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

  unsigned short *sh_y, *sh_x, sh;
  // Load Mask Buffer Pointer
  sh_y = render->canvas->buffer0;
  // Locate Shape Pointer to Render Position
  sh_y += (render->y * s_shape) + render->x;

  // Apply Blending Mode
  for (int y = y1; y < y2; y++) {
    sh_x = sh_y;
    dst_x = dst_y;

    for (int x = x1; x < x2; x++) {
      // Check if is not zero
      if (sh = *sh_x) {
        alpha = _mm_cvtsi32_si128(sh);
        alpha = _mm_shuffle_epi32(alpha, 0);
        // Load Destination Pixel
        xmm0 = _mm_loadl_epi64((__m128i*) dst_x);
        xmm0 = _mm_cvtepu16_epi32(xmm0);

        // Use Max Opacity Between Two
        xmm2 = _mm_shuffle_epi32(xmm0, 0xFF);
        xmm2 = _mm_max_epu32(flow, xmm2);
        // Apply Opacity To Color
        xmm2 = _mm_mullo_epi32(color, xmm2);
        xmm2 = _mm_add_epi32(xmm2, one);
        xmm2 = _mm_srli_epi32(xmm2, 16);

        // Interpolate To Color
        xmm1 = _mm_sub_epi32(one, alpha);
        xmm0 = _mm_mullo_epi32(xmm0, xmm1);
        xmm1 = _mm_mullo_epi32(xmm2, alpha);
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
    }

    // Step Stride
    sh_y += s_shape;
    dst_y += s_dst;
  }
}

void brush_erase_blend(brush_render_t* render) {
  int x1, x2, y1, y2;
  // Render Region
  x1 = render->x;
  y1 = render->y;
  x2 = x1 + render->w;
  y2 = y1 + render->h;

  __m128i one, alpha;
  __m128i xmm0, xmm1;
  // Load Unpacked Color Ones
  one = _mm_set1_epi32(65535);

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

  unsigned short *sh_y, *sh_x, sh;
  // Load Mask Buffer Pointer
  sh_y = render->canvas->buffer0;
  // Locate Shape Pointer to Render Position
  sh_y += (render->y * s_shape) + render->x;

  // Apply Blending Mode
  for (int y = y1; y < y2; y++) {
    sh_x = sh_y;
    dst_x = dst_y;

    for (int x = x1; x < x2; x++) {
      // Check if is not zero
      if (sh = *sh_x) {
        alpha = _mm_cvtsi32_si128(sh);
        alpha = _mm_shuffle_epi32(alpha, 0);
        // Load Destination Pixel
        xmm0 = _mm_loadl_epi64((__m128i*) dst_x);
        xmm0 = _mm_cvtepu16_epi32(xmm0);
        // Interpolate To Color
        xmm1 = _mm_sub_epi32(one, alpha);
        xmm0 = _mm_mullo_epi32(xmm0, xmm1);
        // Ajust Color Fix16
        xmm0 = _mm_add_epi32(xmm0, one);
        xmm0 = _mm_srli_epi32(xmm0, 16);
        // Pack to Fix16 and Store
        xmm0 = _mm_packus_epi32(xmm0, xmm0);
        _mm_storel_epi64((__m128i*) dst_x, xmm0);
      }
      // Step Shape & Color
      sh_x++; dst_x += 4;
    }

    // Step Stride
    sh_y += s_shape;
    dst_y += s_dst;
  }
}