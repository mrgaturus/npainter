// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
#version 330 core

// UNIFORM INPUT
layout (std140) uniform AffineBlock {
  float scale;
  // Transforms
  layout(row_major) mat3 model;
  layout(column_major) mat4 pro;
} ubo;

// VERTEX INPUT
layout (location = 0) in vec2 vPos;
layout (location = 1) in vec2 vTexPos;
// FRAGMENT OUTPUT
out vec2 nTexPos;

void main() {
  const vec2 zeros = vec2(0.0);
  const vec2 rcp = vec2(1.0 / 256.0);
  // Zero Border At Origin of Canvas
  vec2 oPos = min(vPos - 1.0 - ubo.scale, zeros);
  vec2 oUV = (oPos + 1.0) * rcp;

  // UV Position
  nTexPos = vTexPos + oUV;
  // Vertex Projected XY Position With Offset
  vec3 vPosModel = ubo.model * vec3(vPos + oPos + 1.0, 1.0);
  gl_Position = ubo.pro * vec4(vPosModel.xy, 0.0, 1.0);
}
