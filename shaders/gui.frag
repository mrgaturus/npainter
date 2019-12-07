#version 330 core

// TEXTURE
uniform sampler2D uTex;
// INPUT
uniform vec4 uCol;
in vec2 uvColorPos;

void main() {
  gl_FragColor = texture(uTex, uvColorPos) * uCol;
}