# C Math only for this software

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
""".}

proc guiProjection*(mat: ptr array[16, float32], w,h: float32) {.importc: "gui_mat4".}