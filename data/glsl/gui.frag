#version 330 core

// TEXTURE
uniform sampler2D uTex;
// INPUT FROM VERTEX
in vec2 nTexPos;
in vec4 nColor;

void main() {
  gl_FragColor = texture(uTex, nTexPos) * nColor;
}