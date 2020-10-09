// 2D Triangle CPU Rasterizer
#include <inttypes.h>
#include <smmintrin.h>

typedef struct {
  float x, y;
} point_t;

typedef struct {
  // Vertexes
  point_t p[3];
  // Attributes
  float u[3];
  float v[3];
} triangle_t;

// ------------------------------
// TRIANGLE EDGE EQUATION HELPERS
// ------------------------------

void _mm_edge_4(__m128* xmm_w, __m128* xmm_a, __m128* xmm_b, point_t a, point_t b, int xmin, int ymin) {
  float w0, a0, b0, c0;
  // Incrementals
  a0 = a.y - b.y;
  b0 = b.x - a.x;
  // Part of Triangle Area
  c0 = (a.x * b.y) - (b.x * a.y);
  // Calculate Position at xmin, ymin
  w0 = xmin * a0 + ymin * b0 + c0;

  // Define 4 Edge Equation Initial Values
  *xmm_w = _mm_set_ps(w0 + a0 * 3, w0 + a0 * 2, w0 + a0, w0);
  // Define a*x and b*x Incrementals
  *xmm_a = _mm_set1_ps(a0 * 4);
  *xmm_b = _mm_set1_ps(b0);
}

void _mm_gradient_4(__m128* xmm_z0, __m128* xmm_az, __m128* xmm_bz, point_t v[3], float z[3], int xmin, int ymin) {
  float a0, a1, a2;
  float b0, b1, b2;
  float c0, c1, c2;
  // Define a*x delta
  a0 = v[1].y - v[2].y;
  a1 = v[2].y - v[0].y;
  a2 = v[0].y - v[1].y;
  // Define b*y delta
  b0 = v[2].x - v[1].x;
  b1 = v[0].x - v[2].x;
  b2 = v[1].x - v[0].x;
  // Define c for Triangle Area
  c0 = (v[1].x * v[2].y) - (v[2].x * v[1].y); 
  c1 = (v[2].x * v[0].y) - (v[0].x * v[2].y); 
  c2 = (v[0].x * v[1].y) - (v[1].x * v[0].y);

  // Define Reciprocal Triangle Area
  float area = 1 / (c0 + c1 + c2);
  // Define Parameters Interpolation
  a0 = (a0 * z[0] + a1 * z[1] + a2 * z[2]) * area;
  b0 = (b0 * z[0] + b1 * z[1] + b2 * z[2]) * area;
  c0 = (c0 * z[0] + c1 * z[1] + c2 * z[2]) * area;

  // Define 4 Barycentric Equations
  float z0 = xmin * a0 + ymin * b0 + c0;
  *xmm_z0 = _mm_set_ps(z0 + a0 * 3, z0 + a0 * 2, z0 + a0, z0);
  // Define a*x and b*x incrementals
  *xmm_az = _mm_set1_ps(a0);
  *xmm_bz = _mm_set1_ps(b0);
}

__m128 _mm_tie_4(__m128 xmm_a, __m128 xmm_b) {
  __m128 xmm_zero, xmm_a0, xmm_b0;
  xmm_zero = _mm_setzero_ps();
  // Check A > 0 and B > 0
  xmm_a0 = _mm_cmpgt_ps(xmm_a, xmm_zero);
  xmm_b0 = _mm_cmpgt_ps(xmm_b, xmm_zero);
  // Calculate Tie Breaker Mask
  return _mm_blendv_ps(xmm_a0, xmm_b0,
    _mm_cmpeq_ps(xmm_a, xmm_zero));
}

// -------------------------------
// BILINEAR 2D TRIANGLE RASTERIZER
// -------------------------------

void rasterize(uint32_t* pixels, uint8_t* mask, int stride, triangle_t* v, int xmin, int ymin, int xmax, int ymax) {
  stride -= (xmax - xmin);
  // Four-Positions Edge Equations
  __m128 xmm_w0, xmm_w1, xmm_w2;
  __m128 xmm_row0, xmm_row1, xmm_row2;
  // Edge Equation Incrementals
  __m128 xmm_a0, xmm_a1, xmm_a2;
  __m128 xmm_b0, xmm_b1, xmm_b2;
  // Triangle Parameter Equations
  __m128 xmm_u, xmm_u0, xmm_ua, xmm_ub;
  __m128 xmm_v, xmm_v0, xmm_va, xmm_vb;

  // Edge Equation Positions
  __m128 xmm_x, xmm_y;
  // Edge Equation Loop
  __m128 xmm_aux, xmm_tie, xmm_test;
  // Pixel Shader Strides
  __m128i xmm_src, xmm_dest, xmm_cast;

  // Prepare Edge Equations by four positions
  _mm_edge_4(&xmm_row0, &xmm_a0, &xmm_b0, v->p[1], v->p[2], xmin, ymin);
  _mm_edge_4(&xmm_row1, &xmm_a1, &xmm_b1, v->p[2], v->p[0], xmin, ymin);
  _mm_edge_4(&xmm_row2, &xmm_a2, &xmm_b2, v->p[0], v->p[1], xmin, ymin);
  // Prepare Parameters Interpolation by four positions
  _mm_gradient_4(&xmm_u0, &xmm_ua, &xmm_ub, v->p, v->u, xmin, ymin);

  // Prepare Tie Breaker of AC Edge
  xmm_tie = _mm_tie_4(xmm_a1, xmm_b1);
  // Rasterize By 4 Pixels per iteration
  for (int y = ymin; y < ymax; y++) {
    // Set Equations to Row
    xmm_w0 = xmm_row0;
    xmm_w1 = xmm_row1;
    xmm_w2 = xmm_row2;

    // Set Stride to Row
    for (int x = xmin; x < xmax; x += 4) {
      xmm_aux = _mm_setzero_ps();
      // Test Edge Equations Sign
      xmm_test = _mm_setzero_ps();
      xmm_test = _mm_or_ps(xmm_test,
        _mm_cmpge_ps(xmm_w0, xmm_aux));
      xmm_test = _mm_and_ps(xmm_test,
        _mm_cmpge_ps(xmm_w1, xmm_aux));
      xmm_test = _mm_and_ps(xmm_test,
        _mm_cmpge_ps(xmm_w2, xmm_aux));

      // Perform Rasterization If Passed
      if (_mm_movemask_ps(xmm_test) > 0) {
        // Test Tie Breaker Mask of AC Edge
        xmm_aux = _mm_cmpneq_ps(xmm_w1, xmm_aux);
        xmm_aux = _mm_or_ps(xmm_aux, xmm_tie);
        xmm_test = _mm_and_ps(xmm_test, xmm_aux);

        // Convert Current Position
        xmm_x = _mm_set1_ps((float) x);
        xmm_y = _mm_set1_ps((float) y);
        // Calculate U Interpolation
        xmm_aux = _mm_mul_ps(xmm_ua, xmm_x);
        xmm_u = _mm_add_ps(xmm_u0, xmm_aux);
        xmm_aux = _mm_mul_ps(xmm_ub, xmm_y);
        xmm_u = _mm_add_ps(xmm_u, xmm_aux);

        // Load Pixels And Do Pixel Shader
        xmm_src = _mm_loadu_si128((__m128i*) pixels);
        xmm_u = _mm_mul_ps(xmm_u, _mm_set1_ps(255.0));
        xmm_dest = _mm_cvtps_epi32(xmm_u);
        xmm_dest = _mm_slli_epi32(xmm_dest, 24);
        //xmm_dest = _mm_adds_epu8(xmm_src, _mm_set1_epi32(0xFF002B2B));
        // Store Pixels Blending With Mask
        xmm_cast = _mm_castps_si128(xmm_test);
        xmm_dest = _mm_blendv_epi8(xmm_src, xmm_dest, xmm_cast);
        _mm_storeu_si128((__m128i*) pixels, xmm_dest);
      }

      // Increment to Next X
      xmm_w0 = _mm_add_ps(xmm_w0, xmm_a0);
      xmm_w1 = _mm_add_ps(xmm_w1, xmm_a1);
      xmm_w2 = _mm_add_ps(xmm_w2, xmm_a2);
      // Next Pixels
      pixels += 4;
    }

    // Increment to Next Y
    xmm_row0 = _mm_add_ps(xmm_row0, xmm_b0);
    xmm_row1 = _mm_add_ps(xmm_row1, xmm_b1);
    xmm_row2 = _mm_add_ps(xmm_row2, xmm_b2);
    // Next Stride
    pixels += stride;
  }
}
