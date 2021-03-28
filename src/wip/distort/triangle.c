#include <math.h>
#include "distort.h"

// ----------------------------------------
// EDGE EQUATION ORIENT CHECK & CALCULATION
// ----------------------------------------

int eq_winding(vertex_t* v) {
  float ax, ay, bx, by, area;
  // Segment AC
  ax = v[1].x - v[0].x;
  ay = v[1].y - v[0].y;
  // Segment AB
  bx = v[2].x - v[0].x;
  by = v[2].y - v[0].y;

  // Calculate Oriented Area
  area = (ax * by) - (ay * bx);
  
  int result;
  result = // Get Area Sign
    (0.0 < area) - (area < 0.0);

  if (result < 0) {
    vertex_t swap;
    // Swap Vertex
    swap = v[0];
    v[0] = v[2];
    v[2] = swap;
  }

  return result;
}

// -------------------------
// EDGE EQUATION CALCULATION
// -------------------------

void eq_calculate(equation_t* eq, vertex_t* v) {
  float a0, a1, a2;
  float b0, b1, b2;
  float c0, c1, c2;
  // Parameter Coeff
  float z_a, z_b, z_c;
  float z0, z1, z2;
  // Edge Tie Breaker
  int tie0, tie1, tie2;

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
  // Calculate Reciprocal Triangle Area
  float area = 1.0 / (c0 + c1 + c2);

  // Define U Parameter
  z0 = v[0].u * area;
  z1 = v[1].u * area;
  z2 = v[2].u * area;
  // Define U Parameter Equation
  z_a = a0 * z0 + a1 * z1 + a2 * z2;
  z_b = b0 * z0 + b1 * z1 + b2 * z2;
  z_c = c0 * z0 + c1 * z1 + c2 * z2;
  // Store U Parameter Equation
  eq->u0 = z0; eq->u_a = z_a;
  eq->u1 = z1; eq->u_b = z_b;
  eq->u2 = z2; eq->u_c = z_c;

  // Define V Parameter
  z0 = v[0].v * area;
  z1 = v[1].v * area;
  z2 = v[2].v * area;
  // Define V Parameter Equation
  z_a = a0 * z0 + a1 * z1 + a2 * z2;
  z_b = b0 * z0 + b1 * z1 + b2 * z2;
  z_c = c0 * z0 + c1 * z1 + c2 * z2;
  // Store V Parameter Equation
  eq->v0 = z0; eq->v_a = z_a;
  eq->v1 = z1; eq->v_b = z_b;
  eq->v2 = z2; eq->v_c = z_c;

  // Store Edge Equation
  eq->a0 = a0; eq->b0 = b0; eq->c0 = c0;
  eq->a1 = a1; eq->b1 = b1; eq->c1 = c1;
  eq->a2 = a2; eq->b2 = b2; eq->c2 = c2;
  // Store Edge Half Offset
  eq->h0 = (a0 * 0.5) + (b0 * 0.5);
  eq->h1 = (a1 * 0.5) + (b1 * 0.5);
  eq->h2 = (a2 * 0.5) + (b2 * 0.5);
  
  // Set Edge Tie Breaker
  tie0 = (a0 == 0.0) ? b0 > 0.0 : a0 > 0.0;
  tie1 = (a1 == 0.0) ? b1 > 0.0 : a1 > 0.0;
  tie2 = (a2 == 0.0) ? b2 > 0.0 : a2 > 0.0;

  // Fill all Bits
  eq->tie0 = -tie0;
  eq->tie1 = -tie1;
  eq->tie2 = -tie2;
}

// ------------------------------------
// EDGE EQUATION DERIVATIVE CALCULATION
// ------------------------------------

static void eq_derivative_level(equation_t* eq, level_t* dde, int level) {
  float rcp = 1.0 / level;

  // Derivative Steps Full
  dde->dudx = eq->u_a * rcp;
  dde->dudy = eq->u_b * rcp;

  dde->dvdx = eq->v_a * rcp;
  dde->dvdy = eq->v_b * rcp;

  // Store Subpixel Level
  dde->level = level;
}

void eq_derivative(equation_t* eq, derivative_t* dde) {
  float dx, ddu;
  float dy, ddv;
  // Equation Steps
  float a0, a1, a2;
  float b0, b1, b2;
  float r0, r1, r2;

  // dudx * dudx + dudy * dudy
  dx = eq->u_a; dy = eq->u_b;
  ddu = dx * dx + dy * dy;

  // dvdx * dvdx + dvdy * dvdy
  dx = eq->v_a; dy = eq->v_b;
  ddv = dx * dx + dy * dy;

  float raw, level, fract;
  // Calculate Mipmap Level
  raw = (ddu > ddv) ? ddu: ddv;
  raw = log2(raw);
  // Avoid Negative
  if (raw < 0.0)
    raw = 0.0;

  level = floor(raw);
  fract = raw - level;

  int lvl = (int) level;
  // Derivative Steps Full
  eq_derivative_level(eq, &dde->bot, lvl + 1);
  eq_derivative_level(eq, &dde->top, lvl + 2);
  // Derivative Interpolation
  dde->fract = fract;

  raw = 0.0625;
  // 16x16 subpixel mask
  a0 = eq->a0 * raw;
  a1 = eq->a1 * raw;
  a2 = eq->a2 * raw;

  b0 = eq->b0 * raw;
  b1 = eq->b1 * raw;
  b2 = eq->b2 * raw;

  // Unit Offset
  r0 = a0 + b0;
  r1 = a1 + b1;
  r2 = a2 + b2;
  // Store Step
  dde->ds0 = r0;
  dde->ds1 = r1;
  dde->ds2 = r2;

  raw = 0.5;
  // Store 0.5 Offset
  dde->dr0 = r0 * raw;
  dde->dr1 = r1 * raw; 
  dde->dr2 = r2 * raw;

  raw = 2.0;
  // Store Steps as 8x8
  dde->dx0 = a0 * raw;
  dde->dx1 = a1 * raw;
  dde->dx2 = a2 * raw;

  dde->dy0 = b0 * raw;
  dde->dy1 = b1 * raw;
  dde->dy2 = b2 * raw;

  // Copy Tie Checker
  dde->tie0 = eq->tie0;
  dde->tie1 = eq->tie1;
  dde->tie2 = eq->tie2;
}

// ----------------------------------
// TRIANGLE TILED BINNING CALCULATION
// ----------------------------------
const float step = 8.0;

static void eq_trivially(float a0, float b0, float c0, float* tr_r0, float* ta_r0) {
  float ox, oy;

  // Trivially Reject Edge 0
  ox = (a0 >= 0.0) ? step : 0.0;
  oy = (b0 >= 0.0) ? step : 0.0;
  // Calculate Equation Position
  *(tr_r0) = a0 * ox + b0 * oy + c0;

  // Trivially Accept Edge 0
  ox = (a0 >= 0.0) ? 0.0 : step;
  oy = (b0 >= 0.0) ? 0.0 : step;
  // Calculate Equation Position
  *(ta_r0) = a0 * ox + b0 * oy + c0;
}

void eq_binning(equation_t* eq, binning_t* bin) {
  float a0, a1, a2;
  float b0, b1, b2;
  float c0, c1, c2;

  // Load Edge Equation Steps
  a0 = eq->a0; a1 = eq->a1; a2 = eq->a2;
  b0 = eq->b0; b1 = eq->b1; b2 = eq->b2;
  c0 = eq->c0; c1 = eq->c1; c2 = eq->c2;

  // Calculate Reject & Accept Trivially Corners
  eq_trivially(a0, b0, c0, &bin->tr_r0, &bin->ta_r0);
  eq_trivially(a1, b1, c1, &bin->tr_r1, &bin->ta_r1);
  eq_trivially(a2, b2, c2, &bin->tr_r2, &bin->ta_r2);

  // Edge Equation Steps
  bin->s_a0 = a0 * step;
  bin->s_a1 = a1 * step;
  bin->s_a2 = a2 * step;

  bin->s_b0 = b0 * step;
  bin->s_b1 = b1 * step;
  bin->s_b2 = b2 * step;
}

// --------------------------------------------
// TRIANGLE TILED BINNING ITERATOR - Tile Units
// --------------------------------------------

void eb_step_xy(binning_t* bin, float x, float y) {
  // Define Trivially Reject
  bin->tr_r0 += (bin->s_a0 * x) + (bin->s_b0 * y);
  bin->tr_r1 += (bin->s_a1 * x) + (bin->s_b1 * y);
  bin->tr_r2 += (bin->s_a2 * x) + (bin->s_b2 * y);
  // Reset Horizontal
  bin->tr_w0 = bin->tr_r0;
  bin->tr_w1 = bin->tr_r1;
  bin->tr_w2 = bin->tr_r2;

  // Define Trivially Accept
  bin->ta_r0 += (bin->s_a0 * x) + (bin->s_b0 * y);
  bin->ta_r1 += (bin->s_a1 * x) + (bin->s_b1 * y);
  bin->ta_r2 += (bin->s_a2 * x) + (bin->s_b2 * y);
  // Reset Horizontal
  bin->ta_w0 = bin->ta_r0;
  bin->ta_w1 = bin->ta_r1;
  bin->ta_w2 = bin->ta_r2;
}

void eb_step_x(binning_t* bin) {
  // Step Reject Horizontal
  bin->tr_w0 += bin->s_a0;
  bin->tr_w1 += bin->s_a1;
  bin->tr_w2 += bin->s_a2;

  // Step Accept Horizontal
  bin->ta_w0 += bin->s_a0;
  bin->ta_w1 += bin->s_a1;
  bin->ta_w2 += bin->s_a2;
}

void eb_step_y(binning_t* bin) {
  // Step Reject Vertical
  bin->tr_r0 += bin->s_b0;
  bin->tr_r1 += bin->s_b1;
  bin->tr_r2 += bin->s_b2;
  // Reset Horizontal
  bin->tr_w0 = bin->tr_r0;
  bin->tr_w1 = bin->tr_r1;
  bin->tr_w2 = bin->tr_r2;

  // Step Accept Vertical
  bin->ta_r0 += bin->s_b0;
  bin->ta_r1 += bin->s_b1;
  bin->ta_r2 += bin->s_b2;
  // Reset Horizontal
  bin->ta_w0 = bin->ta_r0;
  bin->ta_w1 = bin->ta_r1;
  bin->ta_w2 = bin->ta_r2;
}

// -----------------------------
// TRIANGLE TILED BINNING TESTER
// -----------------------------

// 0 - Trivially Reject 
// 1, 2 - Partially
// 3 - Trivially Accept
int eb_check(binning_t* bin) {
  int count = 0;

  // Sum Trivially Reject Count
  count += (bin->tr_w0 < 0.0);
  count += (bin->tr_w1 < 0.0);
  count += (bin->tr_w2 < 0.0);

  // No Trivially Rejected
  if (count == 0) {
    // Sum Trivially Accept Count
    count += (bin->ta_w0 >= 0.0);
    count += (bin->ta_w1 >= 0.0);
    count += (bin->ta_w2 >= 0.0);
    // Avoid Rejected When Passed
    count += (count == 0);
  } else {
    // Rejected
    count = 0;
  }

  return count;
}
