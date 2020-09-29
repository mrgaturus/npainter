#version 330 core

// UNIFORM INPUT
uniform mat4 uPro;
uniform mat3 uModel;
// VERTEX INPUT
layout (location = 0) in vec2 vPos;
layout (location = 1) in vec2 vTexPos;
// FRAGMENT OUTPUT
out vec2 nTexPos;

void main() {
  // UV Position
  nTexPos = vTexPos;
  // Vertex Projected XY Position
  vec3 vPosModel = uModel * vec3(vPos, 1);
  gl_Position = uPro * vec4(vPosModel.xy, 0, 1);
}