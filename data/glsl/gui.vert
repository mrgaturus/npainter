#version 330 core

// UNIFORM INPUT
uniform mat4 uPro;
uniform vec2 uDim;
// VERTEX INPUT
layout (location = 0) in vec2 vPos;
layout (location = 1) in vec2 vTexPos;
layout (location = 2) in vec4 vColor;
// FRAGMENT OUTPUT
out vec2 nTexPos;
out vec4 nColor;

void main() {
  // Vertex Color
  nColor = vColor;
  // Normalized UV Position
  nTexPos = vTexPos * uDim;
  // Vertex Projected XY Position
  gl_Position = uPro * vec4(vPos, 0, 1);
}