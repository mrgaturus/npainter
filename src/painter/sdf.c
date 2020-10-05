/**

sdt_dead_reckoning.h v1.0
By Stephan Soller <stephan.soller@helionweb.de>
Implementation of the paper "The dead reckoning signed distance transform" by George J. Grevera
Licensed under the MIT license

DOCUMENTATION

The library only contains one function:

  void sdt_dead_reckoning(unsigned int width, unsigned int height, unsigned char threshold,  const unsigned char* image, float* distance_field);

- `width` and `height` are the dimensions of the input bitmap and output distance field.
- `threshold` defines which pixels of `image` are interpreted as inside or outside. Pixels greater than `threshold` are
  considered inside, everything else as outside.
- `image` is a pointer to the 8 bit image data, one byte per pixel without padding (width * height bytes in total).
- `distance_field` is a pointer to a float buffer with one float per pixel and no padding (width * hight * sizeof(float)
  bytes in total). It is overwritten with the finished distance field. The distance field is returned as floats so you
  can decide for yourself how to map the field into your target format (e.g. an 8 bit image or half-float).

The function mallocs internal buffers. If that turns out to be a bottleneck feel free to move that out of the function.
The source code is quite short and straight forward (even if the math isn't). A look at the paper might help, too.

The function is an implementation of the paper "The dead reckoning signed distance transform" by George J. Grevera. The
paper contains quite nice pseudo-code of the algorithm. The C++ implementation at http://people.sju.edu/~ggrevera/software/distance.tar.gz
(for comparing different algorithms) was also used to fill in some gaps.

This implementation differs from the paper pseudo-code and C++ implementation in three aspects:

- Negative distances are used to designate the inside. The paper does it the other way around.
- The paper implementation has the symmetry under complement property. Meaning you'll get a distance of 0 outside _and
  inside_ of the outline. This creates to a 2px wide region around the outline where the distance is 0. When you try to
  render that distance field in GLSL the local per-pixel derivative in that region becomes 0 (no change across a pixel).
  And that can screw up anti-aliasing in the shaders. Therefore this implementation disables the symmetry under
  complement property as outlined in the paper and pseudo-code. Thanks to that you can simply add or subtract values
  from the distance to shrink or grow the outline.
- The paper implementation requires that the outermost pixels of the mask are black. It also leaves the outermost values
  of the distance field at infinity. sdt_dead_reckoning() instead does the padding internally and returns a proper
  distance in each pixel of the output distance field (at the cost of padding in the internal buffers).

VERSION HISTORY

v1.0  2018-08-31  Initial release

**/

#include <stdlib.h>
#include <math.h>

void sdt_dead_reckoning(unsigned int width, unsigned int height, unsigned char threshold,  const unsigned char* image, float* distance_field) {
  // The internal buffers have a 1px padding around them so we can avoid border checks in the loops below
  unsigned int padded_width = width + 2;
  unsigned int padded_height = height + 2;
  
  // px and py store the corresponding border point for each pixel (just p in the paper, here x and y
  // are separated into px and py).
  int* px = (int*)malloc(padded_width * padded_height * sizeof(px[0]));
  int* py = (int*)malloc(padded_width * padded_height * sizeof(py[0]));
  float* padded_distance_field = (float*)malloc(padded_width * padded_height * sizeof(padded_distance_field[0]));
  
  // Create macros as local shorthands to access the buffers. Push (and later restore) any previous macro definitions so we
  // don't overwrite any macros of the user. The names are similar to the names used in the paper so you can use the pseudo-code
  // in the paper as reference.
  #pragma push_macro("I")
  #pragma push_macro("D")
  #pragma push_macro("PX")
  #pragma push_macro("PY")
  #pragma push_macro("LENGTH")
  // image is unpadded so x and y are in the range 0..width-1 and 0..height-1
  #define I(x, y) (image[(x) + (y) * width] > threshold)
  // The internal buffers are padded x and y are in the range 0..padded_width-1 and 0..padded_height-1
  #define D(x, y) padded_distance_field[(x) + (y) * (padded_width)]
  #define PX(x, y) px[(x) + (y) * padded_width]
  #define PY(x, y) py[(x) + (y) * padded_width]
  // We use a macro instead of the hypotf() function because it's a major performance boost (~26ms down to ~17ms)
  #define LENGTH(x, y) sqrtf((x)*(x) + (y)*(y))
  
  // Initialize internal buffers
  for(unsigned int y = 0; y < padded_height; y++) {
    for(unsigned int x = 0; x < padded_width; x++) {
      D(x, y) = INFINITY;
      PX(x, y) = -1;
      PY(x, y) = -1;
    }
  }
  
  // Initialize immediate interior and exterior elements
  // We iterate over the unpadded image and skip the outermost pixels of it (because we look 1px into each direction)
  for(unsigned int y = 1; y < height-2; y++) {
    for(unsigned int x = 1; x < width-2; x++) {
      int on_immediate_interior_or_exterior = (
        I(x-1, y) != I(x, y)  ||  I(x+1, y) != I(x, y)  ||
        I(x, y-1) != I(x, y)  ||  I(x, y+1) != I(x, y)
      );
      if ( I(x, y) && on_immediate_interior_or_exterior ) {
        // The internal buffers have a 1px padding so we need to add 1 to the coordinates of the unpadded image
        D(x+1, y+1) = 0;
        PX(x+1, y+1) = x+1;
        PY(x+1, y+1) = y+1;
      }
    }
  }
  
  // Horizontal (dx), vertical (dy) and diagonal (dxy) distances between pixels
  const float dx = 1.0, dy = 1.0, dxy = 1.4142135623730950488 /* sqrtf(2) */;
  
  // Perform the first pass
  // We iterate over the padded internal buffers but skip the outermost pixel because we look 1px into each direction
  for(unsigned int y = 1; y < padded_height-1; y++) {
    for(unsigned int x = 1; x < padded_width-1; x++) {
      if ( D(x-1, y-1) + dxy < D(x, y) ) {
        PX(x, y) = PX(x-1, y-1);
        PY(x, y) = PY(x-1, y-1);
        D(x, y) = LENGTH(x - PX(x, y), y - PY(x, y));
      }
      if ( D(x, y-1) + dy < D(x, y) ) {
        PX(x, y) = PX(x, y-1);
        PY(x, y) = PY(x, y-1);
        D(x, y) = LENGTH(x - PX(x, y), y - PY(x, y));
      }
      if ( D(x+1, y-1) + dxy < D(x, y) ) {
        PX(x, y) = PX(x+1, y-1);
        PY(x, y) = PY(x+1, y-1);
        D(x, y) = LENGTH(x - PX(x, y), y - PY(x, y));
      }
      if ( D(x-1, y) + dx < D(x, y) ) {
        PX(x, y) = PX(x-1, y);
        PY(x, y) = PY(x-1, y);
        D(x, y) = LENGTH(x - PX(x, y), y - PY(x, y));
      }
    }
  }
  
  // Perform the final pass
  for(unsigned int y = padded_height-2; y >= 1; y--) {
    for(unsigned int x = padded_width-2; x >= 1; x--) {
      if ( D(x+1, y) + dx < D(x, y) ) {
        PX(x, y) = PX(x+1, y);
        PY(x, y) = PY(x+1, y);
        D(x, y) = LENGTH(x - PX(x, y), y - PY(x, y));
      }
      if ( D(x-1, y+1) + dxy < D(x, y) ) {
        PX(x, y) = PX(x-1, y+1);
        PY(x, y) = PY(x-1, y+1);
        D(x, y) = LENGTH(x - PX(x, y), y - PY(x, y));
      }
      if ( D(x, y+1) + dy < D(x, y) ) {
        PX(x, y) = PX(x, y+1);
        PY(x, y) = PY(x, y+1);
        D(x, y) = LENGTH(x - PX(x, y), y - PY(x, y));
      }
      if ( D(x+1, y+1) + dx < D(x, y) ) {
        PX(x, y) = PX(x+1, y+1);
        PY(x, y) = PY(x+1, y+1);
        D(x, y) = LENGTH(x - PX(x, y), y - PY(x, y));
      }
    }
  }
  
  // Set the proper sign for inside and outside and write the result into the output distance field
  for(unsigned int y = 0; y < height; y++) {
    for(unsigned int x = 0; x < width; x++) {
      float sign = I(x, y) ? -1 : 1;
      distance_field[x + y*width] = D(x+1, y+1) * sign;
    }
  }
  
  // Restore macros and free internal buffers
  #pragma pop_macro("I")
  #pragma pop_macro("D")
  #pragma pop_macro("PX")
  #pragma pop_macro("PY")
  #pragma pop_macro("LENGTH")
  
  free(padded_distance_field);
  free(px);
  free(py);
}

// -----------------------------------------
// Simple SizexSize Image Alpha Minification
// -----------------------------------------

void sdt_minificate(float* distances, int stride, int n) {
  int n_stride, n_x, n_y;
  float x1y1, x2y1, x1y2, x2y2;
  for (; n > 0; n--) {
    n_stride = stride >> 1;
    // Perform Minification
    for (int y = 0; y < n_stride; y++) {
      for (int x = 0; x < n_stride; x++) {
        n_x = x << 1;
        n_y = y << 1;
        // Get 2x2 Distances
        x1y1 = distances[n_y * stride + n_x];
        x2y1 = distances[n_y * stride + (n_x + 1)];
        x1y2 = distances[(n_y + 1) * stride + n_x];
        x2y2 = distances[(n_y + 1) * stride + (n_x + 1)];
        // Store Average of four distances
        distances[y * n_stride + x] = (x1y1 + x2y1 + x1y2 + x2y2) / 4;
      }
    }
    stride = n_stride;
  }
}
