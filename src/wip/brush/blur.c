#include "brush.h"

// -----------------------
// BRUSH BLUR IMAGE REGION
// -----------------------

typedef struct {
  // Region Pointer With Offset
  short *buffer, *mask;
  // Region Stride
  int s_buffer, s_mask;
  // Region Size
  int w, h;
} blur_region_t;

typedef struct {
  // Convolve Area
  int x1, x2, y1, y2;
} blur_convolve_t;

// -----------------------------
// BRUSH BLUR CONVOLUTION WEIGHT
// -----------------------------

static unsigned int _mm_linear_65535(const int s, unsigned int x) {
  const int c = (int) x;
  if (c < 0) x = -c;

  x >>= s;
  // Linear Weight
  if (x > 65536) x = 65536;
  x = (65536 - x) >> s;

  // Return Weight
  return x;
}


static unsigned int _mm_quadric_65535(unsigned int x) {
  const int c = (int) x;
  if (c < 0) x = -c;

  // x * 0.75
  x -= x >> 2;

  // Calculate Quadric Weight
  if (x < 32767) {
    x = (x * x + 65535) >> 16;
    x = 49151 - x;
  } else if (x < 98302) {
    x = 98302 - x;
    x = (x * x + 65535) >> 17;
  } else x = 0;

  // x * 0.75
  x -= x >> 2;

  // Return Weight
  return x;
}

// ------------------------
// BRUSH BLUR REGION OFFSET
// ------------------------

#define CLAMP(x, a, b) (x < a) ? a : ((x > b) ? b : x)

static void brush_blur_locate(blur_region_t* r, blur_convolve_t* c, int u0, int v0, int size) {
  const int w = r->w;
  const int h = r->h;

  // Locate Pixel
  u0 >>= 16;
  v0 >>= 16;
  // Locate Convolution Offset
  const int o0 = (size >> 1) - 1;

  int stride;
  // Convolution Region
  int x1 = u0 - o0;
  int y1 = v0 - o0;
  int x2 = x1 + size;
  int y2 = y1 + size;

  // Clamp Convolution Region
  x1 = CLAMP(x1, 0, w);
  x2 = CLAMP(x2, 0, w);
  y1 = CLAMP(y1, 0, h);
  y2 = CLAMP(y2, 0, h);

  stride = (y1 * r->s_mask + x1);
  // Apply Offset to Buffer
  r->mask += stride;
  r->buffer += stride << 2;

  // Convolve Area
  c->x1 = x1 - u0;
  c->y1 = y1 - v0;
  c->x2 = x2 - u0;
  c->y2 = y2 - v0;

  stride = x2 - x1;
  // Ajust Stride to Size
  r->s_mask -= stride;
  r->s_buffer -= stride << 2;
}

// ------------------------------
// BRUSH BLUR SCALING CONVOLUTION
// ------------------------------

static __m128i brush_blur_linear(blur_region_t r, const int s, int u, int v) {
  // Initial Position
  const int u0 = u & ~0xFFFF;
  const int v0 = v & ~0xFFFF;

  // Convolution Area Size
  const int size = 1 << (s + 1);
  const int scaler = 24 - s;

  blur_convolve_t c;
  // Locate Convolution Region
  brush_blur_locate(&r, &c, u0, v0, size);

  __m128i xmm0, xmm1, xmm2;
  // Initialize Pixel Accumulator
  xmm0 = _mm_setzero_si128();
  int count = 0, vj, ui;
  unsigned int w, w_row;

  for (int j = c.y1; j < c.y2; j++) {
    vj = v - v0 - (j << 16);
    w_row = _mm_linear_65535(s, vj);

    for (int i = c.x1; i < c.x2; i++) {
      ui = u - u0 - (i << 16);
      w = _mm_linear_65535(s, ui);
      // Calculate Y * X Weight
      w = (w_row * w) >> scaler;

      if (w > 0 && *r.mask) {
        // Load Current Weight Pixel
        xmm1 = _mm_loadl_epi64((__m128i*) r.buffer);
        xmm1 = _mm_cvtepu16_epi32(xmm1);
        // Load Four Weights
        xmm2 = _mm_cvtsi32_si128(w);
        xmm2 = _mm_shuffle_epi32(xmm2, 0);

        // Count Current Pixel
        xmm1 = _mm_mullo_epi32(xmm1, xmm2);
        xmm0 = _mm_add_epi32(xmm0, xmm1);
        // Count Current Weight
        count += w;
      }

      // Step Pixel
      r.mask++;
      r.buffer += 4;
    }

    // Step Stride
    r.mask += r.s_mask;
    r.buffer += r.s_buffer;
  }

  if (count > 0) {
    __m128 rcp, avg;
    // Load Four Counts
    xmm1 = _mm_cvtsi32_si128(count);
    xmm1 = _mm_shuffle_epi32(xmm1, 0);
    // Convert to Float
    avg = _mm_cvtepi32_ps(xmm0);
    rcp = _mm_cvtepi32_ps(xmm1);
    // Apply Division
    rcp = _mm_rcp_ps(rcp);
    avg = _mm_mul_ps(avg, rcp);

    // Convert Back to Integer
    xmm0 = _mm_cvtps_epi32(avg);
    xmm0 = _mm_srli_epi32(xmm0, 1);
  } else if (count == 0) {
    xmm0 = _mm_cmpeq_epi32(xmm0, xmm0);
  }

  return xmm0;
}

static __m128i brush_blur_quadric(blur_region_t r, int u, int v) {
  // Initial Position
  const int u0 = u & ~0xFFFF;
  const int v0 = v & ~0xFFFF;

  blur_convolve_t c;
  // Locate Convolution Region
  brush_blur_locate(&r, &c, u0, v0, 4);

  __m128i xmm0, xmm1, xmm2;
  // Initialize Pixel Accumulator
  xmm0 = _mm_setzero_si128();
  int count = 0, vj, ui;
  unsigned int w, w_row;
  // Initialize Ones SIMD Mask
  const __m128i ones = _mm_cmpeq_epi32(xmm0, xmm0);

  for (int j = c.y1; j < c.y2; j++) {
    vj = v - v0 - (j << 16);
    w_row = _mm_quadric_65535(vj);

    for (int i = c.x1; i < c.x2; i++) {
      ui = u - u0 - (i << 16);
      w = _mm_quadric_65535(ui);
      // Calculate Y * X Weight
      w = (w_row * w + 65536) >> 24;

      if (w > 0) {
        // Load Current Weight Pixel
        xmm1 = _mm_loadl_epi64((__m128i*) r.buffer);
        xmm1 = _mm_cvtepi16_epi32(xmm1);

        if (_mm_testc_si128(xmm1, ones) == 0) {
          // Load Four Weights
          xmm2 = _mm_cvtsi32_si128(w);
          xmm2 = _mm_shuffle_epi32(xmm2, 0);

          // Count Current Pixel
          xmm1 = _mm_mullo_epi32(xmm1, xmm2);
          xmm0 = _mm_add_epi32(xmm0, xmm1);
          // Count Current Weight
          count += w;
        }
      }

      // Step Pixel
      r.buffer += 4;
    }

    // Step Stride
    r.buffer += r.s_buffer;
  }

  if (count > 0) {
    __m128 rcp, avg;
    // Load Four Counts
    xmm1 = _mm_cvtsi32_si128(count);
    xmm1 = _mm_shuffle_epi32(xmm1, 0);
    // Convert to Float
    avg = _mm_cvtepi32_ps(xmm0);
    rcp = _mm_cvtepi32_ps(xmm1);
    // Apply Division
    rcp = _mm_rcp_ps(rcp);
    avg = _mm_mul_ps(avg, rcp);

    // Convert Back to Integer
    xmm0 = _mm_cvtps_epi32(avg);
  }

  return xmm0;
}

// -----------------------------
// BRUSH BLUR DOWNSCALE CONVOLVE
// -----------------------------

void brush_blur_first(brush_render_t* render) {
  // Check Region Size
  if (render->w <= 0 || render->h <= 0)
    return; // Nothing to Do

  int x1, x2, y1, y2;
  // Blur Opaque Pointer
  brush_blur_t* blur;
  blur_region_t region;
  // Load Blur Opaque Pointer
  blur = (brush_blur_t*) render->opaque;
  // Locate Buffer Offset
  x1 = render->x - blur->x;
  y1 = render->y - blur->y;

  int stride = render->canvas->stride;
  // Brush Shape Mask Stride
  region.s_mask = stride;
  region.s_buffer = stride << 2;
  // Define Region Dimensions
  region.w = blur->w;
  region.h = blur->h;

  // Load Pixel Buffer Pointer
  region.mask = render->canvas->buffer0;
  region.buffer = render->canvas->dst;

  stride = (y1 * stride + x1);
  // Locate Destination Pointer
  region.mask += stride;
  region.buffer += stride << 2;

  const int fx = blur->down_fx;
  const int fy = blur->down_fy;
  // Locate Region Position
  x1 = blur->x;
  y1 = blur->y;
  x2 = x1 + render->w;
  y2 = y1 + render->h;
  // Locate Position to Auxiliar Buffer
  x1 = (x1 * blur->sw) / region.w;
  y1 = (y1 * blur->sh) / region.h;
  x2 = (x2 * blur->sw) / region.w;
  y2 = (y2 * blur->sh) / region.h;

  int level, yy, xx, oo;
  // Load Current Level
  level = render->alpha;
  // Load Current Offset
  oo = blur->offset;
  // Locate Fixlinear Positions
  yy = y1 * fy + oo;
  xx = x1 * fx + oo;

  __m128i xmm0; short *aux_y, *aux_x; 
  // Load Auxiliar Buffer Pointer
  aux_y = render->canvas->buffer1;
  // Change Stride to Auxiliar
  stride = blur->sw;
  // Locate Auxuliar Buffer Pointer
  aux_y += (y1 * stride + x1) << 2;
  // Change Stride to Auxiliar Pixels
  stride <<= 2;

  for (int y = y1; y < y2; y++) {
    aux_x = aux_y;
    oo = xx;

    for (int x = x1; x < x2; x++) {
      // Calculate Average of Current Downscaled Pixel
      xmm0 = brush_blur_linear(region, level, oo, yy);
      // Pack Pixel and Store
      xmm0 = _mm_packs_epi32(xmm0, xmm0);
      _mm_storel_epi64((__m128i*) aux_x, xmm0);

      aux_x += 4;
      // Step X Fixlinear
      oo += fx;
    }

    aux_y += stride;
    // Step Y Fixlinear
    yy += fy;
  }
}

// ---------------------------
// BRUSH BLUR UPSCALE CONVOLVE
// ---------------------------

void brush_blur_blend(brush_render_t* render) {
  // Check Region Size
  if (render->w <= 0 || render->h <= 0)
    return; // Nothing to Do

  int x1, x2, y1, y2;
  // Render Region
  x1 = render->x;
  y1 = render->y;
  x2 = x1 + render->w;
  y2 = y1 + render->h;

  int s_shape, s_dst;
  // Brush Shape Mask Stride
  s_shape = render->canvas->stride;
  // Brush Destination Stride
  s_dst = s_shape << 2;

  short *dst_y, *dst_x;
  // Load Pixel Buffer Pointer
  dst_y = render->canvas->dst;
  // Locate Destination Pointer to Render Position
  dst_y += (render->y * s_shape + render->x) << 2;

  brush_blur_t* blur;
  blur_region_t region;
  // Load Blur & Canvas Pointer
  blur = (brush_blur_t*) render->opaque;

  int stride = render->canvas->stride;
  // Load Pixel Buffer Pointer
  region.buffer = render->canvas->buffer1;
  // Define Region Dimensions
  region.w = blur->sw;
  region.h = blur->sh;
  // Define Region Buffer Stride
  region.s_mask = region.w;
  region.s_buffer = region.w << 2;

  int yy, xx, row_xx;
  // Define Fixlinear Steps
  const int fx = blur->up_fx;
  const int fy = blur->up_fy;
  // Define Fixlinear Position
  xx = blur->x * fx - 32768;
  yy = blur->y * fy - 32768;

  unsigned short *sh_y, *sh_x, sh;
  // Load Mask Buffer Pointer
  sh_y = render->canvas->buffer0;
  // Locate Shape Pointer to Render Position
  sh_y += (render->y * s_shape) + render->x;

  __m128i color, alpha, xmm0, xmm1;
  // Load Unpacked Color Ones
  const __m128i one = _mm_set1_epi32(65535);

  // Apply Blending Mode
  for (int y = y1; y < y2; y++) {
    sh_x = sh_y;
    dst_x = dst_y;
    row_xx = xx;

    for (int x = x1; x < x2; x++) {
      // Check if is not zero
      if (sh = *sh_x) {
        alpha = _mm_cvtsi32_si128(sh);
        alpha = _mm_shuffle_epi32(alpha, 0);
        // Load Destination Pixel
        xmm0 = _mm_loadl_epi64((__m128i*) dst_x);
        xmm0 = _mm_cvtepu16_epi32(xmm0);
        xmm0 = _mm_srli_epi32(xmm0, 1);
        // Load Color From Blur Buffer
        color = brush_blur_quadric(region, row_xx, yy);

        // Interpolate To Color
        xmm1 = _mm_sub_epi32(one, alpha);
        xmm0 = _mm_mullo_epi32(xmm0, xmm1);
        xmm1 = _mm_mullo_epi32(color, alpha);
        xmm0 = _mm_add_epi32(xmm0, xmm1);
        // Ajust Color Fix16
        xmm0 = _mm_add_epi32(xmm0, one);
        xmm0 = _mm_srli_epi32(xmm0, 15);

        // Pack to Fix16 and Store
        xmm0 = _mm_packus_epi32(xmm0, xmm0);
        _mm_storel_epi64((__m128i*) dst_x, xmm0);
      }
      // Step Shape & Color
      sh_x++; dst_x += 4;
      // Step X Fixlinear
      row_xx += fx;
    }

    // Step Stride
    sh_y += s_shape;
    dst_y += s_dst;
    // Step Y Fixlinear
    yy += fy;
  }
}
