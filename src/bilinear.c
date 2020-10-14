#include <math.h>

typedef struct {
  float x, y;
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

vec2_t vec2_negate(vec2_t a) {
  return (vec2_t) {-a.x, -a.y};
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

int bilinear_mapping(quad_t* q, vec2_t p, vec2_t* uv) {
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
  if (k2 == 0.0) {
    v = -k0 / k1;
    
    d = (e.x + g.x * v);
    if (d != 0.0)
      u = (h.x - f.x * v) / d;
    else
      u = (h.y - f.y * v) / (e.y + g.y * v);
  } else {
    double w = k1 * k1 - 4.0 * k0 * k2;
    if (w < 0.0) return 0;

    w = sqrt(w);
    v = (-k1 - w) / (2.0 * k2);

    d = (e.y + g.y * v);
    if (d != 0.0)
      u = (h.y - f.y * v) / d;
    else
      u = (h.x - f.x * v) / (e.x + g.x * v);

    // If not inside, test positive solution
    if (v <= 0.0 || v >= 1.0 || u <= 0.0 || u >= 1.0) {
      v = (-k1 + w) / (2.0 * k2);

      d = (e.y + g.y * v);
      if (d != 0.0)
        u = (h.y - f.y * v) / d;
      else
        u = (h.x - f.x * v) / (e.x + g.x * v);
    }
  }

  // Test if is inside UV quad
  if (v > 0.0 && v < 1.0 && u > 0.0 && u < 1.0) {
    uv->x = u; uv->y = v;
    return 1;
  }

  // Not Inside
  return 0;
}