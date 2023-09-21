// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
#version 330 core

// TILE TEXTURE
uniform sampler2D uTile0;
uniform sampler2D uTile1;
uniform sampler2D uTile2;
uniform sampler2D uTile3;

// UNIFORM INPUT
layout (std140) uniform ScaleBlock {
  float scale;
} ubo;

// INPUT FROM VERTEX
in vec2 nTexPos;

vec2 nearest_aa(vec2 uv) {
  const float rcp = 1.0 / 256;
  // Unnormalize
  uv *= 256.0;
  // Calculate Fractional Part
  vec2 uv_floor = floor(uv + 0.5);
  vec2 uv_fract = uv - uv_floor;

  // Convert UV to Nearest with Antialiasing
  uv_floor += clamp(uv_fract / ubo.scale, -0.5, 0.5);
  return uv_floor * rcp;
}

vec4 sample_pixel(vec2 uv) {
  // UV Tile Positions
  vec2 zero = max(uv - 1.0, 0.0);
  vec2 uv1 = vec2(zero.x, uv.y);
  vec2 uv2 = vec2(uv.x, zero.y);
  // Free Bilinear Cost
  vec4 p0 = texture(uTile0, uv);
  vec4 p1 = texture(uTile1, uv1);
  vec4 p2 = texture(uTile2, uv2);
  vec4 p3 = texture(uTile3, zero);

  const vec2 m = vec2(256.0);
  // Calculate Interpolation
  uv = uv * m - 0.5; uv1 = m - uv;
  uv1 = 1.0 - clamp(uv1, 0.0, 1.0);
  // Zero Border Calculation
  uv2 = 1.0 + min(uv, 0.0);
  float alpha = uv2.x * uv2.y;

  // Apply Interpolation
  p0 = mix(p0, p1, uv1.x);
  p2 = mix(p2, p3, uv1.x);
  p1 = mix(p0, p2, uv1.y);
  // Apply Zero Border
  return p1 * alpha;
}

void main() {
  vec2 uv = nearest_aa(nTexPos);
  gl_FragColor = sample_pixel(uv);
}
