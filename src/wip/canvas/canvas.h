// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
#ifndef NPAINTER_CANVAS_H
#define NPAINTER_CANVAS_H
#include <smmintrin.h>

// ---------------------
// Canvas Stream Objects
// ---------------------

typedef struct {
  unsigned int color0;
  unsigned int color1;
  // Checker Pattern
  unsigned int* buffer;
  int shift;
} canvas_bg_t;

typedef struct {
  int w0, h0, s0;
  unsigned char* buffer;
} canvas_src_t;

typedef struct {
  int x256, y256;
  int x, y, w, h;
  // Canvas Data
  canvas_bg_t* bg;
  canvas_src_t* src;
  // Canvas PBO Buffer
  unsigned char *buffer;
} canvas_copy_t;

// -----------------------
// Canvas Stream Functions
// -----------------------

static void canvas_src_clamp(canvas_src_t* src, int* x, int* y) {
  int cx = *x;
  int cy = *y;
  // Clip Positions to Real Bounding
  cx = (cx < src->w0) ? cx : src->w0;
  cy = (cy < src->h0) ? cy : src->h0;
  // Align Lane to 32 Bounding
  cx = (cx + 0x1F) & ~0x1F;

  // Replace to Clipped
  *x = cx;
  *y = cy;
}

// Canvas Stream Copy + Background
void canvas_copy_stream(canvas_copy_t* copy);
void canvas_copy_white(canvas_copy_t* copy);
void canvas_copy_color(canvas_copy_t* copy);
// Canvas Stream Copy + Pattern
void canvas_gen_checker(canvas_bg_t* bg);
void canvas_copy_checker(canvas_copy_t* copy);
// Canvas Stream Padding
void canvas_copy_padding(canvas_copy_t* copy);

#endif // NPAINTER_CANVAS_H
