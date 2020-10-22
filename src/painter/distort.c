// Prototype Bilinear-Perspective Distort
// TODO: Precalculate Matrices
#include <math.h>

// Border Rounding Constants
#define E_BORDER 8192
#define E_BORDER_DIV 0.0001220703125

// -----------------------
// TODO: Move to algebra.c
// -----------------------

typedef struct {
  double x, y;
} vec2_t;

typedef struct {
  vec2_t v[4];
} quad_t;

vec2_t vec2_add(vec2_t a, vec2_t b) {
  return (vec2_t) {a.x + b.x, a.y + b.y};
}

vec2_t vec2_sub(vec2_t a, vec2_t b) {
  return (vec2_t) {a.x - b.x, a.y - b.y};
}

float vec2_cross(vec2_t a, vec2_t b) {
  return a.x * b.y - a.y * b.x;
}

// DEBUG ONLY
unsigned short checkboard(vec2_t uv) {
  const double M = 5;
  double p = (fmod(uv.x * M, 1.0) > 0.5) ^ (fmod(uv.y * M, 1.0) < 0.5);
  return (unsigned short) (p * 65535);
}

void debug_quad(quad_t* q) {
  printf("quad 1: x %f, y %f\n", q->v[0].x, q->v[0].y);
  printf("quad 2: x %f, y %f\n", q->v[1].x, q->v[1].y);
  printf("quad 3: x %f, y %f\n", q->v[2].x, q->v[2].y);
  printf("quad 4: x %f, y %f\n\n", q->v[3].x, q->v[3].y);
}

// ----------------------------
// Convex Perspective Transform
// ----------------------------

int perspective_check(quad_t* q) {
  vec2_t a = vec2_sub(q->v[1], q->v[3]);
  vec2_t b = vec2_sub(q->v[0], q->v[2]);

  double cross = vec2_cross(a, b);
  if (cross != 0.0) {
    vec2_t c = vec2_sub(q->v[3], q->v[2]);

    double s, t;
    s = vec2_cross(a, c) / cross;
    t = vec2_cross(b, c) / cross;

    return s > 0.0 && s < 1.0 && t > 0.0 && t < 1.0;
  }
  
  return 0;
}

void perspective_distort(quad_t* q, vec2_t p, vec2_t* uv) {
  vec2_t d1, d2, s;
  d1 = vec2_sub(q->v[1], q->v[2]);
  d2 = vec2_sub(q->v[3], q->v[2]);
  s = vec2_add(
    vec2_sub(q->v[0], q->v[1]),
    vec2_sub(q->v[2], q->v[3])
  );

  // Homography Coeffients
  double det, g, h, a, b, c, d, e, f;
  
  det = vec2_cross(d1, d2);
  g = vec2_cross(s, d2) / det;
  h = vec2_cross(d1, s) / det;

  a = q->v[1].x + g * q->v[1].x - q->v[0].x;
  b = q->v[3].x + h * q->v[3].x - q->v[0].x;
  c = q->v[0].x;

  d = q->v[1].y + g * q->v[1].y - q->v[0].y;
  e = q->v[3].y + h * q->v[3].y - q->v[0].y;
  f = q->v[0].y;

  // Inverse Homography Coeffients
  double A, B, C, D, E, F, G, H, I;
  A = e - f * h;
  B = c * h - b;
  C = b * f - c * e;

  D = f * g - d;
  E = a - c * g;
  F = c * d - a * f;

  G = d * h - e * g;
  H = b * g - a * h;
  I = a * e - b * d;

  double denom, u, v;
  denom = (G * p.x + H * p.y + I);
  u = (A * p.x + B * p.y + C) / denom;
  v = (D * p.x + E * p.y + F) / denom;

  // Avoid Losing 1px border
  u = round(u * E_BORDER) * E_BORDER_DIV;
  v = round(v * E_BORDER) * E_BORDER_DIV;
  // Check Inside Later
  uv->x = u; uv->y = v;
}

// -------------------------
// Convex Bilinear Transform
// -------------------------

void bilinear_distort(quad_t* q, vec2_t p, vec2_t* uv) {
  vec2_t e, f, g, h;
  // TODO: Precalculate Some
  e = vec2_sub(q->v[1], q->v[0]);
  f = vec2_sub(q->v[3], q->v[0]);
  g = vec2_add(
    vec2_sub(q->v[0], q->v[1]),
    vec2_sub(q->v[2], q->v[3])
  );
  h = vec2_sub(p, q->v[0]);

  double k0, k1, k2;
  k2 = vec2_cross(g, f);
  k1 = vec2_cross(e, f) + vec2_cross(h, g);
  k0 = vec2_cross(h, e);

  double v, u, d;
  if (k2 == 0.0)
    v = -k0 / k1;
  else {
    double w = k1 * k1 - 4.0 * k0 * k2;
    if (w < 0.0) return;

    w = sqrt(w);
    // Calculate Negative Solution
    v = (-k1 - w) / (2.0 * k2);
    // If Outside, Positive solution
    if (v < 0.0 || v > 1.0)
      v = (-k1 + w) / (2.0 * k2);
  }

  d = (e.x + g.x * v);
  if (d != 0.0)
    u = (h.x - f.x * v) / d;
  else {
    d = (e.y + g.y * v);
    u = (h.y - f.y * v) / d;
  }

  // Avoid Losing 1px border
  u = round(u * E_BORDER) * E_BORDER_DIV;
  v = round(v * E_BORDER) * E_BORDER_DIV;
  // Check Inside Later
  uv->x = u; uv->y = v;
}

// -------------------------------------
// Interpolate Between Convex Transforms
// -------------------------------------

int both_distort(quad_t* q, vec2_t p, vec2_t* uv, double t) {
  vec2_t uv_p, uv_b;

  // Calculate Perspective
  perspective_distort(q, p, &uv_p);
  if (uv_p.x < 0.0 || uv_p.x > 1.0 || uv_p.y < 0.0 || uv_p.y > 1.0)
    return 0; // Not Inside Perspective

  // Calculate Inverse Bilinear
  bilinear_distort(q, p, &uv_b);
  if (uv_b.x < 0.0 || uv_b.x > 1.0 || uv_b.y < 0.0 || uv_b.y > 1.0)
    return 0; // Not Inside Inverse Bilinear

  // Interpolate Both Transforms
  uv->x = uv_b.x + t * (uv_p.x - uv_b.x);
  uv->y = uv_b.y + t * (uv_p.y - uv_b.y);

  // Inside
  return 1;
}
