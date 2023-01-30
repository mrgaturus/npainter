// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
#include "binary.h"
#include <smmintrin.h>

static void scanline_dual_right(scanline_t* scan) {
  unsigned char *buffer0, *buffer1;
  unsigned char *upper0, *upper1;
  unsigned char *lower0, *lower1;
  // Calculate Buffer Stride
  const int stride = scan->stride;
  const int index = scan->index;
  // Calculate Buffer Position
  int x = scan->x;
  int y = scan->y;
  // Calculate Stack Pointer
  short* stack = scan->stack;
  // Calculate Buffer Size
  const int w = scan->w;
  const int h = scan->h;
  // Calculate Buffer Location
  buffer0 = scan->buffer0 + index;
  buffer1 = scan->buffer1 + index;
  // Calculate Scanline Advances
  upper0 = buffer0 - stride;
  upper1 = buffer1 - stride;
  lower0 = buffer0 + stride;
  lower1 = buffer1 + stride;
  // Check Scanline Advances
  if (y - 1 < 0) upper0 = (void*) 0;
  if (y + 1 >= h) lower0 = (void*) 0;

  unsigned int prev1, prev2;
  unsigned int check0, check1, check2;
  // Initialize Checking
  prev1 = prev2 = check0 = 0;
  // Calculate Scanline Blank
  for (int i = w - x; i > 0; i--, x++) {
    check0 = *buffer0 ^ *buffer1 >> 1;
    if (check0 < 255) break;

    // Check Scanline Advances
    check1 = upper0 ? (*upper0++ ^ *upper1++ >> 1) : 0;
    check2 = lower0 ? (*lower0++ ^ *lower1++ >> 1) : 0;

    if (prev1 != check1 && check1 > 127) {
      *(stack++) = x;
      *(stack++) = y - 1;
    }

    if (prev2 != check2 && check2 > 127) {
      *(stack++) = x;
      *(stack++) = y + 1;
    }

    // Set Previous Check
    prev1 = check1;
    prev2 = check2;
    // Put Current Mask
    *(buffer0) = 127;
    // Step Buffers
    buffer0++;
    buffer1++;
  }

  // Initialize Checking
  prev1 = prev2 = check0 = 0;
  // Calculate Scanline Gap
  for (int i = w - x; i > 0; i--, x++) {
    check0 = *buffer0 & *buffer1;
    if (check0 < 255) break;
    // Check Scanline Advances
    check1 = upper0 ? (*upper0++ & *upper1++) : 0;
    check2 = lower0 ? (*lower0++ & *lower1++) : 0;

    if (prev1 != check1 && check1 > 127) {
      *(stack++) = x;
      *(stack++) = y - 1;
    }

    if (prev2 != check2 && check2 > 127) {
      *(stack++) = x;
      *(stack++) = y + 1;
    }

    // Set Previous Check
    prev1 = check1;
    prev2 = check2;
    // Put Current Mask
    *(buffer0) = 127;
    // Step Buffers
    buffer0++;
    buffer1++;
  }

  // Replace Current Stack
  scan->stack = stack;
  // Check Right Boundary
  if (x > scan->x2)
    scan->x2 = x;
}

static void scanline_dual_left(scanline_t* scan) {
  unsigned char *buffer0, *buffer1;
  unsigned char *upper0, *upper1;
  unsigned char *lower0, *lower1;
  // Calculate Buffer Stride
  const int stride = scan->stride;
  const int index = scan->index - 1;
  // Calculate Buffer Position
  int x = scan->x - 1;
  int y = scan->y;
  // Calculate Stack Pointer
  short* stack = scan->stack;
  // Calculate Buffer Size
  const int w = scan->w;
  const int h = scan->h;
  // Calculate Buffer Location
  buffer0 = scan->buffer0 + index;
  buffer1 = scan->buffer1 + index;
  // Calculate Scanline Advances
  upper0 = buffer0 - stride;
  upper1 = buffer1 - stride;
  lower0 = buffer0 + stride;
  lower1 = buffer1 + stride;
  // Check Scanline Advances
  if (y - 1 < 0) upper0 = (void*) 0;
  if (y + 1 >= h) lower0 = (void*) 0;
  // Check X Bound or Current is not blank and Previous a gap
  if (x < 0 || (x + 1 < w && !*(buffer1) && *(buffer1 + 1))) return;

  unsigned int prev1, prev2;
  unsigned int check0, check1, check2;
  // Initialize Checking
  prev1 = prev2 = check0 = 0;
  // Calculate Scanline Blank
  for (int i = x; i >= 0; i--, x--) {
    check0 = *buffer0 ^ *buffer1 >> 1;
    if (check0 < 255) break;

    // Check Scanline Advances
    check1 = upper0 ? (*upper0-- ^ *upper1-- >> 1) : 0;
    check2 = lower0 ? (*lower0-- ^ *lower1-- >> 1) : 0;

    if (prev1 != check1 && check1 > 127) {
      *(stack++) = x;
      *(stack++) = y - 1;
    }

    if (prev2 != check2 && check2 > 127) {
      *(stack++) = x;
      *(stack++) = y + 1;
    }

    // Set Previous Check
    prev1 = check1;
    prev2 = check2;
    // Put Current Mask
    *(buffer0) = 127;
    // Step Buffers
    buffer0--;
    buffer1--;
  }

  // Initialize Checking
  prev1 = prev2 = check0 = 0;
  // Calculate Scanline Gap
  for (int i = x; i >= 0; i--, x--) {
    check0 = *buffer0 & *buffer1;
    if (check0 < 255) break;

    // Check Scanline Advances
    check1 = upper0 ? (*upper0-- & *upper1--) : 0;
    check2 = lower0 ? (*lower0-- & *lower1--) : 0;

    if (prev1 != check1 && check1 > 127) {
      *(stack++) = x;
      *(stack++) = y - 1;
    }

    if (prev2 != check2 && check2 > 127) {
      *(stack++) = x;
      *(stack++) = y + 1;
    }

    // Set Previous Check
    prev1 = check1;
    prev2 = check2;
    // Put Current Mask
    *(buffer0) = 127;
    // Step Buffers
    buffer0--;
    buffer1--;
  }

  // Replace Current Stack
  scan->stack = stack;
  // Check Left Boundary
  if (x < scan->x1)
    scan->x1 = x;
}

// ------------------------
// FLOODFILL SCANLINE PASS1
// ------------------------

void floodfill_dual(floodfill_t* flood) {
  int x, y, w, h;
  // Initial Seed
  x = flood->x;
  y = flood->y;
  // Buffer Size
  w = flood->w;
  h = flood->h;

  printf("starting x: %d, y: %d\n", x, y);

  scanline_t scan;
  // Load Mask Buffer
  scan.buffer0 = flood->buffer0;
  scan.buffer1 = flood->buffer1;
  // Load Mask Metrics
  scan.w = w;
  scan.h = h;
  // Load Mask Stride
  scan.stride = w;
  // Load Stack Pointer
  short* stack0 = flood->stack;
  scan.stack = stack0;

  // Load Stack Initial
  *(scan.stack++) = x;
  *(scan.stack++) = y;
  // Load Scanline AABB
  scan.x1 = scan.x2 = x;
  scan.y1 = scan.y2 = y;

  while (scan.stack > stack0) {
    // Load Coordinates
    scan.y = *(--scan.stack);
    scan.x = *(--scan.stack);

    if (scan.x < 0 || scan.x >= w) {
      printf("error x: %d\n", scan.x);
      continue;
    }

    if (scan.y < 0 || scan.y >= h) {
      printf("error y: %d\n", scan.y);
      continue;
    }

    // Calculate Location Index
    scan.index = scan.y * w + scan.x;
    // Calculate Scanline
    scanline_dual_right(&scan);
    scanline_dual_left(&scan);
  }
}
