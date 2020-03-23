# C Math only for this software

# -------------------
# GUI VEC2 MATH
# -------------------

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

// Orthogonal Projection for GUI Drawing
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
# GUI Vector and Matrix Math
proc guiProjection*(mat: ptr array[16, float32], w,h: float32) {.importc: "gui_mat4".}
