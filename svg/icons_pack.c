#include <stdio.h>
#include <string.h>

#include "cairo.h"
#include "librsvg/rsvg.h"

#define SUCCESS_OUTPUT 0
#define INVALID_ARGS 1
#define INVALID_SVG 2
#define INVALID_OUTPUT 3

int main (int argc, char **argv) {
  // Check arguments
  if (argc < 4) {
    printf("usage: %s <output> <size> icon1.svg icon2.svg, ...\n", argv[0]);
    return INVALID_ARGS;
  }
  // Selected Size
  int size, count, stride;
  // SVG Dimensions
  int has_w, has_h;
  RsvgLength width, height;
  // Cairo & RSVG
  cairo_t* cr;
  cairo_surface_t* surface;
  RsvgHandle* rsvg;
  // Get Selected Dimensions
  if (sscanf(argv[2], "%d", &size) == 0) {
    printf("argument error: <size> must be a number \n");
    return INVALID_ARGS;
  }
  count = argc - 3;
  stride = size * size;
  // Create an image cairo surface
  surface = cairo_image_surface_create(CAIRO_FORMAT_A8, size, size);
  cr = cairo_create(surface); // Create a Cairo Surface
  // Alloc Icons Data on a Buffer
  unsigned char* icons = malloc(stride * count);
  unsigned char* cursor = icons;
  // Render Each SVG File
  for (int i = 3; i < argc; i++, cursor += stride) {
    // Load SVG File
    rsvg = rsvg_handle_new_from_file(argv[i], NULL);
    if (rsvg == NULL) {
      printf("failed loading svg file: %s, aborting\n", argv[i]);
      return INVALID_SVG;
    }
    // Set DPI to 96 (Other DPIs are hard to handle)
    rsvg_handle_set_dpi(rsvg, 96);
    // Get SVG Dimensions and Render it if is valid
    rsvg_handle_get_intrinsic_dimensions(rsvg, &has_w, &width, &has_h, &height, NULL, NULL);
    if (has_w && has_h && width.unit == RSVG_UNIT_PX && height.unit == RSVG_UNIT_PX) {
      // Ajust Cairo Context to selected dimensions
      cairo_identity_matrix(cr);
      cairo_scale(cr, size / width.length, size / height.length);
      // Clear Current cairo surface
      cairo_set_source_rgba(cr, 0, 0, 0, 0);
      cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
      cairo_paint(cr);
      // Render it to cairo surface and then copy to buffer
      if (!rsvg_handle_render_cairo(rsvg, cr)) {
        printf("failed rendering svg file: %s, aborting\n", argv[i]);
        return INVALID_SVG;
      }
      // Flush Pending Commands
      cairo_surface_flush(surface);
    } else {
      printf("svg file: %s must be in px dimensions, aborting\n", argv[i]);
      return INVALID_SVG;
    }
    // Copy Cairo Surface to Buffer
    memcpy(cursor, cairo_image_surface_get_data(surface), stride);
    // Free current RSVG Handle
    g_object_unref(rsvg);
  }
  // Save Icons and Header to stdout
  FILE* output = fopen(argv[1], "w");
  if (output) {
    // Save Header and Buffer
    int header[2] = {size, count};
    fwrite(header, sizeof(int), 2, output);
    fwrite(icons, sizeof(char), stride * count, output);
    // Close File
    fclose(output);
  } else {
      printf("error saving file: %s\n", argv[1]);
      return INVALID_OUTPUT;
  }
  // Free Data
  free(icons);
  // Free Cairo
  cairo_destroy(cr);
  cairo_surface_destroy(surface);
  // Success Executed
  return SUCCESS_OUTPUT;
}
