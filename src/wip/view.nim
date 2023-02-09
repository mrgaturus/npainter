import canvas

type
  NCanvasView* = object
    canvas: ptr NCanvas
    # Canvas Configuration
    mirror: bool
    x, y: cfloat
    zoom, angle: cfloat
    # OpenGL 3.3 Canvas
    program: cuint
    fbo, textures: seq[cuint]
