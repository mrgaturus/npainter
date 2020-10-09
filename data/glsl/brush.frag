#version 330 core

// BRUSH TEXTURE & MASK
// uniform sampler2D uTile;
uniform sampler2D uMask;
uniform float uScale;
// INPUT FROM VERTEX
in vec2 nTexPos;

float circle(vec2 uv) {
	float d = length(uv - 0.5) + 0.005, wd = fwidth(uv.x);
  //return smoothstep(0.5 + wd, 0.5 - wd, d);
  return wd;
}

void main() {
  //float alpha = texture(uMask, nTexPos).r;
  //float alpha = 1 - length(nTexPos - 0.5);
  // gamma = (2 * 1.4142) / (scale / 1024)
  // gamma = ( 2 * 1.4142 / 1024 ) / scale
  //float gamma = 0.003 / uScale;
  //alpha = smoothstep(0.5, 0.75 + gamma, alpha);
  gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0) * nTexPos.x;
}