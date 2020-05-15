#include <xmmintrin.h>

// TODO: Reduce to Short
// Software Triangle Rasterizer for Canvas

// BOX: AABB[minX, minY, maxX, maxY]
void triangle_aabb_naive(int* aabb, int* v) {
  // Set Initial AABB to First Vertex
  aabb[0] = aabb[2] = v[0];
  aabb[1] = aabb[3] = v[1];
  for (int i = 2; i < 6; i += 2) {
    // Check Minimun X and Y
    if (v[i] < aabb[0]) 
      aabb[0] = v[i];
    if (v[i + 1] < aabb[1]) 
      aabb[1] = v[i + 1];
    // Check Maximun X and Y
    if (v[i] > aabb[2]) 
      aabb[2] = v[i];
    if (v[i + 1] > aabb[3]) 
      aabb[3] = v[i + 1];
  }
}

// TODO: Can be SSE2, Block-Based
// VEC2: BLOCK[A, B, C, D] & VERTEX[A, B, C]
void triangle_draw_naive(unsigned int* pixels, int w, int h, int* v) {
  int aabb[4];
  int i1, i2, i3; // m128i
  int j1, j2, j3; // m128i
  // Iterators Variables
  int y1, y2, y3; // m128i
  int x1, x2, x3; // m128i
  // Calculate AABB and Clip
  triangle_aabb_naive(aabb, v);
  // Calculate i's and j's
  i1 = v[1] - v[3]; i2 = v[3] - v[5]; i3 = v[5] - v[1];
  j1 = v[2] - v[0]; j2 = v[4] - v[2]; j3 = v[0] - v[4];
  // Starting Position at minX, minY from AABB
  y1 = i1 * aabb[0] + j1 * aabb[1] + (v[0] * v[3] - v[1] * v[2]); //AB
  y2 = i2 * aabb[0] + j2 * aabb[1] + (v[2] * v[5] - v[3] * v[4]); //BC
  y3 = i3 * aabb[0] + j3 * aabb[1] + (v[4] * v[1] - v[5] * v[0]); //CD
  // Iterate AABB Region
  for (int j = aabb[1]; j < aabb[3]; j++) {
    x1 = y1; x2 = y2; x3 = y3;
    for (int i = aabb[0]; i < aabb[2]; i++) {
      if (x1 > 0 && x2 > 0 && x3 > 0)
        pixels[j * w + i] = 0xFF0000FF;
      x1 += i1; x2 += i2; x3 += i3;
    }
    y1 += j1; y2 += j2; y3 += j3;
  }
}

void triangle_aabb(float* aabb, float* v) {
  // Set Initial AABB to First Vertex
  aabb[0] = aabb[2] = v[0];
  aabb[1] = aabb[3] = v[1];
  for (int i = 2; i < 6; i += 2) {
    // Check Minimun X and Y
    if (v[i] < aabb[0]) 
      aabb[0] = v[i];
    if (v[i + 1] < aabb[1]) 
      aabb[1] = v[i + 1];
    // Check Maximun X and Y
    if (v[i] > aabb[2]) 
      aabb[2] = v[i];
    if (v[i + 1] > aabb[3]) 
      aabb[3] = v[i + 1];
  }
}

// Semi-SSE, Unnormalized Coordinates
void triangle_draw(unsigned int* pixels, int w, int h, float* v) {
  float aabb[4]; triangle_aabb(aabb, v); // Calculate AABB
  __m128 i, j, x, y; // Edge Equations, 3 elements
  i = _mm_set_ps(0, v[5] - v[1], v[3] - v[5], v[1] - v[3]);
  j = _mm_set_ps(0, v[0] - v[4], v[4] - v[2], v[2] - v[0]);
  // Initial at minX, minY
  y = _mm_add_ps(
    _mm_add_ps(
      _mm_mul_ps(i, _mm_set1_ps(aabb[0])), 
      _mm_mul_ps(j, _mm_set1_ps(aabb[1]))
    ), _mm_set_ps(0,
      v[4] * v[1] - v[5] * v[0],
      v[2] * v[5] - v[3] * v[4],
      v[0] * v[3] - v[1] * v[2]
    ));
  // Iterate AABB Region
  for (int py = aabb[1]; py < aabb[3]; py++) {
    x = y; // Iterate X Row
    for (int px = aabb[0]; px < aabb[2]; px++) {
      if (_mm_movemask_ps(_mm_cmpgt_ps(x, _mm_setzero_ps())) == 0x7)
        pixels[py * w + px] = 0xFF0000FF;
      x = _mm_add_ps(x, i);
    }
    y = _mm_add_ps(y, j);
  }
}