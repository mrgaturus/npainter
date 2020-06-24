# Optimized Math for this Software
from math import floor, ceil

type
  # Range Value
  Value* = object
    min, max, pos: float32
  # Color Models
  RGBColor* = object
    r*, g*, b*: float32
  HSVColor* = object
    h*, s*, v*: float32

# --------------------------
# RANGED VALUE INT32|FLOAT32
# --------------------------

proc interval*(value: var Value, min, max: float32) =
  # Set Min and Max Values
  if min < max:
    value.min = min
    value.max = max
  else: # Intercaled
    value.min = max
    value.max = min
  # Clamp Value to Range
  value.pos = clamp(value.pos, 
    value.min, value.max)

proc interval*(value: var Value): float32 =
  value.max - value.min

proc lerp*(value: var Value, t: float32, approx = false) =
  value.pos = (value.max - value.min) * t
  if approx: # Ceil greather than 0.5 or floor
    if value.pos - floor(value.pos) > 0.5:
      value.pos = ceil(value.pos)
    else: value.pos = floor(value.pos)

proc distance*(value: var Value): float32 {.inline.} =
  value.pos / (value.max - value.min)

template toFloat*(value: Value): float32 =
  value.pos # Return Current Value

template toInt*(value: Value): int32 =
  int32(value.pos) # Return Current Value to Int32

# -------------------------
# HSV to RGB and RGB to HSV
# -------------------------

{.emit: """

// [H, S, V, A]
void hsv2rgb(float* rgb, float* hsv) {
  float vv = hsv[2];
  if (hsv[1] == 0)
    rgb[0] = rgb[1] = rgb[2] = vv;
  else {
    short i;
    float aa, bb, cc, h, f;

    h = hsv[0];
    if (h == 1)
      h = 0;
    h *= 6;

    i = floorf(h);
    f = h - i;

    aa = vv * (1 - hsv[1]);
    bb = vv * (1 - (hsv[1] * f));
    cc = vv * (1 - (hsv[1] * (1 - f)));
  
    switch (i) {
      case 0: rgb[0] = vv; rgb[1] = cc; rgb[2] = aa; break;
      case 1: rgb[0] = bb; rgb[1] = vv; rgb[2] = aa; break;
      case 2: rgb[0] = aa; rgb[1] = vv; rgb[2] = cc; break;
      case 3: rgb[0] = aa; rgb[1] = bb; rgb[2] = vv; break;
      case 4: rgb[0] = cc; rgb[1] = aa; rgb[2] = vv; break;
      case 5: rgb[0] = vv; rgb[1] = aa; rgb[2] = bb; break;
    }
  }
}

void rgb2hsv(float* hsv, float* rgb) {
  float max, min, delta;
  // Max Color Channel
  max = (rgb[0] > rgb[1]) ? rgb[0] : rgb[1];
  max = (max > rgb[2]) ? max : rgb[2];
  // Min Color Channel
  min = (rgb[0] < rgb[1]) ? rgb[0] : rgb[1];
  min = (min < rgb[2]) ? min : rgb[2];
  // Delta Max - Min
  delta = max - min;

  hsv[2] = max;
  hsv[1] = (max == 0) ? 0 : delta / max;
  if (hsv[1] == 0)
    hsv[0] = 0;
  else {
    if (rgb[0] == max)
      hsv[0] = (rgb[1] - rgb[2]) / delta;
    else if (rgb[1] == max)
      hsv[0] = 2 + (rgb[2] - rgb[0]) / delta;
    else if (rgb[2] == max)
      hsv[0] = 4 + (rgb[0] - rgb[1]) / delta;
    hsv[0] *= 60;
    if (hsv[0] < 0)
      hsv[0] += 360;
    hsv[0] /= 360;
  }
}

unsigned int rgb2bytes(float* rgb) {
  return 
    (unsigned int) (rgb[0] * 255) |
    (unsigned int) (rgb[1] * 255) << 8 |
    (unsigned int) (rgb[2] * 255) << 16 | 
    0xFF << 24;
}

inline char rgb_cmp(float* a, float* b) {
  return memcmp(a, b, 3) == 0;
}

""".}

# Color Conversion
proc hsv*(color: var RGBColor, hsv: var HSVColor) {.importc: "hsv2rgb".}
proc rgb*(color: var HSVColor, rgb: var RGBColor) {.importc: "rgb2hsv".}
# RGB Comparation and Conversion
proc rgb8*(color: var RGBColor): uint32 {.importc: "rgb2bytes".}
proc `==`*(a, b: var RGBColor): bool {.importc: "rgb_cmp".}

# ---------------------
# FAST MATH C-FUNCTIONS
# ---------------------

{.emit: """

// -- nuklear_math.c
float inv_sqrt(float n) {
  float x2;
  const float threehalfs = 1.5f;
  union {unsigned int i; float f;} conv = {0};
  conv.f = n;
  x2 = n * 0.5f;
  conv.i = 0x5f375A84 - (conv.i >> 1);
  conv.f = conv.f * (threehalfs - (x2 * conv.f * conv.f));
  return conv.f;
}

float fast_sqrt(float n) {
  return n * inv_sqrt(n);
}

// -- Orthogonal Projection for GUI Drawing
void gui_mat4(float* r, float w, float h) {
  r[0] = 2.0 / w;
  r[5] = 2.0 / -h;
  r[12] = -1.0;

  r[10] = r[13] = r[15] = 1.0;
}

""".}

# C to Nim Wrappers to Fast Math C-Functions
proc invSqrt*(n: float32): float32 {.importc: "inv_sqrt".}
proc fastSqrt*(n: float32): float32 {.importc: "fast_sqrt".}
proc guiProjection*(mat: ptr array[16, float32], w,h: float32) {.importc: "gui_mat4".}
