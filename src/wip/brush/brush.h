// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2021 Cristian Camilo Ruiz <mrgaturus>
#include <smmintrin.h>

// -------------------
// BRUSH SHAPE TEXTURE
// -------------------

typedef struct {
  // Interpolation & Level
  int fract, tone0, tone1;
  // Texture Size
  int w, h, fixed;
  // Texture Buffer
  unsigned char* buffer;
} brush_texture_t;

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
  // Blotmap Circle
  brush_circle_t circle;
  // Blotmap Texture Difference
  brush_texture_t* tex;
  // ---------------------
} brush_blotmap_t;

typedef struct {
  float sx, sy;
  // Inverse Affine
  int a, b, c;
  int d, e, f;
  // Brush Bitmap Buffer
  brush_texture_t* tex;
  // ------------------
} brush_bitmap_t;

// --------------------
// BRUSH SHAPE BLENDING
// --------------------

typedef struct {
  // Color Acumulation
  int count, total[4];
} brush_average_t;

typedef struct {
  // Color Acumulation
  int count, total[4];
  // Water Tiled
  int x, y, fx, fy;
  // Water Buffer
  int stride;
} brush_water_t;

typedef struct {
  // Buffer Size
  short x, y, w, h;
  // Buffer Position
  short sw, sh;
  // Buffer Bilinear Steps
  int down_fx, down_fy;
  int up_fx, up_fy;
  // Buffer Bilinear Offset
  int offset;
} brush_blur_t;

typedef struct {
  // Copy Position
  int dx, dy;
} brush_smudge_t;

// --------------------
// BRUSH RENDERING TILE
// --------------------

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
  int* color;
  // Shape Alpha
  int alpha, flow;
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

void brush_clip_blend(brush_render_t* render);
// ---------------------------------------------
void brush_normal_blend(brush_render_t* render);
void brush_func_blend(brush_render_t* render);
void brush_flat_blend(brush_render_t* render);
void brush_erase_blend(brush_render_t* render);
// --------------------------------------------
void brush_water_first(brush_render_t* render);
void brush_water_blend(brush_render_t* render);
// --------------------------------------------
void brush_blur_first(brush_render_t* render);
void brush_blur_blend(brush_render_t* render);
// --------------------------------------------
void brush_smudge_first(brush_render_t* render);
void brush_smudge_blend(brush_render_t* render);
