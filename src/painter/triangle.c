// 2D Triangle CPU Rasterizer
#include <inttypes.h>
#include <smmintrin.h>

typedef struct {
  float x, y;
  float u, v;
} point_t;

typedef struct {
  point_t a, b, c;
} triangle_t;

void _mm_edge_4(__m128* xmm_w, __m128* xmm_a, __m128* xmm_b, float w, float a, float b) {
  // Prepare 4 Edge Equation Initial Values
  *xmm_w = _mm_set_ps(w + a * 3, w + a * 2, w + a, w);
  // Prepare a*x and b*x Incrementals
  *xmm_a = _mm_set1_ps(a * 4);
  *xmm_b = _mm_set1_ps(b);
}

void rasterize(uint32_t* pixels, uint8_t* mask, int stride, triangle_t* s, int xmin, int ymin, int xmax, int ymax) {
  // Edge Auxiliars
  float w, a, b, c;
  // Edge Equations x4
  __m128 xmm_w0, xmm_w1, xmm_w2;
  __m128 xmm_row0, xmm_row1, xmm_row2;
  // Edge Incrementals x4
  __m128 xmm_a0, xmm_a1, xmm_a2;
  __m128 xmm_b0, xmm_b1, xmm_b2;
  // Edge Equation Test
  __m128 xmm_zero, xmm_test;
  // Test Mask to SSE2 Integer
  __m128i xmm_src, xmm_dest, xmm_cast;

  // Edge Equation BC
  a = s->b.y - s->c.y;
  b = s->c.x - s->b.x;
  c = (s->b.x * s->c.y) - (s->c.x * s->b.y);
  // Calculate Position at xmin, ymin
  w = xmin * a + ymin * b + c;
  // Prepare 4 SSE Edge Equations
  _mm_edge_4(&xmm_row0, &xmm_a0, &xmm_b0, w, a, b);

  // Edge Equation CA
  a = s->c.y - s->a.y;
  b = s->a.x - s->c.x;
  c = (s->c.x * s->a.y) - (s->a.x * s->c.y);
  // Calculate Position at xmin, ymin
  w = xmin * a + ymin * b + c;
  // Prepare 4 SSE Edge Equations
  _mm_edge_4(&xmm_row1, &xmm_a1, &xmm_b1, w, a, b);

  // Edge Equation AB
  a = s->a.y - s->b.y;
  b = s->b.x - s->a.x;
  c = (s->a.x * s->b.y) - (s->b.x * s->a.y);
  // Calculate Position at xmin, ymin
  w = xmin * a + ymin * b + c;
  // Prepare 4 SSE Edge Equations
  _mm_edge_4(&xmm_row2, &xmm_a2, &xmm_b2, w, a, b);

  // Prepare Pixel Strides
  pixels += ymin * stride + xmin;
  // Rasterize By 4 Pixels per iteration
  for (int y = ymin; y < ymax; y ++) {
    // Set Equations to Row
    xmm_w0 = xmm_row0;
    xmm_w1 = xmm_row1;
    xmm_w2 = xmm_row2;
    // Set Stride to Row
    for (int x = xmin; x < xmax; x += 4) {
      xmm_zero = _mm_setzero_ps();
      // Test Edge Equations Sign
      xmm_test = _mm_setzero_ps();
      xmm_test = _mm_or_ps(xmm_test,
        _mm_cmpge_ps(xmm_w0, xmm_zero));
      xmm_test = _mm_and_ps(xmm_test,
        _mm_cmpge_ps(xmm_w1, xmm_zero));
      xmm_test = _mm_and_ps(xmm_test,
        _mm_cmpge_ps(xmm_w2, xmm_zero));
      // Perform Rasterization If Passed
      if (_mm_movemask_ps(xmm_test) > 0) {
        xmm_src = _mm_loadu_si128((__m128i*) pixels);
        // -- Start Pixel Shader Here
        xmm_dest = _mm_adds_epu8(xmm_src, _mm_set1_epi32(0xFF002B2B));
        // -- Stop Pixel Shader Here
        // Store Pixels Tested Mask
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
    //pixels += stride;
  }
}
