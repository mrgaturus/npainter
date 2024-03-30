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
  uv = m - uv * m + 0.5;
  uv = 1.0 - clamp(uv, 0.0, 1.0);

  // Apply Interpolation
  p0 = mix(p0, p1, uv.x);
  p2 = mix(p2, p3, uv.x);
  p1 = mix(p0, p2, uv.y);
  // Return Interpolated Pixel
  return p1;
}

vec4 supersample_pixel(vec2 uv) {
  const float s = 1.0 / 256.0;
  const float rcp = 1.0 / 4.0;
  // Calculate Supersample Offset
  float offset = ubo.scale * s - s;
  offset = min(offset + offset, s);

  // Calculate UV Positions
  vec2 bias = uv + vec2(offset);
  vec2 uv1 = vec2(bias.x, uv.y);
  vec2 uv2 = vec2(uv.x, bias.y);
  // Sample Positions
  vec4 p0 = sample_pixel(uv);
  vec4 p1 = sample_pixel(uv1);
  vec4 p2 = sample_pixel(uv2);
  vec4 p3 = sample_pixel(bias);

  // Return Averaged Pixel
  return (p0 + p1 + p2 + p3) * rcp;
}

void main() {
  vec4 pixel = supersample_pixel(nTexPos);
  // Calculate Antialiasing Border
  vec2 border = (nTexPos * 256.0 - 0.5) / ubo.scale;
  border = 1.0 + min(border, 0.0);
  // Apply Antialiasing Border
  float alpha = border.x * border.y;
  gl_FragColor = pixel * alpha;
}
