// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2022 Cristian Camilo Ruiz <mrgaturus>
#include "binary.h"

// --------------------------
// Chamfer Distance Preparing
// --------------------------

void distance_prepare(distance_t* chamfer) {
  int x1, y1, x2, y2;
  // Locate Position
  x1 = chamfer->x;
  y1 = chamfer->y;
  x2 = x1 + chamfer->w;
  y2 = y1 + chamfer->h;

  int stride, index;
  // Buffer Strides
  stride = chamfer->stride;
  index = y1 * stride + x1;
  // Buffer Pointers
  unsigned char *buffer_row, *buffer;
  unsigned int *distances_row, *distances;
  unsigned int *positions_row, *positions;
  // Locate Buffer Pointers
  buffer_row = chamfer->src + index;
  distances_row = chamfer->distances + index;
  positions_row = chamfer->positions + index;
  
  const unsigned int infinite = 2147483647;
  const unsigned int check = chamfer->check;
  // Test Auxiliar Variable
  unsigned int test;

  // Initialize Buffer Data
  for (int y = y1; y < y2; y++) {
    buffer = buffer_row;
    distances = distances_row;
    positions = positions_row;

    for (int x = x1; x < x2; x++) {
      test = (*buffer == check) ? infinite : 0;
      // Store Values
      *(distances) = test;
      *(positions) = 0;

      // Step Buffer Pixels
      buffer++;
      distances++;
      positions++;
    }

    // Step Buffer Rows
    buffer_row += stride;
    distances_row += stride;
    positions_row += stride;
  }
}

void distance_convert(distance_t* chamfer) {
  int x1, y1, x2, y2;
  // Locate Position
  x1 = chamfer->x;
  y1 = chamfer->y;
  x2 = x1 + chamfer->w;
  y2 = y1 + chamfer->h;

  int stride, index;
  // Buffer Strides
  stride = chamfer->stride;
  index = y1 * stride + x1;
  // Buffer Pointers
  unsigned char *buffer_row, *buffer;
  unsigned int *distances_row, *distances;
  // Locate Buffer Pointers
  buffer_row = chamfer->dst + index;
  distances_row = chamfer->distances + index;
  
  // Check Distance Test
  unsigned int check = chamfer->threshold;
  // Test Auxiliar Variable
  unsigned int test;

  // Initialize Buffer Data
  for (int y = y1; y < y2; y++) {
    buffer = buffer_row;
    distances = distances_row;

    for (int x = x1; x < x2; x++) {
      test = (*distances < check) ? 255 : 0;
      // Store Values
      *(buffer) = test;

      // Step Buffer Pixels
      buffer++;
      distances++;
    }

    // Step Buffer Rows
    buffer_row += stride;
    distances_row += stride;
  }
}
