#version 330 core

// BRUSH TEXTURE & MASK
// uniform sampler2D uTile;
// uniform sampler2D uMask;
// INPUT FROM VERTEX
in vec2 nTexPos;

float circle(vec2 uv) {
	float d = length(uv - 0.5) + 0.005, wd = fwidth(d);
  return smoothstep(0.5 + wd, 0.5 - wd, d);
}

void main() {
  float alpha = circle(nTexPos);
  gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0) * alpha;
}