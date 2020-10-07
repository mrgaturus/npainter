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

void rasterize(uint32_t* pixels, uint8_t* mask, int w, int h, triangle_t* s, int xmin, int xmax, int ymin, int ymax) {
  float a0, a1, a2;
  float b0, b1, b2;
  float c0, c1, c2;
  // Edge Equations
  float w0, w1, w2;
  float w0_row, w1_row, w2_row;
  // Barycentric
  float area;
  // Tie Breaker
  int tie_ac;

  // Define a*x delta
  a0 = s->b.y - s->c.y;
  a1 = s->c.y - s->a.y;
  a2 = s->a.y - s->b.y;
  // Define b*y delta
  b0 = s->c.x - s->b.x;
  b1 = s->a.x - s->c.x;
  b2 = s->b.x - s->a.x;
  // Define c for Barycentric Interpolation
  c0 = (s->b.x * s->c.y) - (s->c.x * s->b.y); 
  c1 = (s->c.x * s->a.y) - (s->a.x * s->c.y); 
  c2 = (s->a.x * s->b.y) - (s->b.x * s->a.y);
  // Evaluate Edge Equations at xmin, ymin
  w0_row = xmin * a0 + ymin * b0 + c0;
  w1_row = xmin * a1 + ymin * b1 + c1;
  w2_row = xmin * a2 + ymin * b2 + c2;
  // Check Tie Breaker for Edge AC
  tie_ac = (a1 != 0) ? a1 > 0 : b1 > 0;

  // Rasterize Each Pixel
  for (int y = ymin; y <= ymax; y++) {
    // Set X yo Y
    w0 = w0_row;
    w1 = w1_row;
    w2 = w2_row;
    for (int x = xmin; x <= xmax; x++) {
      // Check if is inside or not and Check tie breaker
      if (w0 >= 0 && ( w1 > 0 || (w1 == 0 && tie_ac) ) && w2 >= 0) {
        if (pixels[y * h + x] == 0x00) {
          pixels[y * h + x] = 0xFF << 24 | 0xAB;
        } else {
          pixels[y * h + x] = 0xFF << 24;
        }
      }

      // Step X
      w0 += a0;
      w1 += a1;
      w2 += a2;
    }
    // Step Y
    w0_row += b0;
    w1_row += b1;
    w2_row += b2;
  }
  
}
