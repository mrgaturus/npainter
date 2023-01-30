// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
#include "binary.h"

// ---------------------------
// Binary Smooth Magic Numbers
// ---------------------------

extern const unsigned char magic_numbers[256];
const char magic_offsets[16] = {
    0x00, 0xFF, 0x01, 0xFF, 
    0x01, 0x00, 0x01, 0x01, 
    0x00, 0x01, 0xFF, 0x01, 
    0xFF, 0x00, 0xFF, 0xFF
};

// ------------------------
// Binary Clamp Calculation
// ------------------------

static unsigned char binary_pixel_clamp(int x, int y, int w, int h) {
  unsigned char mask = 0;
  // Check Lower Bound
  if (x <= 0) mask |= 0xE0;
  if (y <= 0) mask |= 0x83;
  // Check Upper Bound
  if (x >= w - 1) mask |= 0xE;
  if (y >= h - 1) mask |= 0x38;

  return mask;
}

// -------------------------
// Binary Dilate Calculation
// -------------------------

static unsigned short binary_pixel_dilate(binary_smooth_t* smooth, int x, int y, unsigned int check, unsigned char clamp) {
  const int stride = smooth->stride;
  unsigned char* pixel = smooth->binary + (y * stride + x);

  unsigned short mask = 0;
  // Check Top Pixels
  mask = *(pixel) == check;
  // Check Middle Pixels
  pixel += stride;
  mask |= (*(pixel + 1) == check) << 2;
  mask |= (*(pixel - 1) == check) << 6;
  // Check Bottom Pixels
  pixel += stride;
  mask |= (*(pixel) == check) << 4;
  // Remove Border
  mask &= ~clamp;

  // Use All 15 Bits
  mask = -!!mask;
  return mask >> 1;
}

void binary_smooth_dilate(binary_smooth_t* smooth) {
  int x1, y1, x2, y2;
  // Rendering Region
  x1 = smooth->x;
  y1 = smooth->y;
  x2 = x1 + smooth->w;
  y2 = y1 + smooth->h;

  // Magic Buffer Pointer
  unsigned char *magic, *magic_row;
  unsigned char *binary, *binary_row;
  // Gray Buffer Pointer
  unsigned short *gray, *gray_row;

  const int stride = smooth->stride;
  const int rows = smooth->rows;
  // Current Binary Check
  const unsigned int check = smooth->check;
  // Locate Magic Buffer Pointer
  const int index = y1 * stride + x1;
  binary_row = smooth->binary + index;
  gray_row = smooth->gray + index;
  // Current Boundary Clamp
  unsigned char clamp;

  // Iterate Each Pixel
  for (int y = y1; y < y2; y++) {
    binary = binary_row;
    gray = gray_row;

    for (int x = x1; x < x2; x++) {
      // Get Current Clamp And Calculate Pixel
      clamp = binary_pixel_clamp(x, y, stride, rows);
      *gray = (*binary == check) ? 0x7FFF : binary_pixel_dilate(smooth, x, y - 1, check, clamp);

      // Step Binary
      binary++;
      gray++;
    }

    // Step Stride
    binary_row += stride;
    gray_row += stride;
  }
}

// -------------------------
// Binary Lookup Calculation
// -------------------------

static unsigned char binary_pixel_magic(binary_smooth_t* smooth, int x, int y, unsigned char clamp) {
  const int stride = smooth->stride;
  unsigned short* pixel = smooth->gray + (y * stride + x);

  unsigned char mask = 0;
  // Check Top Pixels
  mask |= !!*(pixel);
  mask |= !!*(pixel + 1) << 1;
  mask |= !!*(pixel - 1) << 7;

  // Check Middle Pixels
  pixel += stride;
  mask |= !!*(pixel + 1) << 2;
  mask |= !!*(pixel - 1) << 6;

  pixel += stride;
  // Check Bottom Pixels
  mask |= !!*(pixel) << 4;
  mask |= !!*(pixel + 1) << 3;
  mask |= !!*(pixel - 1) << 5;

  // Return Magic Number With Clamp
  return magic_numbers[mask | clamp];
}

void binary_smooth_magic(binary_smooth_t* smooth) {
  int x1, y1, x2, y2;
  // Rendering Region
  x1 = smooth->x;
  y1 = smooth->y;
  x2 = x1 + smooth->w;
  y2 = y1 + smooth->h;

  // Magic Buffer & Gray Pointer
  unsigned char *binary, *binary_row;
  unsigned short *gray, *gray_row;
  // Buffer Stride Size
  const int stride = smooth->stride;
  const int rows = smooth->rows;
  // Locate Magic Buffer Pointer
  const int index = y1 * stride + x1;
  binary_row = smooth->binary + index;
  gray_row = smooth->gray + index;
  // Binary Selected Check
  const unsigned int check = smooth->check;
  // Current Boundary Clamp
  unsigned char clamp;

  // Iterate Each Pixel
  for (int y = y1; y < y2; y++) {
    binary = binary_row;
    gray = gray_row;

    for (int x = x1; x < x2; x++) {
      if (clamp = (*gray && *binary != check)) {
        clamp = binary_pixel_clamp(x, y, stride, rows);
        clamp = binary_pixel_magic(smooth, x, y - 1, clamp);
      }

      *binary = clamp;
      // Step Binary
      binary++;
      gray++;
    }

    // Step Stride
    binary_row += stride;
    gray_row += stride;
  }
}

// ----------------------
// Binary Smooth Line DDA
// ----------------------

static void binary_pixel_dda(binary_smooth_t* smooth, int x, int y, int check, int offset) {
  offset <<= 1;
  // Load DDA Offsets
  int ox = magic_offsets[offset];
  int oy = magic_offsets[offset + 1];
  // Calculate Buffer Step
  const int stride = smooth->stride;
  int step = stride * oy + ox;
  // DDA Step Count
  int aux, count = 1;

  // Check Count Distance of Line DDA
  aux = stride * (y + oy) + (x + ox);
  unsigned char *magic = smooth->binary + aux;
  if (aux = *magic & 0xC0) {
    while (1) {
      count++;

      if (aux == 0x80 || aux == 0xC0)
        break;

      // Step Magic Buffer
      magic += step;
      aux = *magic & 0xC0;
      if (aux == 0)
        return;
    }

    if (check == aux)
      count = (count + 1) >> 1;
    else if (check != 0x80)
      return;
    else if (count == 2)
      count = (offset & 2) ? 1 : count;

    int dda_step, dda_current;
    // Calculate DDA Size
    if (check == 0x80) {
      dda_step = 0x7FFF0000 / (count + 1);
      dda_current = dda_step;
    } else {
      dda_step = ((int) 0x80010000) / (count + 1);
      dda_current = dda_step + 0x7FFF0000;
    }

    unsigned short pixel, lopixel;
    unsigned short* gray;
    // Locate Buffer Pointers
    aux = y * stride + x;
    gray = smooth->gray + aux;
    magic = smooth->binary + aux;

    while (count > 0) {
      pixel = *gray;
      aux = *magic;
      // Calculate Current Smooth
      lopixel = (unsigned short) (dda_current >> 16);

      if ((aux & 0xC0) == 0xC0) {
        if (pixel == 0x7FFF || lopixel > pixel)
          *gray = lopixel;
      } else if (lopixel < pixel)
        *gray = lopixel;
      
      // Step DDA
      dda_current += dda_step;
      // Step Buffer Pointers
      gray += step;
      magic += step;
      // DDA Finished
      count--;
    }
  }
}

static void binary_pixel_smooth(binary_smooth_t* smooth, int magic, int x, int y) {
  unsigned int check, magic0, magic1;

  check = magic & 0xC0;
  if (check == 0x80 || check == 0xC0) {
    magic0 = (magic >> 3) & 7;
    magic1 = magic & 7;

    binary_pixel_dda(smooth, x, y, check, magic0);
    if (magic0 != magic1)
      binary_pixel_dda(smooth, x, y, check, magic1);
  }
}

void binary_smooth_apply(binary_smooth_t* smooth) {
  int x1, y1, x2, y2;
  // Rendering Region
  x1 = smooth->x;
  y1 = smooth->y;
  x2 = x1 + smooth->w;
  y2 = y1 + smooth->h;

  unsigned char *magic, *magic_row;
  const int stride = smooth->stride;
  // Locate Buffer Pointer
  const int index = y1 * stride + x1;
  magic_row = smooth->binary + index;

  // Iterate Each Pixel
  for (int y = y1; y < y2; y++) {
    magic = magic_row;

    for (int x = x1; x < x2; x++) {
      binary_pixel_smooth(smooth, *magic, x, y);
      // Step Binary
      magic++;
    }

    // Step Stride
    magic_row += stride;
  }
}
