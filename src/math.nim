# C Math only for this software

# -------------------
# GUI VEC2 MATH
# -------------------

{.emit: """
// Normalize UV for GUI Root Regions
void uv_normalize(float* r, float w, float h) {
  for (int i = 0; i < 12; i += 2) {
    r[i] /= w;
    r[i + 1] = (h - r[i + 1]) / h;
  }
}

// Orthogonal Projection with 0 far
void mat4_gui(float* r, float left, float right, float bottom, float top) {
  float dw = right - left;
  float dh = top - bottom;

  r[0] = 2.0 / dw;
  r[5] = 2.0 / dh;
  r[12] = -(right + left) / dw;
  r[13] = -(top + bottom) / dh;

  r[10] = r[15] = 1.0;
}
""".}

proc uvNormalize*(buffer: ptr array[12, float32], w,h: float32) {.importc: "uv_normalize".}
proc guiProjection*(mat: ptr array[16, float32], l,r,b,t: float32) {.importc: "mat4_gui".}
