#include "distort.h"

// ------------------------------------
// TRIANGLE RENDERING PARTIALLY / FULLY
// ------------------------------------

// -- Renders Triangle With Edge Equation Check
void eq_partial(equation_t* eq, fragment_t* render) {
  int xmin, xmax, ymin, ymax;
  // Edge Equation Coeffients
  long long row0, row1, row2;
  long long w0, w1, w2;
  // Incremental Steps
  long long a0, a1, a2;
  long long b0, b1, b2;
  // UV Gradient Parameters
  float u_a, u_b, u_c, u;
  float v_a, v_b, v_c, v;

  // Source Pixels
  sampler_t* sampler;
  sampler_fn_t sampler_fn;
  // Source Pixel
  __m128i pixel;

  // Destination Pixels
  int stride; int16_t* dst;

  // X Interval
  xmin = render->x;
  xmax = xmin + render->w;
  // Y Interval
  ymin = render->y;
  ymax = ymin + render->h;

  // Load Equation Incrementals
  a0 = eq->a0; a1 = eq->a1; a2 = eq->a2;
  b0 = eq->b0; b1 = eq->b1; b2 = eq->b2;

  // Set Incremental Starting Position
  row0 = a0 * xmin + b0 * ymin + eq->c0;
  row1 = a1 * xmin + b1 * ymin + eq->c1;
  row2 = a2 * xmin + b2 * ymin + eq->c2;

  // Set Centered to Pixel
  row0 += (a0 >> 1) + (b0 >> 1);
  row1 += (a1 >> 1) + (b1 >> 1);
  row2 += (a2 >> 1) + (b2 >> 1);

  // Load UV Equation Coeffients
  u_a = eq->u_a; u_b = eq->u_b; u_c = eq->u_c;
  v_a = eq->v_a; v_b = eq->v_b; v_c = eq->v_c;
  
  // Get Destination Pixel Pointer
  stride = (ymin * render->dst_w + xmin) << 2;
  dst = render->dst + stride;
  // Get Destination Pointer Stride
  stride = ( render->dst_w - render->w ) << 2;

  sampler = render->sampler;
  // Load and Cast Sample Function Pointer
  sampler_fn = (sampler_fn_t) sampler->fn;

  // Perform Triangle Rasterization
  for (int y = ymin; y < ymax; y++) {
    // Reset Equation X Position
    w0 = row0; w1 = row1, w2 = row2;
    for (int x = xmin; x < xmax; x++) {
      // Check if is inside triangle
      if ( (w0 | w1 | w2) > 0 ) {
        // Calculate Barycentric UV
        u = x * u_a + y * u_b + u_c;
        v = x * v_a + y * v_b + v_c;
        // Perform Pixel Filtering
        pixel = sampler_fn(sampler, u, v);
        sample_blend_store(pixel, dst);
      }
      // Step Equation X Position
      w0 += a0; w1 += a1; w2 += a2; 
      // Next Pixel
      dst += 4;
    }
    // Step Equation Y Position
    row0 += b0; row1 += b1; row2 += b2; 
    // Next Stride
    dst += stride;
  }
}

// -- Renders Triangle With Gradient Equation
void eq_full(equation_t* eq, fragment_t* render) {
  int xmin, xmax, ymin, ymax;
  // Gradient Coeffients
  float u_a, u_b, u_row, u;
  float v_a, v_b, v_row, v;

  // Source Pixels
  sampler_t* sampler;
  sampler_fn_t sampler_fn;
  // Source Pixel
  __m128i pixel;

  // Destination Pixels
  int stride; int16_t* dst;

  // X Interval
  xmin = render->x;
  xmax = xmin + render->w;
  // Y Interval
  ymin = render->y;
  ymax = ymin + render->h;

  // Load Gradient Coeffients
  u_a = eq->u_a; u_b = eq->u_b;
  v_a = eq->v_a; v_b = eq->v_b;
  // Set Incremental Starting Position
  u_row = xmin * u_a + ymin * u_b + eq->u_c;
  v_row = xmin * v_a + ymin * v_b + eq->v_c;

  // Get Destination Pixel Pointer
  stride = (ymin * render->dst_w + xmin) << 2;
  dst = render->dst + stride;
  // Get Destination Pointer Stride
  stride = ( render->dst_w - render->w ) << 2;

  sampler = render->sampler;
  // Load and Cast Sample Function Pointer
  sampler_fn = (sampler_fn_t) sampler->fn;

  // Perform Triangle Rasterization
  for (int y = ymin; y < ymax; y++) {
    // Reset X Incremental
    u = u_row; v = v_row;
    for (int x = xmin; x < xmax; x++) {
      // Perform Pixel Filtering
      pixel = sampler_fn(sampler, u, v);
      sample_blend_store(pixel, dst);
      // Step X Incremental and Pixels
      u += u_a; v += v_a; dst += 4;
    }
    // Step Y Incremental and Pixels
    u_row += u_b; v_row += v_b; dst += stride;
  }
}

// ----------------------------------------
// TRIANGLE RASTERIZATION WITH OVERSAMPLING
// ----------------------------------------

static __m128 eq_full_average(level_t* dde, sampler_t* sampler, float u0, float v0) {
  float u, v;
  // Derivatives Step
  float dudx, dudy;
  float dvdx, dvdy;
  // Level Area
  int level;

  // Averaged Pixel
  __m128i pixel, pix_sum;
  __m128 xmm0, xmm1;
  // Sampler Function Pointer
  sampler_fn_t sampler_fn;

  // Load Derivatives Step
  dudx = dde->dudx; dudy = dde->dudy;
  dvdx = dde->dvdx; dvdy = dde->dvdy;

  // Load and Cast Sample Function Pointer
  sampler_fn = (sampler_fn_t) sampler->fn;

  // Load Level Area
  level = dde->level;
  xmm0 = _mm_set1_ps(level * level);
  xmm0 = _mm_rcp_ps(xmm0);
  // Initialize Pixel Sumation
  pix_sum = _mm_setzero_si128();

  for (int y = 0; y < level; y++) {
    // Reset Horizontal
    u = u0; v = v0;
    for (int x = 0; x < level; x++) {
      // Perform Pixel Filtering
      pixel = sampler_fn(sampler, u, v);
      pix_sum = _mm_add_epi32(pix_sum, pixel);
      // Step Horizontal
      u += dudx; v += dvdx;
    }
    // Step Vertical
    u0 += dudy; v0 += dvdy;
  }

  // Divide By Subpixel Area
  xmm1 = _mm_cvtepi32_ps(pix_sum);
  xmm1 = _mm_mul_ps(xmm1, xmm0);

  // Return Averaged
  return xmm1;
}

// -- Renders Triangle With Edge Equation Check
void eq_partial_subpixel(equation_t* eq, derivative_t* dde, fragment_t* render) {
  int xmin, xmax, ymin, ymax;
  // Edge Equation Coeffients
  long long row0, row1, row2;
  long long w0, w1, w2;
  // Incremental Steps
  long long a0, a1, a2;
  long long b0, b1, b2;
  // UV Gradient Parameters
  float u_a, u_b, u_c, u;
  float v_a, v_b, v_c, v;

  // Source Pixels
  sampler_t* sampler;
  sampler_fn_t sampler_fn;
  // Subpixel Interpolation
  __m128 xmm0, xmm1;
  __m128 pix_bot, pix_top;
  // Blend Pixel
  __m128i pixel;

  // Destination Pixels
  int stride; int16_t* dst;

  // X Interval
  xmin = render->x;
  xmax = xmin + render->w;
  // Y Interval
  ymin = render->y;
  ymax = ymin + render->h;

  // Load Equation Incrementals
  a0 = eq->a0; a1 = eq->a1; a2 = eq->a2;
  b0 = eq->b0; b1 = eq->b1; b2 = eq->b2;

  // Set Incremental Starting Position
  row0 = a0 * xmin + b0 * ymin + eq->c0;
  row1 = a1 * xmin + b1 * ymin + eq->c1;
  row2 = a2 * xmin + b2 * ymin + eq->c2;

  // Set Centered to Pixel
  row0 += (a0 >> 1) + (b0 >> 1);
  row1 += (a1 >> 1) + (b1 >> 1);
  row2 += (a2 >> 1) + (b2 >> 1);

  // Load UV Equation Coeffients
  u_a = eq->u_a; u_b = eq->u_b; u_c = eq->u_c;
  v_a = eq->v_a; v_b = eq->v_b; v_c = eq->v_c;
  
  // Load Subpixel Interpolator
  xmm0 = _mm_set1_ps(dde->fract);

  // Get Destination Pixel Pointer
  stride = (ymin * render->dst_w + xmin) << 2;
  dst = render->dst + stride;
  // Get Destination Pointer Stride
  stride = ( render->dst_w - render->w ) << 2;

  sampler = render->sampler;
  // Load and Cast Sample Function Pointer
  sampler_fn = (sampler_fn_t) sampler->fn;


  // Perform Triangle Rasterization
  for (int y = ymin; y < ymax; y++) {
    // Reset Equation X Position
    w0 = row0; w1 = row1, w2 = row2;
    for (int x = xmin; x < xmax; x++) {
      // Check if is inside triangle
      if ( (w0 | w1 | w2) > 0 ) {
        // Calculate Barycentric UV
        u = x * u_a + y * u_b + u_c;
        v = x * v_a + y * v_b + v_c;

        pix_bot = eq_full_average(&dde->bot, sampler, u, v);
        pix_top = eq_full_average(&dde->top, sampler, u, v);
        // Interpolate Both Subpixels
        xmm1 = _mm_sub_ps(pix_top, pix_bot);
        xmm1 = _mm_mul_ps(xmm1, xmm0);
        xmm1 = _mm_add_ps(xmm1, pix_bot);
        // Convert and Blend Pixel
        pixel = _mm_cvtps_epi32(xmm1);
        sample_blend_store(pixel, dst);
      }
      // Step Equation X Position
      w0 += a0; w1 += a1; w2 += a2; 
      // Next Pixel
      dst += 4;
    }
    // Step Equation Y Position
    row0 += b0; row1 += b1; row2 += b2; 
    // Next Stride
    dst += stride;
  }
}

// -- Renders Triangle With Gradient Equation
void eq_full_subpixel(equation_t* eq, derivative_t* dde, fragment_t* render) {
  int xmin, xmax, ymin, ymax;
  // Gradient Coeffients
  float u_a, u_b, u_row, u;
  float v_a, v_b, v_row, v;

  // Source Pixels
  sampler_t* sampler;
  sampler_fn_t sampler_fn;
  // Subpixel Interpolation
  __m128 xmm0, xmm1;
  __m128 pix_bot, pix_top;
  // Blend Pixel
  __m128i pixel;

  // Destination Pixels
  int stride; int16_t* dst;

  // X Interval
  xmin = render->x;
  xmax = xmin + render->w;
  // Y Interval
  ymin = render->y;
  ymax = ymin + render->h;

  // Load Gradient Coeffients
  u_a = eq->u_a; u_b = eq->u_b;
  v_a = eq->v_a; v_b = eq->v_b;
  // Set Incremental Starting Position
  u_row = xmin * u_a + ymin * u_b + eq->u_c;
  v_row = xmin * v_a + ymin * v_b + eq->v_c;
  
  // Load Subpixel Interpolator
  xmm0 = _mm_set1_ps(dde->fract);

  // Get Destination Pixel Pointer
  stride = (ymin * render->dst_w + xmin) << 2;
  dst = render->dst + stride;
  // Get Destination Pointer Stride
  stride = ( render->dst_w - render->w ) << 2;

  sampler = render->sampler;
  // Load and Cast Sample Function Pointer
  sampler_fn = (sampler_fn_t) sampler->fn;

  // Perform Triangle Rasterization
  for (int y = ymin; y < ymax; y++) {
    // Reset X Incremental
    u = u_row; v = v_row;
    for (int x = xmin; x < xmax; x++) {
      pix_bot = eq_full_average(&dde->bot, sampler, u, v);
      pix_top = eq_full_average(&dde->top, sampler, u, v);
      // Interpolate Both Subpixels
      xmm1 = _mm_sub_ps(pix_top, pix_bot);
      xmm1 = _mm_mul_ps(xmm1, xmm0);
      xmm1 = _mm_add_ps(xmm1, pix_bot);
      // Convert and Blend Pixel
      pixel = _mm_cvtps_epi32(xmm1);
      sample_blend_store(pixel, dst);

      // Step X Incremental and Pixels
      u += u_a; v += v_a; dst += 4;
    }
    // Step Y Incremental and Pixels
    u_row += u_b; v_row += v_b; dst += stride;
  }
}
