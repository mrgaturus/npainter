# Math only for this software
from math import floor, ceil
# --------------------------
# RANGED VALUE INT32|FLOAT32
# --------------------------

type
  Value* = object
    min, max, pos: float32

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

# ----------------------
# FAST SQRT AND INV SQRT
# ----------------------

{.emit: """
// From nuklear_math.c
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
""".}

# Fast Math for Simple usages
proc invertedSqrt*(n: float32): float32 {.importc: "inv_sqrt".} # Fast Inverted Sqrt
proc fastSqrt*(n: float32): float32 {.importc: "fast_sqrt".}

# --------------
# GUI PROJECTION
# --------------

{.emit: """
// Orthogonal Projection for GUI Drawing
void gui_mat4(float* r, float w, float h) {
  r[0] = 2.0 / w;
  r[5] = 2.0 / -h;
  r[12] = -1.0;

  r[10] = r[13] = r[15] = 1.0;
}
""".}

# GUI Vector and Matrix Math
proc guiProjection*(mat: ptr array[16, float32], w,h: float32) {.importc: "gui_mat4".}
