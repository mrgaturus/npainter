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

static inline __m128i _mm_mix_32767(__m128i xmm0, __m128i xmm1, __m128i fract) {
  xmm1 = _mm_sub_epi32(xmm1, xmm0);
  xmm1 = _mm_mullo_epi32(xmm1, fract);
  xmm1 = _mm_srai_epi32(xmm1, 15);
  xmm1 = _mm_add_epi32(xmm0, xmm1);
  // Return Interpolated
  return xmm1;
}

// ----------------------------
// BRUSH SIMPLE COLOR AVERAGING
// ----------------------------

static int brush_average_total(brush_render_t* render, __m128i* pixel, int x, int y, int w, int h) {
  int x1, x2, y1, y2;
  // Render Region
  x1 = x; x2 = x + w;
  y1 = y; y2 = y + h;

  int count = 0;
  __m128i color0, color1;
  // Initialize Counters
  color0 = _mm_setzero_si128();

  int s_shape, s_dst;
  // Brush Shape Mask Stride
  s_shape = render->canvas->stride;
  // Brush Destination Stride
  s_dst = s_shape << 2;

  short *dst_y, *dst_x;
  // Load Pixel Buffer Pointer
  dst_y = render->canvas->dst;
  // Locate Destination Pointer
  dst_y += (y * s_shape + x) << 2;

  short *sh_y, *sh_x, sh;
  // Load Mask Buffer Pointer
  sh_y = render->canvas->buffer0;
  // Locate Shape Pointer
  sh_y += (y * s_shape) + x;

  // Apply Blending Mode
  for (y = y1; y < y2; y++) {
    sh_x = sh_y;
    dst_x = dst_y;

    for (x = x1; x < x2; x++) {
      // Check if is not zero
      if (sh = *sh_x) {
        color1 = _mm_loadl_epi64((__m128i*) dst_x);
        color1 = _mm_cvtepi16_epi32(color1);
        color1 = _mm_srli_epi32(color1, 4);
        // Sum Color Average & Color Count
        color0 = _mm_add_epi32(color0, color1);
        // Sum Mask Count
        count++;
      }
      // Step Shape & Color
      sh_x++; dst_x += 4;
    }

    // Step Stride
    sh_y += s_shape;
    dst_y += s_dst;
  }

  // Return Acumulated Color
  _mm_store_si128(pixel, color0);
  // Return Mask Count
  return count;
}

void brush_average_first(brush_render_t* render) {
  // Pixel Accumulation & Count
  __m128i pixel; int count;

  brush_average_t* avg;
  // Load Current Average Block
  avg = (brush_average_t*) render->opaque;

  // Calculate Pixel Average
  count = brush_average_total(render, &pixel, 
    render->x, render->y, render->w, render->h);

  // Replace Counters
  avg->count0 = count;
  avg->count1 = count;
  // Replace Acumulated Color
  _mm_storeu_si128((__m128i*) avg->color_sum, pixel);
}

// ---------------------------
// BRUSH WATER COLOR AVERAGING
// ---------------------------

void brush_water_first(brush_render_t* render) {
  brush_water_t* water;
  // Load Current Average Block
  water = (brush_water_t*) render->opaque;

  const int alpha = render->alpha;
  // Water Strides
  const int s = water->s;
  const int ss = water->ss;

  int size, size_x, size_y;
  // Render Block Dimensions
  size_x = render->w >> ss;
  size_y = render->h >> ss;

  int re_w, re_h, w, h;
  // Render Size Mask
  size = (1 << ss) - 1;
  // Render Size Residuals
  re_w = render->w & size;
  re_h = render->h & size;
  // Water Subdivision Size
  size = 1 << (s - ss);

  int x, y, w_x, w_y;
  // Render Position
  x = render->x;
  y = render->y;
  // Water Position
  w_x = water->x * size;
  w_y = water->y * size;

  short *dst_y, *dst_x, s_dst;
  // Load Pixel Stride
  s_dst = water->stride;
  // Load Pixel Buffer Pointer
  dst_y = render->canvas->buffer1;
  // Locate Destination Pointer
  dst_y += (w_y * s_dst + w_x) << 2;
  // Stride to Pixel Size
  s_dst <<= 2;

  // Pixel Count
  int count, count0;
  // Pixel Calculation
  __m128i pixel, total;
  __m128 xmm0, xmm1;
  // Initialize Total Pixel
  count0 = count = 0;
  total = _mm_setzero_si128();

  // Iterate Each Sub-Block
  for (int oy = 0; oy < size; oy++) {
    dst_x = dst_y;

    for (int ox = 0; ox < size; ox++) {
      // Check if is Inside
      if (ox <= size_x && oy <= size_y) {
        // Define Sub-block Size
        if (ox == size_x) w = re_w; else w = 1 << ss;
        if (oy == size_y) h = re_h; else h = 1 << ss;

        // Calculate Sum of Pixel Block
        count0 = brush_average_total(render, &pixel,
          x + (ox << ss), y + (oy << ss), w, h);
        // Check if there is pixel
        if (count0 == 0)
          goto empty;

        // Sum Pixel Accumulation
        total = _mm_add_epi32(total, pixel);
        // Sum Pixel Count
        count += count0;

        pixel = _mm_slli_epi32(pixel, 4);
        // Divide Pixel By Count
        xmm0 = _mm_cvtepi32_ps(pixel);
        xmm1 = _mm_set1_ps((float) count0);
        xmm1 = _mm_rcp_ps(xmm1);
        xmm0 = _mm_mul_ps(xmm0, xmm1);
        // Convert Back to Fix15
        pixel = _mm_cvtps_epi32(xmm0);
        // Check if Needs Straight Alpha
        if (alpha == 0 && _mm_testz_si128(pixel, pixel) == 0) {
          const __m128 fix = _mm_set1_ps(32767.0);
          // Convert Pixel To Straight Alpha
          xmm1 = _mm_shuffle_ps(xmm0, xmm0, 0xFF);
          xmm1 = _mm_rcp_ps(xmm1);
          xmm0 = _mm_mul_ps(xmm0, xmm1);
          xmm0 = _mm_mul_ps(xmm0, fix);
          // Convert Back to Fix15
          pixel = _mm_cvtps_epi32(xmm0);
        }
      } else { empty:
        pixel = _mm_cmpeq_epi32(pixel, pixel);
        //pixel = _mm_setzero_si128();
      }

      // Replace Current Pixel
      pixel = _mm_packs_epi32(pixel, pixel);
      _mm_storel_epi64((__m128i*) dst_x, pixel);

      // Step X
      dst_x += 4;
    }

    // Step Y
    dst_y += s_dst;
  }

  // Return Averaged Pixel
  water->count0 = count;
  // Replace Acumulated Color
  _mm_storeu_si128((__m128i*) water->color_sum, total);
}

// ------------------------------
// BRUSH AVERAGED SIMPLE BOX BLUR
// ------------------------------

static __m128i brush_water_convolve(short* buffer, int w, int h, int x, int y) {
  __m128i pixel, ones, xmm0, xmm1; __m128 rcp, total;
  // Initialize Total and Count
  pixel = _mm_setzero_si128();

  int x1, y1, x2, y2;
  // Convolution Region
  x1 = x - 1; y1 = y - 1;
  x2 = x + 1; y2 = y + 1;
  // Clamp Convolution
  if (x1 < 0) x1 = 0;
  if (y1 < 0) y1 = 0;
  if (x2 >= w) x2 = w - 1;
  if (y2 >= h) y2 = h - 1;

  int stride, count = 0;
  // Buffer Pointer Steps
  short *buffer_x, *buffer_y;
  // Buffer Pointer Position
  buffer_y = buffer + ((y1 * w + x1) << 2);
  // Buffer Stride
  stride = w << 2;

  ones = _mm_cmpeq_epi32(ones, ones);
  // Calculate Convolution
  for (y = y1; y <= y2; y++) {
    buffer_x = buffer_y;

    for (x = x1; x <= x2; x++) {
      xmm0 = _mm_loadl_epi64((__m128i*) buffer_x);
      xmm1 = _mm_unpacklo_epi16(xmm0, xmm0);
      // Check if is not 0xFFFF
      if (_mm_testc_si128(xmm1, ones) == 0) {
        xmm0 = _mm_cvtepi16_epi32(xmm0);
        pixel = _mm_add_epi32(pixel, xmm0);
        // Increment Count
        count++;
      }

      // Step X
      buffer_x += 4;
    }

    // Step Stride
    buffer_y += stride;
  }

  if (count > 1) {
    // Load Counter and Aproximate
    xmm0 = _mm_cvtsi32_si128(count);
    xmm0 = _mm_shuffle_epi32(xmm0, 0);
    rcp = _mm_cvtepi32_ps(xmm0);
    rcp = _mm_rcp_ps(rcp);
    // Divide Pixel By Aproximated
    total = _mm_cvtepi32_ps(pixel);
    total = _mm_mul_ps(rcp, total);
    // Convert Back to Fix15
    pixel = _mm_cvtps_epi32(total);
  }

  return pixel;
}

static short* brush_water_expand(brush_render_t* render) {
  brush_water_t* water;
  // Load Current Water Block
  water = (brush_water_t*) render->opaque;

  __m128i pixel, color, alpha, xmm0;
  // Load Unpacked Shape Color
  color = _mm_loadl_epi64(render->color);
  color = _mm_cvtepi16_epi32(color);
  alpha = _mm_shuffle_epi32(color, 0xFF);

  int sss, w, h;
  // Sub-Block Dimensions
  sss = (water->s - water->ss);
  // Water Dimensions
  w = water->stride;
  h = water->rows;

  int x1, x2, y1, y2;
  // Render Region
  x1 = water->x << sss;
  y1 = water->y << sss;
  x2 = x1 + (1 << sss);
  y2 = y1 + (1 << sss);
  // Clamp Region
  if (--x1 < 0) x1 = 0;
  if (--y1 < 0) y1 = 0;
  if (++x2 >= w) x2 = w - 1;
  if (++y2 >= h) y2 = h - 1;

  int stride;
  short *src, *dst;
  short *dst_x, *dst_y;
  // Source Water Pixels
  src = render->canvas->buffer1;
  dst = src + ((w * h) << 2);
  // Destination Pixel Pointer
  dst_y = dst + ((y1 * w + x1) << 2);
  // Destination Stride
  stride = w << 2;

  // Expand Each Pixel
  for (int y = y1; y <= y2; y++) {
    dst_x = dst_y;

    for (int x = x1; x <= x2; x++) {
      // Convolve Current Pixel
      pixel = brush_water_convolve(src, w, h, x, y);
      // Get Pixel Current Alpha
      xmm0 = _mm_shuffle_epi32(pixel, 0xFF);
      // Apply Color Alpha to Pixel
      pixel = _mm_mullo_epi32(pixel, alpha);
      pixel = _mm_div_32767(pixel);
      // Blend With Current Color
      xmm0 = _mm_mullo_epi32(xmm0, color);
      xmm0 = _mm_div_32767(xmm0);
      xmm0 = _mm_sub_epi32(color, xmm0);
      pixel = _mm_add_epi32(pixel, xmm0);
      // Store Convolved Pixel
      pixel = _mm_packs_epi32(pixel, pixel);
      _mm_storel_epi64((__m128i*) dst_x, pixel);
      // Next Pixel
      dst_x += 4;
    }

    // Next Stride
    dst_y += stride;
  }

  // Return Pointer
  return dst;
}

// ------------------------------
// BRUSH AVERAGED FIXLINEAR BLEND
// ------------------------------

static __m128i brush_water_pixel(short* buffer, int stride, int u, int v) {
  int x, y;
  // Pixel Position
  x = u >> 15;
  y = v >> 15;
  // Buffer Position
  x = (y * stride + x) << 2;
  y = x + (stride << 2);

  __m128i fx, fy;
  // Remainder
  fx = _mm_set1_epi32(u & 0x7FFF);
  fy = _mm_set1_epi32(v & 0x7FFF);
  __m128i xmm0, m00, m10, m01, m11;
  // Load Top Two Pixels
  xmm0 = _mm_loadu_si128(
    (__m128i*) (buffer + x));
  // Unpack Top Two Pixels
  m00 = _mm_cvtepi16_epi32(xmm0);
  xmm0 = _mm_srli_si128(xmm0, 8);
  m10 = _mm_cvtepi16_epi32(xmm0);
  // Load Top Two Pixels
  xmm0 = _mm_loadu_si128(
    (__m128i*) (buffer + y));
  // Unpack Top Two Pixels
  m01 = _mm_cvtepi16_epi32(xmm0);
  xmm0 = _mm_srli_si128(xmm0, 8);
  m11 = _mm_cvtepi16_epi32(xmm0);

  __m128i result;
  result = _mm_setzero_si128();
  // Interpolate Horizontally
  m00 = _mm_mix_32767(m00, m10, fx);
  m11 = _mm_mix_32767(m01, m11, fx);
  // Interpolate Vertically
  result = _mm_mix_32767(m00, m11, fy);

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
  blur = brush_water_expand(render);
  // Load Watercolor Scale
  size = 1 << water->s;
  // Load Watercolor Stride
  stride = water->stride;
  // Load Watercolor Interpolation Steps
  fx = water->fx; xx = water->x * size * fx;
  fy = water->fy; yy = water->y * size * fy;

  short *sh_y, *sh_x, sh;
  // Load Mask Buffer Pointer
  sh_y = render->canvas->buffer0;
  // Locate Shape Pointer to Render Position
  sh_y += (render->y * s_shape) + render->x;

  __m128i color, alpha, xmm0, xmm1;
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
        xmm0 = _mm_cvtepi16_epi32(xmm0);
        // Load Color From Blur Buffer
        color = brush_water_pixel(
          blur, stride, row_xx, yy);
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
