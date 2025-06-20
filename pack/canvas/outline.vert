// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Cristian Camilo Ruiz <mrgaturus>
#version 330 core

// FRAGMENT OUTPUT
out float nAngle;
out vec2 nPos;
// UNIFORM INPUT
layout (location = 0) in ivec2 vPos;
layout (std140) uniform AffineBlock {
  float scale, angle;
  vec2 viewport;
  // Transforms
  layout(row_major) mat3 model;
  layout(column_major) mat4 pro;
} ubo;

// -----------------------
// Outline Vertex Decoding
// -----------------------

float decodeAngle(ivec2 pos) {
  pos &= 0x8000;
  int side =
    pos.x >> 15 |
    pos.y >> 14;

  // Return Decoded Angle Side
  const float slice = 1.5707963267948966;
  return slice * float(side);
}

vec2 decodePosition(ivec2 pos) {
  return vec2(pos & 0x7FFF);
}

// ------------------------
// Outline Vertex Procesing
// ------------------------

void main() {
  nAngle = decodeAngle(vPos);
  vec2 pos = decodePosition(vPos);
  vec3 posModel = ubo.model * vec3(pos, 1.0);
  vec4 posPro = ubo.pro * vec4(posModel.xy, 0.0, 1.0);

  nPos = posModel.xy;
  gl_Position = posPro;
}
