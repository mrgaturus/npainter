// TODO: USE LAYER BLENDING MODES FOR AVOID REDUNDANCY
#include <inttypes.h>
#include "brush.h"

// ( x + ( (x + 32769) >> 15 ) ) >> 15
static inline __m128i _mm_div_32767(__m128i xmm0) {
  __m128i xmm1; // Auxiliar
  const __m128i mask_div = 
    _mm_set1_epi32(32767);

  xmm1 = _mm_add_epi32(xmm0, mask_div);
  xmm1 = _mm_srai_epi32(xmm1, 15);
  xmm1 = _mm_add_epi32(xmm1, xmm0);
  xmm1 = _mm_srai_epi32(xmm1, 15);
  return xmm1; // 32767 Div
}

// -----------------------------------------------
//
// -----------------------------------------------

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
  color = _mm_loadl_epi64(render->color);
  color = _mm_cvtepi16_epi32(color);

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
        xmm0 = _mm_cvtepi16_epi32(xmm0);
        // Interpolate To Color
        xmm1 = _mm_sub_epi32(color, xmm0);
        xmm1 = _mm_mullo_epi32(xmm1, alpha);
        xmm1 = _mm_div_32767(xmm1);
        xmm1 = _mm_add_epi32(xmm0, xmm1);
        // Pack to Fix15 and Store
        xmm1 = _mm_packs_epi32(xmm1, xmm1);
        _mm_storel_epi64((__m128i*) dst_x, xmm1);
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
void brush_flat_blend(brush_render_t* render) {}
void brush_erase_blend(brush_render_t* render) {}