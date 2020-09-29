#version 330 core

// TILE TEXTURE
uniform sampler2D uTile;
// INPUT FROM VERTEX
in vec2 nTexPos;

void main() {
  gl_FragColor = texture(uTile, nTexPos);
}