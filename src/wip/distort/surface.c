#include <math.h>
#include <string.h>
#include "distort.h"

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

// ------------------------------------
// CATMULL SURFACE PATCH TRANSFORMATION
// ------------------------------------

static void catmull_endpoints(vec2_t* v, int w) {
  w += 2; // Add End Points

  vec2_t cp;
  // A = B - (C - B)
  cp = vec2_sub(v[2], v[1]);
  cp = vec2_sub(v[1], cp);
  // Start Point
  v[0] = cp;

  // D = C + (C - B)
  cp = vec2_sub(v[w - 2], v[w - 3]);
  cp = vec2_add(v[w - 2], cp);
  // End Point
  v[w - 1] = cp;
}

void catmull_surface_calc(catmull_t* surf, vec2_t* v, int w, int h) {
  const int s = h + 2;
  // Calculate End Points
  for (int i = 0; i < h; i++)
    catmull_endpoints(v + s * i, h);

  // Mesh of Curves
  surf->curves = v;
  // Bind Horizontally Curve
  surf->curve = v + s * w;

  surf->w = w;
  surf->h = h;
  surf->s = s;
  // Reset V Cache
  surf->v = INFINITY;
}

static float catmull_lookup(float* cp_x, float* cp_y, vec2_t* cp, int count, float t) {
  int i; float t0, t1;

  // Get Interpolation
  t1 = (count - 1) * t;
  t0 = floor(t1);

  // Get Point Index
  i = (int) t0;
  t = t1 - t0;

  // Get Curve Segment
  cp_x[0] = cp[i + 0].x;
  cp_x[1] = cp[i + 1].x;
  cp_x[2] = cp[i + 2].x;
  cp_x[3] = cp[i + 3].x;

  cp_y[0] = cp[i + 0].y;
  cp_y[1] = cp[i + 1].y;
  cp_y[2] = cp[i + 2].y;
  cp_y[3] = cp[i + 3].y;

  return t;
}

static vec2_t catmull_evaluate(float* cp_x, float* cp_y, float t) {
  float p[4], t2, t3;
  // SSE4.1 Dot Product
  __m128 xmm0, xmm1, xmm2;

  t2 = t * t;
  t3 = t2 * t;

  p[0] = (-0.5 * t3) + t2 - (0.5 * t);
  p[1] = (1.5 * t3) - (2.5 * t2) + 1.0;
  p[2] = (-1.5 * t3) + (2.0 * t2) + (0.5 * t);
  p[3] = (0.5 * t3) - (0.5 * t2);

  // Load Cooeffients
  xmm0 = _mm_loadu_ps(p);
  // Load Control Points
  xmm1 = _mm_loadu_ps(cp_x);
  xmm2 = _mm_loadu_ps(cp_y);

  // Perform SSE4.1 Dot Product
  xmm1 = _mm_dp_ps(xmm0, xmm1, 0xFF);
  xmm2 = _mm_dp_ps(xmm0, xmm2, 0xFF);

  vec2_t result;
  // Store Interpolated
  result.x = _mm_cvtss_f32(xmm1);
  result.y = _mm_cvtss_f32(xmm2);

  return result;
}

void catmull_surface_evaluate(catmull_t* surf, vertex_t* p) {
  vec2_t *curves, *curve, point;
  // Current Curve Segment
  float cp_x[4], cp_y[4];

  float u, v, t;
  // Interpolation
  u = p->x; v = p->y;
  // Curve Pointers
  curves = surf->curves;
  curve = surf->curve;

  int w, h, s;
  // Dimensions
  w = surf->w;
  h = surf->h;
  s = surf->s;

  if (v != surf->v) {
    // Calculate Horizontal Curve
    for (int i = 0; i < h; i++) {
      // Load Current Curve
      t = catmull_lookup(cp_x, cp_y,
        curves + s * i, h, v);

      // Evaluate Curve and Save Point
      curve[i + 1] = catmull_evaluate(cp_x, cp_y, t);
    }

    // Calculate Endpoints
    catmull_endpoints(curve, w);
    // Replace Cache
    surf->v = v;
  }
  
  // Evaluate Horizontally
  t = catmull_lookup(cp_x, cp_y, curve, w, u);
  point = catmull_evaluate(cp_x, cp_y, t);

  // Store New Point
  p->x = point.x;
  p->y = point.y;
}
