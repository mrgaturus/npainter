// ------------------------------
// PAINTER FUNDAMENTAL TRANSFORMS
// ------------------------------

// <- [Translate][Rotate][Scale] <-
void mat3_brush(float* m, float x, float y, float s, float o) {
  float cs, ss;
  cs = cos(o) * s;
  ss = sin(o) * s;
  // Set Matrix Transform
  m[0] = cs; m[1] = -ss; m[2] = x;
  m[3] = ss; m[4] =  cs; m[5] = y;
  // Transform Place Holder
  m[6] = 0; m[7] = 0; m[8] = 1;
}

// <- [Translate][Translate -Center][Rotate][Scale][Translate Center] <-
void mat3_canvas(float* m, float cx, float cy, float x, float y, float s, float o) {
  // Rotation Precalculated
  float co, so, cs, ss;
  co = cos(o); so = sin(o);
  cs = co * s; ss = so * s;
  // Rotation Transform
  m[0] = cs; m[1] = -ss;
  m[3] = ss; m[4] = cs;
  // Translation with Center Transform
  m[2] = (so * cy - co * cx) * s + (x + cx);
  m[5] = -(co * cy + so * cx) * s + (y + cy);
  // Transform Place Holder
  m[6] = 0; m[7] = 0; m[8] = 1;
}

// -> [Translate][Translate -Center][Rotate][Scale][Translate Center] ->
void mat3_canvas_inv(float* m, float cx, float cy, float x, float y, float s, float o) {
  // Inverted Scale
  float os = s;
  s = 1 / s;
  // Rotation Precalculated
  float co, so, cs, ss;
  co = cos(o); so = sin(o);
  cs = co * s; ss = so * s;
  // Rotation Transform
  m[0] = cs; m[1] = ss;
  m[3] = -ss; m[4] = cs;
  // Translation with Center Transform
  m[2] = ( cx * os - co * (x + cx) - so * (y + cy) ) * s;
  m[5] = ( cy * os + so * (x + cx) - co * (y + cy) ) * s;
  // Transform Place Holder
  m[6] = 0; m[7] = 0; m[8] = 1;
}

// [Matrix][Vector3] Multiplication
void vec2_mat3(float* v, float* m) {
  float x = v[0], y = v[1];
  // Matrix-Vector Multiplication
  v[0] = (x * m[0]) + (y * m[1]) + m[2];
  v[1] = (x * m[3]) + (y * m[4]) + m[5];
}
