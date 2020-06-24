# Render 256x256 Tiles, One Draw Call Per Tile
# If you know a better way for OGL3.3, tell me
import ../libs/gl
# --------------
import ../assets
import ../omath
# -----------
import canvas

const
  STRIDE_SIZE = # Casting
    sizeof(NVertex).int32
type
  # Canvas View Corner
  NCanvasCorner* = object
    x*, y*: int32
  # Tiled Canvas View
  NCanvasScanline = enum
    scNone, scLeftSide
    scInside, scRightSide
  NCanvasView = object
    # Shader Objects
    program: GLuint
    uView, uModel: GLint
    # OpenGL Objects
    vao, vbo, pbo: GLuint
    ping, pong: GLuint
    # Textures and Vertexs
    verts: seq[NVertex]
    texts: seq[GLuint]
    # Tile Count
    len: int32
    # Screen Size
    w, h: int32

# -------------------------
# CANVAS VIEW CREATION PROC
# -------------------------

proc newCanvasView*(): NCanvasView =
  result.program = # Compile Canvas Program
    newShader("canvas.vert", "canvas.frag")
  # -- Use Program for Define Uniforms
  glUseProgram(result.program)
  # Define Projection and Texture Uniforms
  result.uView = glGetUniformLocation(result.program, "uView")
  result.uModel = glGetUniformLocation(result.program, "uModel")
  # Set Default Uniform Value: Tile Texture
  glUniform1i glGetUniformLocation(result.program, "uTile"), 0
  # Unuse Program
  glUseProgram(0)
  # -- Generate Pixel Transfer PBOs
  glGenBuffers(2, addr result.ping)
  # Alloc Ping Pixel Buffer Object
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, result.ping)
  glBufferData(GL_PIXEL_UNPACK_BUFFER, 
    65536 * sizeof(NPixel), nil, GL_STREAM_COPY)
  # Alloc Pong Pixel Buffer Object
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, result.pong)
  glBufferData(GL_PIXEL_UNPACK_BUFFER, 
    65536 * sizeof(NPixel), nil, GL_STREAM_COPY)
  # Unbind Pixel Buffer Object
  glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0)
  # Set Initial Current PBO
  result.pbo = result.ping
  # -- Generate Vertex Buffer
  glGenVertexArrays(1, addr result.vao)
  glGenBuffers(1, addr result.vbo)
  # Bind VAO and VBO
  glBindVertexArray(result.vao)
  glBindBuffer(GL_ARRAY_BUFFER, result.vbo)
  # Vertex Attribs XYVUV 12bytes
  glVertexAttribPointer(0, 2, cGL_INT, false, 
    STRIDE_SIZE, cast[pointer](0)) # VERTEX
  glVertexAttribPointer(1, 2, GL_UNSIGNED_SHORT, true, 
    STRIDE_SIZE, cast[pointer](sizeof(int32)*2)) # UV
  # Unbind VBO and VAO
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  glBindVertexArray(0)

# --------------------------
# CANVAS VIEW, VIEWPORT PROC
# --------------------------

proc viewport*(view: var NCanvasView, w, h: int32) =
  # Change Screen Size
  view.w = w; view.h = h
  # Use Canvas Program
  glUseProgram(view.program)
  # Change Screen Uniform

  # Unuse Canvas Program
  glUseProgram(0)
