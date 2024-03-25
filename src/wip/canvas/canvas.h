// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
#ifndef NPAINTER_CANVAS_H
#define NPAINTER_CANVAS_H
#include <smmintrin.h>

static void canvas_copy_align(canvas_copy_t* copy, int* x, int* y) {
  int cx = *x;
  int cy = *y;
  // Clip Positions to Real Bounding
  cx = (cx < copy->w0) ? cx : copy->w0;
  cy = (cy < copy->h0) ? cy : copy->h0;
  // Align Lane to 32
  if (cx & 0x1F)
    cx = (cx | 0x1F) + 1;

  // Replace to Clipped
  *x = cx;
  *y = cy;
}

// ---------------------
// Canvas Stream Objects
// ---------------------

typedef struct {
  unsigned int color0;
  unsigned int color1;
  // Checker Pattern
  unsigned char* checker;
  int shift;
} canvas_bg_t;

typedef struct {
  int w0, h0, s0;
  unsigned char* buffer;
} canvas_src_t;

typedef struct {
  int x256, y256;
  int x, y, w, h;
  // Canvas Background
  canvas_bg_t* bg;
  // Copy Buffers
  int w0, h0, s0;
  unsigned char *buffer0;
  unsigned char *buffer1;
} canvas_copy_t;

// Canvas Stream Copy + Background
void canvas_copy_stream(canvas_copy_t* copy);
void canvas_copy_white(canvas_copy_t* copy);
void canvas_copy_color(canvas_copy_t* copy);
// Canvas Stream Copy + Pattern
void canvas_copy_checker(canvas_copy_t* copy);
void canvas_gen_checker(canvas_bg_t* bg);
// Canvas Stream Copy - Padding
void canvas_copy_padding(canvas_copy_t* copy);

#endif // NPAINTER_CANVAS_H
