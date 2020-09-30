#version 330 core

// BRUSH TEXTURE & MASK
// uniform sampler2D uTile;
// uniform sampler2D uMask;
// INPUT FROM VERTEX
in vec2 nTexPos;
/* DITHERING GRANULARITY
const float NOISE = 0.5/255.0;

float random(vec2 coords) { // Simple Random from shader-tutorial.dev
   return fract(sin(dot(coords.xy, vec2(12.9898,78.233))) * 43758.5453);
}
*/
float circle(vec2 uv) {
	float d = length(uv - 0.5) + 0.005;
  float wd = fwidth(d);
  return smoothstep(0.5 + wd, wd, d);
}

void main() {
  float alpha = circle(nTexPos);
  //alpha += mix(-NOISE, NOISE, random(nTexPos)) * alpha;
  // Apply Simple Dithering for 8bit Channels
  gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0) * alpha;
}