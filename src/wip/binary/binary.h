// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2022 Cristian Camilo Ruiz <mrgaturus>

// ------------------
// Distance Transform
// ------------------

typedef struct {
  int x, y, w, h;
  // Buffer Stride
  int stride, rows;
  // Mask Buffers
  unsigned char *src, *dst;
  // Distance Buffers
  unsigned int* distances;
  unsigned int* positions;
  // Distance Checks
  int check, threshold;
} distance_t;

void distance_prepare(distance_t* chamfer);
void distance_pass0(distance_t* chamfer);
void distance_pass1(distance_t* chamfer);
void distance_convert(distance_t* chamfer);

// -------------------
// Flood Fill Scanline
// -------------------

typedef struct {
  int stride, index;
  // Buffer Bounds
  short x, y, w, h;
  // Buffer Stack
  short* stack;
  // Buffer Pointers
  unsigned char* buffer0;
  unsigned char* buffer1;
  // Scanline AABB
  int x1, y1, x2, y2;
} scanline_t;

typedef struct {
  // Scanline Pivot
  int x, y, w, h;
  // Scanline Stack
  short* stack;
  // Scanline Buffer Pointer
  unsigned char* buffer0;
  unsigned char* buffer1;
  // Scanline AABB
  int x1, y1, x2, y2;
} floodfill_t;

void floodfill_simple(floodfill_t* flood);
void floodfill_dual(floodfill_t* flood);

// ---------------
// Binary to Color
// ---------------

typedef struct {
  // Region Buffer
  int x, y, w, h;
  // Binary & Color Buffer
  void *color, *buffer;
  // Stride Buffer
  int stride, rows;
  // Color <-> Binary
  unsigned int value, threshold;
  unsigned int rgba, check;
} binary_t;

// Color to Binary Convert
void binary_threshold_color(binary_t* binary);
void binary_threshold_alpha(binary_t* binary);
// Binary to Color Convert
void binary_convert_simple(binary_t* binary);

// ----------------
// Binary to Smooth
// TODO: use binary_t instead
// ----------------

typedef struct {
  int x, y, w, h;
  // Buffer Pointers
  unsigned char* binary;
  unsigned char* magic;
  // Grayscale Buffer
  unsigned short* gray;
  // Buffer Strides
  int stride, rows;
  unsigned int rgba, check;
} binary_smooth_t;

void binary_smooth_dilate(binary_smooth_t* smooth);
void binary_smooth_magic(binary_smooth_t* smooth);
void binary_smooth_apply(binary_smooth_t* smooth);
void binary_convert_smooth(binary_smooth_t* smooth);

// --------------------
// Binary Clear Stencil
// --------------------

typedef struct {
  // Region Buffer
  int x, y, w, h;
  // Buffer Pointer
  void* buffer;
  // Buffer Stride
  int stride, bytes;
} binary_clear_t;

typedef struct {
  // Region Buffer
  int x, y, w, h;
  // Buffer Pointer
  void* buffer0;
  void* buffer1;
  // Buffer Stride
  int stride, bytes;
} binary_stencil_t;

void binary_clear(binary_clear_t* clear);
void binary_stencil(binary_stencil_t* stencil);
