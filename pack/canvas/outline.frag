// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Cristian Camilo Ruiz <mrgaturus>
#version 330 core

// INPUT FROM VERTEX
in float nAngle;
in vec2 nPos;
// UNIFROM INPUT
uniform float uTime;
uniform float uThick;
layout (std140) uniform BasicBlock {
  float scale, angle;
  vec2 viewport;
} ubo;

// ---------------------
// Outline Stripe Shader
// ---------------------

vec2 rotated(vec2 uv, float angle) {
  float co = cos(angle);
  float si = sin(angle);
  
  mat2 rot = mat2(co, si, -si, co);
  vec2 c = ubo.viewport * 0.5;
  return ((uv - c) * rot) + c;
}

void main() {
  vec2 uv = rotated(nPos, ubo.angle + nAngle);
  uv = sin(uv * uThick + uTime);

  // Output to Screen
  vec3 color = vec3(uv.x);
  gl_FragColor = vec4(color, 1.0);
}
