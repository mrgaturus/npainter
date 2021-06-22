#include <smmintrin.h>

// -------------------
// BRUSH SHAPE MASKING
// -------------------

typedef struct {
  // Position & Size
  float x, y, size;
  // Style Attribute
  float smooth;
} brush_circle_t;

typedef struct {
  // Interpolation
  short alpha, fract;
  // Texture Size
  int w, h;
  // Texture Buffer
  unsigned char* buffer;
} brush_texture_t;

typedef struct {
  brush_circle_t circle;
  // Difference Masking
  brush_texture_t* texture;
  // ---------------------
} brush_blotmap_t;

typedef struct {
  // Inverse Affine
  float a, b, c;
  float d, e, f;
  // Subpixel LOD
  int level;
  // Brush Bitmap Buffer
  brush_texture_t* texture;
  // ------------------
} brush_bitmap_t;

// ---------------------
// BRUSH BLENDING ENGINE
// ---------------------

typedef struct {
  int count0, count1;
  // Color Acumulation
  int color_sum[4];
} brush_average_t;

typedef struct {
  int count0, count1;
  // Color Acumulation
  int color_sum[4];
  // Water Tiled
  int x, y, w, h;
} brush_water_t;

typedef struct {
  // Backup Region
  int x, y, w, h;
  // Render Offset
  int ox, oy;
} brush_smudge_t;

// -----------------
// BRUSH RENDER TILE
// -----------------

typedef struct {
  int w, h, stride;
  // CLipping Buffers
  short *clip, *alpha;
  // Auxiliar Buffers
  short *buffer0;
  short *buffer1;
  // Destination
  short *dst;
} brush_canvas_t;

typedef struct {
  int x, y, w, h;
  // Shape Color
  short* color;
  // Shape Basic
  int alpha, size;
  // Canvas Target Buffers
  brush_canvas_t* canvas;
  // Aditional Data
  void* opaque;
} brush_render_t;

// ----------------------------
// BRUSH ENGINE SHAPE RENDERING
// ----------------------------

void brush_circle_mask(brush_render_t* render, brush_circle_t* circle);
void brush_blotmap_mask(brush_render_t* render, brush_blotmap_t* blot);
void brush_bitmap_mask(brush_render_t* render, brush_bitmap_t* bitmap);
// --------------------------------------------------------------------
void brush_texture_mask(brush_render_t* render, brush_texture_t* tex);

// ---------------------------
// BRUSH ENGINE BLENDING MODES
// ---------------------------

void brush_normal_blend(brush_render_t* render);
void brush_func_blend(brush_render_t* render);
void brush_flat_blend(brush_render_t* render);
void brush_erase_blend(brush_render_t* render);
// --------------------------------------------
void brush_water_first(brush_render_t* render);

void brush_water_blend(brush_render_t* render);
void brush_marker_blend(brush_render_t* render);
// --------------------------------------------
void brush_blur_first(brush_render_t* render);
void brush_blur_blend(brush_render_t* render);
// --------------------------------------------
void brush_smudge_first(brush_render_t* render);
void brush_smudge_blend(brush_render_t* render);
// --------------------------------------------
void brush_selection_clip(brush_render_t* render);

void brush_selection_blend(brush_render_t* render);
void brush_selection_erase(brush_render_t* render);
