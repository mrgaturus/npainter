// -----------------------------
// PAINTER FUNDAMENTAL TRANSFORM
// -----------------------------

// <- [Translate][Rotate][Scale] <-
void mat3_painter(float* m, float x, float y, float s, float o) {
  float cs, ss;
  cs = cos(o) * s;
  ss = sin(o) * s;
  // Set Matrix Transform
  m[0] = cs; m[1] = -ss; m[2] = x;
  m[3] = ss; m[4] =  cs; m[5] = y;
  // Transform Place Holder
  m[6] = m[7] = 0; m[8] = 1;
}

// -> [Translate][Rotate][Scale] ->
void mat3_painter_inv(float* m, float x, float y, float s, float o) {
  s = 1 / s;
  // Cos & Sin Cache
  float co, so, cs, ss;
  co = cos(o); so = sin(o);
  cs = co * s; ss = so * s;
  // Set Matrix Transform
  m[0] = cs; m[1] = ss;
  m[3] = -ss; m[4] = cs;
  // Set Heavy Calculation Part
  m[2] = -(co * x + so * y) * s;
  m[5] = (so * x - co * y) * s;
  // Transform Place Holder
  m[6] = m[7] = 0; m[8] = 1;
}

// [Matrix][Vector3] Multiplication
void vec2_mat3(float* v, float* m) {
  float x = v[0], y = v[1];
  // Matrix-Vector Multiplication
  v[0] = (x * m[0]) + (y * m[1]) + m[2];
  v[1] = (x * m[3]) + (y * m[4]) + m[5];
}