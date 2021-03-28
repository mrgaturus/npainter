#include <smmintrin.h>
#include <inttypes.h>

// ----------------------
// TRIANGLE RASTERIZATION
// ----------------------

// -- 2D Vertex
typedef struct {
  float x, y, u, v;
} vertex_t;

// -- Edge Equation
typedef struct {
  float a0, b0, c0;
  float a1, b1, c1;
  float a2, b2, c2;
  // Parameters
  float u0, u1, u2;
  float v0, v1, v2;
  // Half Offset
  float h0, h1, h2;
  // Edge Tie Breaker
  int tie0, tie1, tie2;
  // -- Fully Covered
  float u_a, u_b, u_c;
  float v_a, v_b, v_c;
} equation_t;

// -- Subpixel Rendering
typedef struct {
  int level;
  // Raster Full
  float dudx, dudy;
  float dvdx, dvdy;
} level_t;

typedef struct {
  __m128 color;
  __m128i mask;
} subpixel_t;

typedef struct {
  // -- Full Derivatives
  level_t bot, top;
  // Interpolation
  float fract;
  // -- Edge Derivatives
  float dx0, dx1, dx2;
  float dy0, dy1, dy2;
  // -- Edge Half Offset
  float dr0, dr1, dr2;
  float ds0, ds1, ds2;
  // -- 0xFFFFFFFF Tie
  int tie0, tie1, tie2;
} derivative_t;

// -- Triangle Binning
typedef struct {
  // -- Tile Trivially Reject
  float tr_r0, tr_r1, tr_r2;
  float tr_w0, tr_w1, tr_w2;
  // -- Tile Trivially Accept
  float ta_r0, ta_r1, ta_r2;
  float ta_w0, ta_w1, ta_w2;
  // -- Tiled Equation Steps
  float s_a0, s_a1, s_a2;
  float s_b0, s_b1, s_b2;
} binning_t;

// -- Rendering Info
typedef struct {
  int x, y, w, h;
  // Source Pixels
  int src_w, src_h;
  int16_t* src;
  // Target Pixels
  int dst_w, dst_h;
  // Target Pointers
  int16_t *dst, *mask;
  // Sampler fn
  void* sample_fn;
} fragment_t;

// ----------------
// PIXEL RESAMPLING
// ----------------

// Pixel Resampling Function Pointer
typedef __m128i (*sample_fn_t)(fragment_t*, float, float);
// Pixel Resampling Virtual Methods
__m128i sample_nearest(fragment_t* render, float u, float v);
__m128i sample_bilinear(fragment_t* render, float u, float v);
__m128i sample_bicubic(fragment_t* render, float u, float v);

// One Pixel Premultiplied Alpha Blending
void sample_blend_store(__m128i src, int16_t* dst);
__m128i sample_blend_pack(__m128i src, __m128i dst);

// --------------------------------
// TRIANGLE AND BINNING PREPARING
// --------------------------------

int eq_winding(vertex_t* v);
// -- Triangle Edge Equation Preparing
void eq_calculate(equation_t* eq, vertex_t* v);
void eq_derivative(equation_t* eq, derivative_t* dde);
// -- Triangle Edge Equation Binning
void eq_binning(equation_t* eq, binning_t* bin);

// -- Binning Pivot Definition
void eb_step_xy(binning_t* bin, float x, float y);
// -- Binning Tile Steps
void eb_step_x(binning_t* bin);
void eb_step_y(binning_t* bin);
// -- Binning Trivially Test
int eb_check(binning_t* bin);

// -------------------------------------------
// TRIANGLE RASTERIZATION, SIMPLE AND SUBPIXEL
// -------------------------------------------

// -- Triangle Edge Equation Rendering
void eq_partial(equation_t* eq, fragment_t* render);
void eq_full(equation_t* eq, fragment_t* render);
// -- Triangle Edge Equation Rendering with Antialising
void eq_partial_subpixel(equation_t* eq, derivative_t* dde, fragment_t* render);
void eq_full_subpixel(equation_t* eq, derivative_t* dde, fragment_t* render);
// -- Apply Antialiased Pixels and Free Auxiliar
void eq_apply_antialiasing(fragment_t* render);

// -----------------------------------------------------------
// 2D TRIANGULAR SURFACES, AFFINE, BILINEAR-PERSPECTIVE, NURBS
// -----------------------------------------------------------

typedef struct {
  float x, y;
} vec2_t;

// -- Bi-Perspective
typedef struct {
  // Bilinear
  vec2_t v[4];
  // Perspective
  float a, b, c;
  float d, e, f;
  float g, h, i;
  // Interpolation
  float fract;
} perspective_t;

// -- Bezier Surface
typedef struct {
  vec2_t* v;
  // Degrees
  int w, h;
} bezier_t;

void perspective_calc(perspective_t* surf, vec2_t* v, float fract);
void perspective_evaluate(perspective_t* surf, vertex_t* p);

void bezier_surface_calc(bezier_t* surf, vec2_t* v, int w, int h);
void bezier_surface_evaluate(bezier_t* surf, vertex_t* p);
