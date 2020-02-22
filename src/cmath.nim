# C Math only for this software

# Import SSE Intrinsics
{.emit: "#include <xmmintrin.h>".}

# -------------------
# GUI VEC2 MATH
# -------------------

{.emit: """
// Orthogonal Projection for GUI Drawing
void gui_mat4(float* r, float w, float h) {
  r[0] = 2.0 / w;
  r[5] = 2.0 / -h;
  r[12] = -1.0;

  r[10] = r[13] = r[15] = 1.0;
}

// Normalize Coordinates [X1,X2,Y1,Y2] / [W,W,H,H]
// dest is 16-byte unaligned, but is better than many divisions
void gui_normalize(float* dest, float x1, float x2, float y1, float y2, float w, float h) {
  _mm_storeu_ps(dest, _mm_div_ps(
      _mm_set_ps(y1+y2, y1, x1+x2, x1),
      _mm_set_ps(h, h, w, w)
    )
  );
}
""".}

proc guiProjection*(mat: ptr array[16, float32], w,h: float32) {.importc: "gui_mat4".}
proc guiNormalize*(dest: pointer, x1,x2,y1,y2, w,h: float32) {.importc: "gui_normalize".}