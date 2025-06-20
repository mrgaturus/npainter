// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Cristian Camilo Ruiz <mrgaturus>
#include "mask.h"

typedef enum {
  sideTop,
  sideRight,
  sideBottom,
  sideLeft,
} mask_side_t;

// -------------------------------
// Combine Mask Operations: Lookup
// -------------------------------

static unsigned short outline_mask_pixel(mask_outline_t* co, int x, int y) {
  int size = 1 << co->log;
  int ox = ((x >= size) - (x < 0));
  int oy = ((y >= size) - (y < 0)) * 3;
  // Lookup Pixel Tile Buffer
  unsigned short *tile = co->tiles[4 + ox + oy];
  if (!tile) return 0;

  // Lookup Pixel Position
  x &= size - 1; y &= size - 1;
  return tile[y * size + x] > 1;
}

static void outline_mask_vertex(mask_outline_t* co, int x, int y, mask_side_t side) {
  int idx = co->count;
  // Store Encoded Vertex
  unsigned short bit0 = ((unsigned short) side & 1) << 15;
  unsigned short bit1 = ((unsigned short) side & 2) << 14;
  co->buffer[idx + 0] = (x + co->ox) | bit0;
  co->buffer[idx + 1] = (y + co->oy) | bit1;
  co->count += 2;
}

// ------------------------------
// Combine Mask Operations: Sides
// ------------------------------

static void outline_mask_sides(mask_outline_t* co, int x, int y) {
  if (outline_mask_pixel(co, x, y) == 0) return;

  // Left Pixel Side
  if (outline_mask_pixel(co, x - 1, y) == 0) {
    outline_mask_vertex(co, x, y + 0, sideLeft);
    outline_mask_vertex(co, x, y + 1, sideLeft);
  }

  // Right Pixel Side
  if (outline_mask_pixel(co, x + 1, y) == 0) {
    outline_mask_vertex(co, x + 1, y + 0, sideRight);
    outline_mask_vertex(co, x + 1, y + 1, sideRight);
  }

  // Top Pixel Side
  if (outline_mask_pixel(co, x, y - 1) == 0) {
    outline_mask_vertex(co, x + 0, y, sideTop);
    outline_mask_vertex(co, x + 1, y, sideTop);
  }

  // Bottom Pixel Side
  if (outline_mask_pixel(co, x, y + 1) == 0) {
    outline_mask_vertex(co, x + 0, y + 1, sideBottom);
    outline_mask_vertex(co, x + 1, y + 1, sideBottom);
  }
}

// --------------------------------
// Combine Mask Operations: Outline
// --------------------------------

void combine_mask_outline(mask_outline_t* co) {
  int size = 1 << co->log;
  // Gather Outline Geometry Lines
  for (int y = 0; y < size; y++)
    for (int x = 0; x < size; x++)
      outline_mask_sides(co, x, y);
}
