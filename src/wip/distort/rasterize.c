#include "distort.h"

// ------------------------------------
// TRIANGLE RENDERING PARTIALLY / FULLY
// ------------------------------------

// -- Renders Triangle With Edge Equation Check
void eq_partial(equation_t* eq, fragment_t* render) {
  int xmin, xmax, ymin, ymax;
  // Edge Equation Coeffients
  float row0, row1, row2;
  float w0, w1, w2;
  // Incremental Steps
  float a0, a1, a2;
  float b0, b1, b2;
  // UV Parameters
  float u0, u1, u2, u;
  float v0, v1, v2, v;
  // Edge Tie Breaker
  int tie0, tie1, tie2;
  int check0, check1, check2;
  // Destination Pixels
  int stride; int16_t* dst;
  // Sampler Function Pointer
  sample_fn_t sample_fn;
  // Source Pixel
  __m128i pixel;

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

  // Edge Tie Breaker
  tie0 = eq->tie0;
  tie1 = eq->tie1;
  tie2 = eq->tie2;

  // Load UV Equation Coeffients
  u0 = eq->u0; u1 = eq->u1; u2 = eq->u2;
  v0 = eq->v0; v1 = eq->v1; v2 = eq->v2;
  
  // Get Destination Pixel Pointer
  stride = (ymin * render->dst_w + xmin) << 2;
  dst = render->dst + stride;
  // Get Destination Pointer Stride
  stride = ( render->dst_w - render->w ) << 2;

  // Load and Cast Sample Function Pointer
  sample_fn = (sample_fn_t) render->sample_fn;

  // Perform Triangle Rasterization
  for (int y = ymin; y < ymax; y++) {
    // Reset Equation X Position
    w0 = row0; w1 = row1, w2 = row2;
    for (int x = xmin; x < xmax; x++) {
      // Check Edge Sign and Tie Breaker
      check0 = w0 > 0.0 || (w0 == 0.0 && tie0);
      check1 = w1 > 0.0 || (w1 == 0.0 && tie1);
      check2 = w2 > 0.0 || (w2 == 0.0 && tie2);
      // Check if is inside triangle
      if (check0 && check1 && check2) {
        // Calculate Barycentric UV
        u = w0 * u0 + w1 * u1 + w2 * u2;
        v = w0 * v0 + w1 * v1 + w2 * v2;
        // Perform Pixel Filtering
        pixel = sample_fn(render, u, v);
        sample_blend_store(pixel, dst);
      }
      // Step Equation X Position and Pixels
      w0 += a0; w1 += a1; w2 += a2; dst += 4;
    }
    // Step Equation Y Position and Pixels
    row0 += b0; row1 += b1; row2 += b2; dst += stride;
  }
}

// -- Renders Triangle With Gradient Equation
void eq_full(equation_t* eq, fragment_t* render) {
  int xmin, xmax, ymin, ymax;
  // Gradient Coeffients
  float u_a, u_b, u_row, u;
  float v_a, v_b, v_row, v;
  // Destination Pixels
  int stride; int16_t* dst;
  // Sampler Function Pointer
  sample_fn_t sample_fn;
  // Source Pixel
  __m128i pixel;

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

  // Load and Cast Sample Function Pointer
  sample_fn = (sample_fn_t) render->sample_fn;

  // Perform Triangle Rasterization
  for (int y = ymin; y < ymax; y++) {
    // Reset X Incremental
    u = u_row; v = v_row;
    for (int x = xmin; x < xmax; x++) {
      // Perform Pixel Filtering
      pixel = sample_fn(render, u, v);
      sample_blend_store(pixel, dst);
      // Step X Incremental and Pixels
      u += u_a; v += v_a; dst += 4;
    }
    // Step Y Incremental and Pixels
    u_row += u_b; v_row += v_b; dst += stride;
  }
}

// ------------------------------------
// FULL SUBPIXEL TRIANGLE RASTERIZATION
// ------------------------------------

static __m128 eq_full_average(equation_t* eq, level_t* dde, fragment_t* render, float u0, float v0) {
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
  sample_fn_t sample_fn;

  // Load Derivatives Step
  dudx = dde->dudx; dudy = dde->dudy;
  dvdx = dde->dvdx; dvdy = dde->dvdy;

  // Load and Cast Sample Function Pointer
  sample_fn = (sample_fn_t) render->sample_fn;

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
      pixel = sample_fn(render, u, v);
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

void eq_full_subpixel(equation_t* eq, derivative_t* dde, fragment_t* render) {
  int xmin, xmax, ymin, ymax;
  // Gradient Coeffients
  float u_a, u_b, u_row, u0;
  float v_a, v_b, v_row, v0;
  // Destination Pixels
  int stride; int16_t* dst;
  // Subpixel Interpolation
  __m128 xmm0, xmm1;
  __m128 pix_bot, pix_top;
  // Blend Pixel
  __m128i pixel;

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

  // Load Interpolation
  xmm0 = _mm_set1_ps(dde->fract);

  // Get Destination Pixel Pointer
  stride = (ymin * render->dst_w + xmin) << 2;
  dst = render->dst + stride;
  // Get Destination Pointer Stride
  stride = ( render->dst_w - render->w ) << 2;

  // Perform Triangle Rasterization
  for (int y = ymin; y < ymax; y++) {
    // Reset X Incremental
    u0 = u_row; v0 = v_row;
    for (int x = xmin; x < xmax; x++) {
      pix_bot = eq_full_average(eq, &dde->bot, render, u0, v0);
      pix_top = eq_full_average(eq, &dde->top, render, u0, v0);
      // Interpolate Both Subpixels
      xmm1 = _mm_sub_ps(pix_top, pix_bot);
      xmm1 = _mm_mul_ps(xmm1, xmm0);
      xmm1 = _mm_add_ps(xmm1, pix_bot);
      // Convert and Blend Pixel
      pixel = _mm_cvtps_epi32(xmm1);
      sample_blend_store(pixel, dst);
      // Step X Incremental and Pixels
      u0 += u_a; v0 += v_a; dst += 4;
    }
    // Step Y Incremental and Pixels
    u_row += u_b; v_row += v_b; dst += stride;
  }
}

// ---------------------------------------
// PARTIAL SUBPIXEL TRIANGLE RASTERIZATION
// ---------------------------------------

static int eq_partial_count(derivative_t* dde, float r0, float r1, float r2) {
  // Equation Derivatives
  float dx0, dx1, dx2;
  float dy0, dy1, dy2;
  // Horizontal Steps
  __m128 xmm_w0, xmm_w1, xmm_w2;
  __m128 xmm_row0, xmm_row1, xmm_row2;
  // Equation Parameters
  __m128 xmm_dx0, xmm_dx1, xmm_dx2;
  __m128 xmm_dy0, xmm_dy1, xmm_dy2;
  // Coverage Test
  __m128 xmm0, xmm1;
  // Pixels Found
  int w_check, count;

  // Load Partial Derivatives
  dx0 = dde->dx0; dx1 = dde->dx1; dx2 = dde->dx2;
  dy0 = dde->dy0; dy1 = dde->dy1; dy2 = dde->dy2;
  // Step by Half Initial Edge Equation
  r0 += (dx0 * 0.5) + (dy0 * 0.5);
  r1 += (dx1 * 0.5) + (dy1 * 0.5);
  r2 += (dx2 * 0.5) + (dy2 * 0.5);

  // Load 2x2 Four Edge Equation
  xmm_row0 = _mm_setr_ps(r0, r0 + dx0, r0 + dy0, r0 + dx0 + dy0);
  xmm_row1 = _mm_setr_ps(r1, r1 + dx1, r1 + dy1, r1 + dx1 + dy1);
  xmm_row2 = _mm_setr_ps(r2, r2 + dx2, r2 + dy2, r2 + dx2 + dy2);
  // Load Four Edge Equation Steps
  xmm_dx0 = _mm_set1_ps(dx0 * 2.0);
  xmm_dx1 = _mm_set1_ps(dx1 * 2.0);
  xmm_dx2 = _mm_set1_ps(dx2 * 2.0);

  xmm_dy0 = _mm_set1_ps(dy0 * 2.0);
  xmm_dy1 = _mm_set1_ps(dy1 * 2.0);
  xmm_dy2 = _mm_set1_ps(dy2 * 2.0);

  // Count Found
  count = 0;

  // Calculate Coverage
  for (int y = 0; y < 16; y++) {
    // Reset Horizontal
    xmm_w0 = xmm_row0;
    xmm_w1 = xmm_row1;
    xmm_w2 = xmm_row2;

    for (int x = 0; x < 16; x++) {
      xmm0 = _mm_setzero_ps();
      xmm1 = // Check Posivity
        _mm_cmpge_ps(xmm_w0, xmm0);
      xmm1 = _mm_and_ps(xmm1,
        _mm_cmpge_ps(xmm_w1, xmm0));
      xmm1 = _mm_and_ps(xmm1,
        _mm_cmpge_ps(xmm_w2, xmm0));
      // Check if is inside triangle
      w_check = _mm_movemask_ps(xmm1);

      // Count How Many Are Inside
      count += (w_check >> 0) & 0x1;
      count += (w_check >> 1) & 0x1;
      count += (w_check >> 2) & 0x1;
      count += (w_check >> 3) & 0x1;

      // Step Horizontal
      xmm_w0 = _mm_add_ps(xmm_w0, xmm_dx0);
      xmm_w1 = _mm_add_ps(xmm_w1, xmm_dx1);
      xmm_w2 = _mm_add_ps(xmm_w2, xmm_dx2);
    }
    // Step Vertical Incrementals
    xmm_row0 = _mm_add_ps(xmm_row0, xmm_dy0);
    xmm_row1 = _mm_add_ps(xmm_row1, xmm_dy1);
    xmm_row2 = _mm_add_ps(xmm_row2, xmm_dy2);
  }

  // Return Count
  return count;
}

void eq_partial_subpixel(equation_t* eq, derivative_t* dde, fragment_t* render) {
  int xmin, xmax, ymin, ymax;
  // Edge Equation Coeffients
  float row0, row1, row2;
  float w0, w1, w2;
  // Incremental Steps
  float a0, a1, a2;
  float b0, b1, b2;
  // UV Parameters
  float u0, u1, u2, u;
  float v0, v1, v2, v;
  // Edge Tie Breaker
  int tie0, tie1, tie2;
  int check0, check1, check2;

  __m128 xmm_div;
  // Subpixel Interpolation
  __m128 xmm0, xmm1, xmm2;
  __m128 pix_bot, pix_top;
  // Pixel Blending & Mask
  __m128i pix0, pix1;
  // Coverage Count
  __m128i xmm_cnt;

  // Coverage Check Mask
  int16_t orient;
  // Coverage Slopes Mask
  int16_t ss0, ss1, ss2;
  int16_t sd0, sd1, sd2;
  // Destination Pointers
  int16_t *dst, *mask, *back;
  // Count & Stride Step
  int count, stride;

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

  // Edge Tie Breaker
  tie0 = eq->tie0;
  tie1 = eq->tie1;
  tie2 = eq->tie2;

  // Load UV Equation Coeffients
  u0 = eq->u0; u1 = eq->u1; u2 = eq->u2;
  v0 = eq->v0; v1 = eq->v1; v2 = eq->v2;
  
  // Load Subpixel Area Divisor
  xmm_div = _mm_set1_ps(32.0 * 32.0);
  xmm_div = _mm_rcp_ps(xmm_div);
  // Load Subpixel Interpolator
  xmm0 = _mm_set1_ps(dde->fract);

  // Load Winding Orient Sign
  orient = (int16_t) dde->orient;
  // Load Mask Discretized Slopes
  ss0 = dde->ss0 * orient; 
  ss1 = dde->ss1 * orient; 
  ss2 = dde->ss2 * orient;

  // Get Destination Pixel Stride Position
  stride = (ymin * render->dst_w + xmin) << 2;
  // Set Destination Pixel Pointers
  dst = render->dst + stride;
  mask = render->mask + stride;
  back = render->back + stride;
  // Get Destination Pointer Stride
  stride = ( render->dst_w - render->w ) << 2;

  // Perform Triangle Rasterization
  for (int y = ymin; y < ymax; y++) {
    // Reset Equation X Position
    w0 = row0; w1 = row1, w2 = row2;
    for (int x = xmin; x < xmax; x++) {
      // Count Subpixels Inside on 32x32 area
      count = eq_partial_count(dde, w0, w1, w2);
      // Not Zero Pixel
      if (count > 0) {
        // Check Edge Sign and Tie Breaker
        check0 = w0 > 0.0 || (w0 == 0.0 && tie0);
        check1 = w1 > 0.0 || (w1 == 0.0 && tie1);
        check2 = w2 > 0.0 || (w2 == 0.0 && tie2);
        // Check if inside of not-antialised
        check0 = check0 && check1 && check2;

        // Calculate Barycentric UV
        u = w0 * u0 + w1 * u1 + w2 * u2;
        v = w0 * v0 + w1 * v1 + w2 * v2;

        // Calculate Bot-Top Subpixel
        pix_bot = eq_full_average(eq, &dde->bot, render, u, v);
        pix_top = eq_full_average(eq, &dde->top, render, u, v);
        // Interpolate Both Subpixels
        xmm1 = _mm_sub_ps(pix_top, pix_bot);
        xmm1 = _mm_mul_ps(xmm1, xmm0);
        xmm1 = _mm_add_ps(xmm1, pix_bot);

        if (count == 1024) {
          // Load Destination Color
          pix1 = _mm_loadl_epi64(
            (__m128i*) dst);
          // Blend Pixel With Destination
          pix0 = _mm_cvtps_epi32(xmm1);
          pix0 = sample_blend_pack(pix0, pix1);
          // Clear Coverage
          check1 = 0x1;
        } else {
          // Load Destination Mask Slope
          sd0 = mask[0]; sd1 = mask[1]; sd2 = mask[2];
          // Check if there is at least one slope equality
          check2  = sd0 && (sd0 == ss0) || sd1 && (sd1 == ss0) || sd2 && (sd2 == ss0);
          check2 |= sd0 && (sd0 == ss1) || sd1 && (sd1 == ss1) || sd2 && (sd2 == ss1);
          check2 |= sd0 && (sd0 == ss2) || sd1 && (sd1 == ss2) || sd2 && (sd2 == ss2);

          if (check1 = check2) {
            // Load Backup Color
            pix1 = _mm_loadl_epi64((__m128i*) back);

            // Check Was or Is Inside
            if (check1 = mask[3]) {
              pix0 = pix1; // Just Backup
            } else if (check1 = check0) {
              // Blend Pixel With Backup
              pix0 = _mm_cvtps_epi32(xmm1);
              pix0 = sample_blend_pack(pix0, pix1);
            } else { check2 &= mask[3]; }
          }
        }
        
        if (check1) {
          // Clear Mask Coverage
          pix1 = _mm_setzero_si128();
          _mm_storel_epi64((__m128i*) mask, pix1);
        } else {
          // Replace Slopes
          mask[0] = ss0;
          mask[1] = ss1;
          mask[2] = ss2;
          // Set Edge test
          mask[3] = check0;

          // Load Destination Color
          pix1 = _mm_loadl_epi64(
            (__m128i*) dst);

          if (check0 && !check2) {
            pix0 = _mm_cvtps_epi32(xmm1);
            pix0 = sample_blend_pack(pix0, pix1);
          } else { pix0 = pix1; }

          // Store Pixel to Backup Destination Pointer
          _mm_storel_epi64((__m128i*) back, pix0);

          // Move Count to a XMM register
          xmm_cnt = _mm_cvtsi32_si128(count);
          xmm_cnt = _mm_shuffle_epi32(xmm_cnt, 0);
          // Convert Count to Float
          xmm2 = _mm_cvtepi32_ps(xmm_cnt);
          xmm2 = _mm_mul_ps(xmm2, xmm_div);

          // Apply Antialiasing Coverage
          xmm1 = _mm_mul_ps(xmm1, xmm2);
          // Convert Pixel and Blend
          pix0 = _mm_cvtps_epi32(xmm1);
          pix0 = sample_blend_pack(pix0, pix1);
        }

        // Store Final Pixel to Dst
        _mm_storel_epi64((__m128i*) dst, pix0);
      }

      // Step Equation X Position and Pixels
      w0 += a0; w1 += a1; w2 += a2;
      // Step Destination Pointers
      dst += 4; mask += 4; back += 4;
    }
    // Step Equation Y Position and Pixels
    row0 += b0; row1 += b1; row2 += b2;
    // Step Destination Pointers
    dst += stride; mask += stride; back += stride;
  }
}
