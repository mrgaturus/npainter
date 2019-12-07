#version 330 core

// INPUT
uniform mat4 uPro;
layout (location = 0) in vec2 vPos;
layout (location = 1) in vec2 vColorPos;
// OUTPUT
out vec2 uvColorPos;

void main() {
  gl_Position = uPro * vec4(vPos, 0.0, 1.0);
  uvColorPos = vColorPos;
}