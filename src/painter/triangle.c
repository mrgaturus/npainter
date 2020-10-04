// 2D Triangle CPU Rasterizer
#include <inttypes.h>
//#include <immintrin.h>

typedef struct {
  float x, y;
  float u, v;
} point_t;

typedef struct {
  point_t a, b, c;
} triangle_t;

// NAIVE IMPLEMENTATION
float linear(float a, float b, float t) {
  return a + (b - a) * t;
}

float bilinear(uint8_t* mask, float u, float v) {
  float x1, x2, y1, y2;
  // Locate on mask
  u *= 127; v *= 127;
  // Mask Neighbords Locations
  x1 = floor(u - 0.5) + 0.5;
  y1 = floor(v - 0.5) + 0.5;
  x2 = x1 + 1;
  y2 = y1 + 1;
  // Interpolators
  u = u - x1;
  v = v - y1;
  // Lookup Masks
  float m00 = (float) mask[(int) (y1) * 128 + (int) (x1)];
  float m10 = (float) mask[(int) (y1) * 128 + (int) (x2)];
  float m01 = (float) mask[(int) (y2) * 128 + (int) (x1)];
  float m11 = (float) mask[(int) (y2) * 128 + (int) (x2)];
  // Perform Interpolation
  float a = m00 * (1 - u) + m10 * u;
  float b = m01 * (1 - u) + m11 * u; 
  return a * (1 - v) + b * v;
}

float smoothstep(float x, float a, float b) {
  float t = (x - a) / (b - a);
  if (t > 1.0) t = 1.0;
  if (t < 0.0) t = 0.0;
  return t * t * (3.0 - 2.0 * t);
}

float orient2D(point_t a, point_t b, point_t c) {
  return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
}

void rasterize(uint32_t* pixels, uint8_t* mask, int w, int h, triangle_t* s, int xmin, int xmax, int ymin, int ymax) {
  float w0, w1, w2;
  float w0_row, w1_row, w2_row;
  // Area Barycentrics
  float area, wa0, wa1, wa2;
  // Prepare Incremental Walkers
  float a01 = s->a.y - s->b.y, b01 = s->b.x - s->a.x;
  float a12 = s->b.y - s->c.y, b12 = s->c.x - s->b.x;
  float a20 = s->c.y - s->a.y, b20 = s->a.x - s->c.x;
  // Barycentric at Corner
  point_t p = { xmin, ymin };
  w0_row = orient2D(s->b, s->c, p);
  w1_row = orient2D(s->c, s->a, p);
  w2_row = orient2D(s->a, s->b, p);

  area = 1 / orient2D(s->a, s->b, s->c);
  for (int y = ymin; y <= ymax; y++) {
    // Start Row
    w0 = w0_row;
    w1 = w1_row;
    w2 = w2_row;

    for (int x = xmin; x <= xmax; x++) {
      // Check if is inside all edges
      if (w0 >= 0 && w1 >= 0 && w2 >= 0) {
        // Calculate UV using triangle area
        wa0 = w0 * area; wa1 = w1 * area; wa2 = w2 * area;
        float u = wa0 * s->a.u + wa1 * s->b.u + wa2 * s->c.u;
        float v = wa0 * s->a.v + wa1 * s->b.v + wa2 * s->c.v;
        // Put Interpolated Pixel
        float alpha = bilinear(mask, u, v) / 255;
        alpha = smoothstep(alpha, 0.5, 0.5 + 0.003);
        uint32_t c = (uint32_t)(alpha * 255);
        pixels[y * h + x] = c << 24;
      }

      // Step Right
      w0 += a12;
      w1 += a20;
      w2 += a01;
    }

    // Step Row
    w0_row += b12;
    w1_row += b20;
    w2_row += b01;
  }
}
