#version 330 core

// INPUT
uniform mat4 uPro;
layout (location = 0) in vec2 vPos;
layout (location = 1) in vec2 vTexPos;
layout (location = 2) in vec4 vColor;
// OUTPUT
out vec2 nTexPos;
out vec4 nColor;

void main() {
  gl_Position = uPro * vec4(vPos, 0.0, 1.0);
  nTexPos = vTexPos; // UV Position
  nColor = vColor; // Vertex Color
}