# C Math only for this software

# -------------------
# GUI VEC2 MATH
# -------------------

{.emit: """
// Normalize UV for GUI Root Regions
void uv_normalize(float* r, float w, float h) {
  for (int i = 0; i < 12; i += 2) {
    r[i] /= w; r[i + 1] = (h - r[i + 1]) / h;
  }
}

// Orthogonal Projection for GUI Drawing
void mat4_gui(float* r, float w, float h) {
  r[0] = 2.0 / w;
  r[5] = 2.0 / -h;
  r[12] = -1.0;

  r[10] = r[13] = r[15] = 1.0;
}
""".}

proc uvNormalize*(buffer: ptr array[12, float32], w,h: float32) {.importc: "uv_normalize".}
proc guiProjection*(mat: ptr array[16, float32], w,h: float32) {.importc: "mat4_gui".}
