# Math designed only for this software

# -------------------
# GUI VEC2 MATH
# -------------------

{.emit: """
void uv_normalize(float* r, float w, float h) {
  for (int i = 0; i < 8; i += 2) {
    r[i] /= w;
    r[i + 1] = (h - r[i + 1]) / h;
  }
}
""".}

proc uvNormalize*(buffer: ptr float32, w, h: float32) {.importc: "uv_normalize".}

# -------------------
# Transforms
# -------------------

# -------------------
# Projections
# -------------------

{.emit: """
void mat4_ortho(float* r, float left, float right, float bottom, float top) {
  float dw = right - left;
  float dh = top - bottom;

  r[0] = 2.0 / dw;
  r[5] = 2.0 / dh;
  r[12] = -(right + left) / dw;
  r[13] = -(top + bottom) / dh;

  r[10] = r[15] = 1.0;
}
""".}

proc orthoProjection*(mat: ptr float32, left, right, bottom, top: float32) {.importc: "mat4_ortho".}
