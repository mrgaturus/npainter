#include "distort.h"
#include <string.h>

// --------------------------------------
// 2D VECTOR OPERATION ONLY REVELANT HERE
// --------------------------------------

static vec2_t vec2_add(vec2_t a, vec2_t b) {
  return (vec2_t) {a.x + b.x, a.y + b.y};
}

static vec2_t vec2_sub(vec2_t a, vec2_t b) {
  return (vec2_t) {a.x - b.x, a.y - b.y};
}

static float vec2_cross(vec2_t a, vec2_t b) {
  return a.x * b.y - a.y * b.x;
}

// -----------------------------------
// PERSPECTIVE-BILINEAR TRANSFORMATION
// -----------------------------------

static int perspective_check(vec2_t* v) {
  vec2_t a = vec2_sub(v[1], v[3]);
  vec2_t b = vec2_sub(v[0], v[2]);

  double cross = vec2_cross(a, b);
  if (cross != 0.0) {
    vec2_t c = vec2_sub(v[3], v[2]);

    double u, v;
    u = vec2_cross(a, c) / cross;
    v = vec2_cross(b, c) / cross;
    // Avoid Almost Invalid Artifacts
    u = round(u * 100) * 0.01;
    v = round(v * 100) * 0.01;

    // Check if Perspective Homography is Valid
    return (u > 0.0 && u < 1.0 && v > 0.0 && v < 1.0);
  }
  
  // Invalid Homography
  return 0;
}

void perspective_calc(perspective_t* surf, vec2_t* v, float fract) {
  // Check if is able for homography
  if ( perspective_check(v) ) {
    vec2_t d1, d2, s;
    d1 = vec2_sub(v[1], v[2]);
    d2 = vec2_sub(v[3], v[2]);
    s = vec2_add(
      vec2_sub(v[0], v[1]),
      vec2_sub(v[2], v[3])
    ); 

    // Homography Coeffients
    double det, g, h, i, a, b, c, d, e, f;
    
    det = vec2_cross(d1, d2);
    g = vec2_cross(s, d2) / det;
    h = vec2_cross(d1, s) / det;

    a = v[1].x + g * v[1].x - v[0].x;
    b = v[3].x + h * v[3].x - v[0].x;
    c = v[0].x;

    d = v[1].y + g * v[1].y - v[0].y;
    e = v[3].y + h * v[3].y - v[0].y;
    f = v[0].y;

    // Store Perspective Transform
    surf->a = a; surf->b = b; surf->c = c;
    surf->d = d; surf->e = e; surf->f = f;
    surf->g = g; surf->h = h; surf->i = 1;

    // Store Interpolation
    surf->fract = 0.75 * fract;
  } else { surf->fract = 0.0; }

  // Store Bilinear Interpolation Points
  memcpy(surf->v, v, sizeof(vec2_t) * 4);
}

void perspective_evaluate(perspective_t* surf, vertex_t* p) {
  vec2_t* ve = surf->v;
  // UV Variables
  float u, x0, x1;
  float v, y0, y1;
  // UV Unit
  u = p->x;
  v = p->y;

  // Calculate Bilinear Transform
  x0 = ve[0].x + (ve[1].x - ve[0].x) * u;
  x1 = ve[3].x + (ve[2].x - ve[3].x) * u;
  x0 = x0 + (x1 - x0) * v;

  y0 = ve[0].y + (ve[1].y - ve[0].y) * u;
  y1 = ve[3].y + (ve[2].y - ve[3].y) * u;
  y0 = y0 + (y1 - y0) * v;

  if (surf->fract > 0.0) {
    float a, b, c;
    float d, e, f;
    float g, h, i;
    // Divisor
    float raw;

    a = surf->a; b = surf->b; c = surf->c;
    d = surf->d; e = surf->e; f = surf->f;
    g = surf->g; h = surf->h; i = surf->i;

    raw = (g * u + h * v + i);
    // Calculate Homography Transformation
    x1 = (a * u + b * v + c) / raw;
    y1 = (d * u + e * v + f) / raw;

    raw = surf->fract;
    // Interpolate Both Transforms
    x0 = x0 + (x1 - x0) * raw;
    y0 = y0 + (y1 - y0) * raw;
  }

  // Store New Point
  p->x = x0; p->y = y0;
}

// -----------------------------
// BEZIER SURFACE TRANSFORMATION
// -----------------------------
