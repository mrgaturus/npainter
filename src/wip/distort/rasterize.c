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

  // Set Incremental Starting Position with Tie Bias
  row0 = a0 * xmin + b0 * ymin + (eq->c0 + eq->tie0);
  row1 = a1 * xmin + b1 * ymin + (eq->c1 + eq->tie1);
  row2 = a2 * xmin + b2 * ymin + (eq->c2 + eq->tie2);

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

  // Load and Cast Sample Function Pointer
  sample_fn = (sample_fn_t) render->sample_fn;

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
        pixel = sample_fn(render, u, v);
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
  // Subpixel Interpolation
  __m128 xmm0, xmm1;
  __m128 pix_bot, pix_top;
  // Blend Pixel
  __m128i pixel;

  // Destination Pixels
  int16_t *dst, *mask;
  // Stride Step
  int stride;
  // Subpixel Mask
  subpixel_t* sub;

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
  // Set Destination Pixel Pointers
  dst = render->dst + stride;
  mask = render->mask + stride;
  // Get Destination Pointer Stride
  stride = ( render->dst_w - render->w ) << 2;

  // Perform Triangle Rasterization
  for (int y = ymin; y < ymax; y++) {
    // Reset X Incremental
    u0 = u_row; v0 = v_row;
    for (int x = xmin; x < xmax; x++) {
      // Put and Free Subpixel Mask
      if (sub = *(subpixel_t**) mask) {
        xmm1 = sub->color;
        // Convert and Blend Pixel
        pixel = _mm_cvtps_epi32(xmm1);
        sample_blend_store(pixel, dst);

        // Free Subpixel
        free(sub);
        // Remove Subpixel Mask
        *(subpixel_t**) mask = 0;
      }

      pix_bot = eq_full_average(eq, &dde->bot, render, u0, v0);
      pix_top = eq_full_average(eq, &dde->top, render, u0, v0);
      // Interpolate Both Subpixels
      xmm1 = _mm_sub_ps(pix_top, pix_bot);
      xmm1 = _mm_mul_ps(xmm1, xmm0);
      xmm1 = _mm_add_ps(xmm1, pix_bot);
      // Convert and Blend Pixel
      pixel = _mm_cvtps_epi32(xmm1);
      sample_blend_store(pixel, dst);

      // Step X Incremental
      u0 += u_a; v0 += v_a; 
      // Step X Pixel Pointers
      dst += 4; mask += 4;
    }
    // Step Y Incremental
    u_row += u_b; v_row += v_b; 
    // Step Y Pixel Pointers
    dst += stride; mask += stride;
  }
}

// ---------------------------------------
// PARTIAL SUBPIXEL TRIANGLE RASTERIZATION
// ---------------------------------------

static int eq_partial_count(derivative_t* dde, __m128i* mask, long long r0, long long r1, long long r2) {
  // Equation Derivatives
  long long a0, a1, a2;
  long long b0, b1, b2;
  // Horizontal Steps
  __m128i xmm_w0, xmm_w1, xmm_w2;
  __m128i xmm_row0, xmm_row1, xmm_row2;
  // Equation Parameters Steps
  __m128i xmm_a0, xmm_a1, xmm_a2;
  __m128i xmm_b0, xmm_b1, xmm_b2;
  // Subpixel Coverage
  __m128i xmm0, xmm1;
  // Subpixels Edge Test
  int check, count, bits;
  // Subpixel 128bit Mask
  __m128i bits0, bits1;

  // Load Partial Derivatives && Step Offset
  a0 = dde->a0; a1 = dde->a1; a2 = dde->a2;
  b0 = dde->b0; b1 = dde->b1; b2 = dde->b2;

  // Ajust to Center of Pixel
  r0 += (a0 >> 1) + (b0 >> 1);
  r1 += (a1 >> 1) + (b1 >> 1);
  r2 += (a2 >> 1) + (b2 >> 1);

  // Load Four Checkboard Four Edge Equation
  xmm_row0 = _mm_set_epi64x(r0 + a0 + b0, r0);
  xmm_row1 = _mm_set_epi64x(r1 + a1 + b1, r1);
  xmm_row2 = _mm_set_epi64x(r2 + a2 + b2, r2);
  // Load Four Edge Equation Steps
  xmm_a0 = _mm_set1_epi64x(a0 << 1);
  xmm_a1 = _mm_set1_epi64x(a1 << 1);
  xmm_a2 = _mm_set1_epi64x(a2 << 1);

  xmm_b0 = _mm_set1_epi64x(b0 << 1);
  xmm_b1 = _mm_set1_epi64x(b1 << 1);
  xmm_b2 = _mm_set1_epi64x(b2 << 1);

  // Intialize Bit Mask
  bits0 = _mm_setzero_si128();
  // Initialize Count
  count = 0;

  // Calculate Coverage
  for (int y = 0; y < 8; y++) {
    // Reset Horizontal
    xmm_w0 = xmm_row0;
    xmm_w1 = xmm_row1;
    xmm_w2 = xmm_row2;
    // Reset Bits
    bits = 0;

    for (int x = 0; x < 8; x++) {
      xmm0 = _mm_setzero_si128();

      xmm1 = _mm_or_si128(xmm_w0, xmm_w1);
      xmm1 = _mm_or_si128(xmm1, xmm_w2);
      xmm1 = _mm_srli_epi64(xmm1, 63);
      // Check if is Inside of Triangle
      xmm1 = _mm_cmpeq_epi64(xmm1, xmm0);

      // Get Edge Equation Test Mask
      check = _mm_movemask_epi8(xmm1);

      // Count How Many Are Inside
      count += (check >> 0) & 0x1;
      count += (check >> 8) & 0x1;

      // Move Bits 2 Spaces
      bits = (bits << 2);
      // Set Bits on Auxiliar Mask
      bits |= (check >> 0) & 0x1;
      bits |= (check >> 8) & 0x2;

      // Step Horizontal
      xmm_w0 = _mm_add_epi64(xmm_w0, xmm_a0);
      xmm_w1 = _mm_add_epi64(xmm_w1, xmm_a1);
      xmm_w2 = _mm_add_epi64(xmm_w2, xmm_a2);
    }

    // Set mask bits on 128 bits
    bits1 = _mm_cvtsi32_si128(bits);
    bits0 = _mm_slli_si128(bits0, 2);
    bits0 = _mm_or_si128(bits0, bits1);

    // Step Vertical Incrementals
    xmm_row0 = _mm_add_epi64(xmm_row0, xmm_b0);
    xmm_row1 = _mm_add_epi64(xmm_row1, xmm_b1);
    xmm_row2 = _mm_add_epi64(xmm_row2, xmm_b2);
  }

  // Return Coverage Mask
  _mm_store_si128(mask, bits0);

  // Return Count
  return count;
}

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

  __m128 xmm_div;
  // Subpixel Interpolation
  __m128 xmm0, xmm1, xmm2;
  __m128 pix_bot, pix_top;
  // Pixel Blending
  __m128i pix0;
  // Coverage Count & Mask
  __m128i mask0, mask1;
  // Subpixel Mask
  subpixel_t* sub;

  // Destination Pixel
  int16_t *dst, *mask;
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

  // Set Incremental Starting Position with Tie Bias
  row0 = a0 * xmin + b0 * ymin + (eq->c0 - eq->tie0);
  row1 = a1 * xmin + b1 * ymin + (eq->c1 - eq->tie1);
  row2 = a2 * xmin + b2 * ymin + (eq->c2 - eq->tie2);

  // Load UV Equation Coeffients
  u_a = eq->u_a; u_b = eq->u_b; u_c = eq->u_c;
  v_a = eq->v_a; v_b = eq->v_b; v_c = eq->v_c;
  
  // Load Subpixel Area Divisor
  xmm_div = _mm_set1_ps(128.0);
  xmm_div = _mm_rcp_ps(xmm_div);
  // Load Subpixel Interpolator
  xmm0 = _mm_set1_ps(dde->fract);

  // Get Destination Pixel Stride Position
  stride = (ymin * render->dst_w + xmin) << 2;
  // Set Destination Pixel Pointers
  dst = render->dst + stride;
  mask = render->mask + stride;
  // Get Destination Pointer Stride
  stride = ( render->dst_w - render->w ) << 2;

  // Perform Triangle Rasterization
  for (int y = ymin; y < ymax; y++) {
    // Reset Equation X Position
    w0 = row0; w1 = row1, w2 = row2;
    for (int x = xmin; x < xmax; x++) {
      // Count Subpixels Inside A 16x16 checkboard area
      count = eq_partial_count(dde, &mask0, w0, w1, w2);
      // Not Zero Pixel
      if (count > 0) {
        // Calculate Barycentric UV
        u = x * u_a + y * u_b + u_c;
        v = x * v_a + y * v_b + v_c;

        // Calculate Bot-Top Subpixel
        pix_bot = eq_full_average(eq, &dde->bot, render, u, v);
        pix_top = eq_full_average(eq, &dde->top, render, u, v);
        // Interpolate Both Subpixels
        xmm1 = _mm_sub_ps(pix_top, pix_bot);
        xmm1 = _mm_mul_ps(xmm1, xmm0);
        xmm1 = _mm_add_ps(xmm1, pix_bot);

        // Move Count to a XMM register
        mask1 = _mm_cvtsi32_si128(count);
        mask1 = _mm_shuffle_epi32(mask1, 0);
        // Convert Count to Float
        xmm2 = _mm_cvtepi32_ps(mask1);
        xmm2 = _mm_mul_ps(xmm2, xmm_div);

        // Apply Antialiasing Coverage
        xmm1 = _mm_mul_ps(xmm1, xmm2);

        // Load Subpixel Pointer
        if (sub = *(subpixel_t**) mask) {
          mask1 = sub->mask;
          // Check if there is not an overlap
          if (_mm_testz_si128(mask0, mask1) == 1) {
            // Combine Both Masks and Pixels
            mask0 = _mm_or_si128(mask0, mask1);
            xmm1 = _mm_add_ps(xmm1, sub->color);
          } else {
            // Put Merged Pixel
            xmm2 = sub->color;
            // Convert Pixel and Blend
            pix0 = _mm_cvtps_epi32(xmm2);
            sample_blend_store(pix0, dst);
          }

          // Check if needs to be freed
          mask1 = _mm_cmpeq_epi32(mask1, mask1);
          if (_mm_testc_si128(mask0, mask1) == 0) {
            // Replace Values
            sub->color = xmm1;
            sub->mask = mask0;
          } else {
            // Convert Current and Blend
            pix0 = _mm_cvtps_epi32(xmm1);
            sample_blend_store(pix0, dst);

            // Free Subpixel
            free(sub);
            // Remove Subpixel Mask
            *(subpixel_t**) mask = 0;
          }
        } else if (count < 128) {
          // Allocates New Temporal Mask
          sub = malloc( sizeof(subpixel_t) );
          // Initialize Mask
          sub->color = xmm1;
          sub->mask = mask0;
          // Replace Subpixel Pointer
          *(subpixel_t**) mask = sub;
        } else {
          // Convert Pixel and Blend
          pix0 = _mm_cvtps_epi32(xmm1);
          sample_blend_store(pix0, dst);
        }
      }

      // Step Equation X Position and Pixels
      w0 += a0; w1 += a1; w2 += a2;
      // Step Destination Pointers
      dst += 4; mask += 4;
    }
    // Step Equation Y Position and Pixels
    row0 += b0; row1 += b1; row2 += b2;
    // Step Destination Pointers
    dst += stride; mask += stride;
  }
}

// ------------------------------
// ANTIALIASING SUBPIXEL BLENDING
// ------------------------------

void eq_apply_antialiasing(fragment_t* render) {
  int xmin, xmax, ymin, ymax;
  // Weighted Pixel
  __m128 xmm0;
  // Blended Pixel
  __m128i pix0;

  // Destination Pixel
  int16_t *dst, *mask;
  // Stride Step
  int stride;
  // Subpixel Mask
  subpixel_t* sub;

  // X Interval
  xmin = render->x;
  xmax = xmin + render->w;
  // Y Interval
  ymin = render->y;
  ymax = ymin + render->h;

  // Get Destination Pixel Stride Position
  stride = (ymin * render->dst_w + xmin) << 2;
  // Set Destination Pixel Pointers
  dst = render->dst + stride;
  mask = render->mask + stride;
  // Get Destination Pointer Stride
  stride = ( render->dst_w - render->w ) << 2;

  for (int y = ymin; y < ymax; y++) {
    // Step Each Pixel And Blend Weighted
    for (int x = xmin; x < xmax; x++) {
      // Put and Free Subpixel Mask
      if (sub = *(subpixel_t**) mask) {
        xmm0 = sub->color;
        // Convert and Blend Pixel
        pix0 = _mm_cvtps_epi32(xmm0);
        sample_blend_store(pix0, dst);
        
        // Free Subpixel
        free(sub);
        // Remove Subpixel Mask
        *(subpixel_t**) mask = 0;
      }
      // Step Destination Pointers
      dst += 4; mask += 4;
    }
    // Step Destination Pointers
    dst += stride; mask += stride;
  }
}
