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

void brush_water_first(brush_render_t* render) {
  int x1, x2, y1, y2;
  // Render Region
  x1 = render->x;
  y1 = render->y;
  x2 = x1 + render->w;
  y2 = y1 + render->h;

  __m128i color0, color1;
  int count0, count1;
  // Initialize Counters
  color0 = _mm_setzero_si128();
  count0 = count1 = 0;

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
        color1 = _mm_cvtepi16_epi32(color1);
        color1 = _mm_srli_epi32(color1, 4);
        // Sum Color Average & Color Count
        color0 = _mm_add_epi32(color0, color1);
        count1 += _mm_testz_si128(color1, color1) == 0;
        // Sum Mask Count
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
  avg->count0 = count0;
  avg->count1 = count1;
  // Replace Acumulated Color
  _mm_storeu_si128((__m128i*) avg->color_sum, color0);
}

void brush_water_blend(brush_render_t* render) {

}
