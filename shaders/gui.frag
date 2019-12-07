#version 330 core

// TEXTURE
uniform sampler2D uTex;
// INPUT
uniform vec4 uCol;
in vec2 uvColorPos;

void main() {
  //gl_FragColor = vec4(uvColorPos.xy, 0.0, 1.0) * uCol;
  gl_FragColor = texture(uTex, uvColorPos) * uCol;
  //gl_FragColor = uCol;
}