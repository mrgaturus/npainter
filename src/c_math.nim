# Math only for this software
from math import floor, ceil

type
  Value* = object
    min, max, pos: float32
  RGBColor* = uint32
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
# HSV-RGBA / RGBA-HSV PROCS
# -------------------------

proc hsv*(rgb: RGBColor): HSVColor =
  let # Get Colors
    r = cast[byte](rgb)
    g = cast[byte](rgb shr 8)
    b = cast[byte](rgb shr 16)
  let # Get Min, Max, Delta
    max = max(max(r, g), b)
    min = min(min(r, g), b)
    delta = float32(max - min)
  if max != 0: # Compute HSV
    result.v = # Value
      max.float32 / 255
    result.s = # Saturation
      delta / max.float32
    result.h = # Hue Calculation
      if r == max: float32(g - b) / delta
      elif g == max: 2 + float32(b - r) / delta
      elif b == max: 4 + float32(r - g) / delta
      else: 0 # Invalid RGBA
    result.h *= 60;
    if result.h < 0:
      result.h += 360
    result.h /= 360

proc rgb*(hsv: var HSVColor): RGBColor =
  if hsv.s == 0: # Grayscale
    let v = byte(hsv.v * 255)
    result = v or (v shl 8) or (v shl 16)
  else: # Colored
    var h = hsv.h
    # Get Hue Sector
    if h == 1: h = 0
    else: h *= 6
    # Calculate RGBA
    let # Round Sector
      i = floor(h)
      f = h - i
      # Calculate Compotents
      vv = uint32 hsv.v * 255
      aa = uint32 hsv.v * (1 - hsv.s) * 255
      bb = uint32 hsv.v * (1 - hsv.s * f) * 255
      cc = uint32 hsv.v * (1 - hsv.s * (1 - f)) * 255
    result = # Convert to RGB888
      case byte(i): # Guaranted no oveflow
      of 0: vv or (cc shl 8) or (aa shl 16)
      of 1: bb or (vv shl 8) or (aa shl 16)
      of 2: aa or (vv shl 8) or (cc shl 16)
      of 3: aa or (bb shl 8) or (vv shl 16)
      of 4: cc or (aa shl 8) or (vv shl 16)
      of 5: vv or (aa shl 8) or (bb shl 16)
      else: 0 # Invalid HSV Color

# ----------------------
# FAST SQRT AND INV SQRT
# ----------------------

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

# Fast Math for Simple usages
proc invertedSqrt*(n: float32): float32 {.importc: "inv_sqrt".} # Fast Inverted Sqrt
proc fastSqrt*(n: float32): float32 {.importc: "fast_sqrt".}
# GUI Projection
proc guiProjection*(mat: ptr array[16, float32], w,h: float32) {.importc: "gui_mat4".}
