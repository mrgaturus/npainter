# Render 256x256 Tiles, One Draw Call Per Tile
# If you know a better way for OGL3.3, tell me
import ../libs/gl
import ../assets
import ../omath
# Extend Canvas
import canvas

type
  # -- Primitives
  NVertex = object
    x, y: int32
    u, v: uint16
  # -- Tiled Canvas View
  NCanvasView = object
    # Shader Objects
    program: GLuint
    uView, uModel: GLint
    # OpenGL Objects
    vao, vbo, pbo: GLuint
    ping, pong: GLuint
    # Viewport Uniforms
    width, height: int32
    mView: array[16, float32]
    mModel: array[9, float32]
    # Canvas Target Addr
    target: ptr NCanvas
    # Textures and Vertexs
    verts: seq[NVertex]
    texts: seq[GLuint]
    # Current Status
    len: int32
    dirty: bool
const # Vertex Layout Stride
  STRIDE_SIZE = # Casting
    sizeof(NVertex).int32

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

# ------------------------------------
# CANVAS VIEW BASIC MANIPULATION PROCS
# ------------------------------------

# Same as GUI, but is for other shader program
proc viewport*(view: var NCanvasView, w, h: int32) =
  # Use Canvas Program
  glUseProgram(view.program)
  # Change View Projection Matrix
  guiProjection(addr view.mView, 
    float32 w, float32 h)
  # Upload View Projection Matrix
  glUniformMatrix4fv(view.uView, 1, false,
    cast[ptr float32](addr view.mView))
  # Unuse Canvas Program
  glUseProgram(0)
  # Save New Viewport Size
  view.width = w; view.height = h
  # Invalidate View Tiles
  view.dirty = true

proc target*(view: var NCanvasView, canvas: ptr NCanvas) =
  # Set New Canvas Target
  view.target = canvas
  # Invalidate View Tiles
  view.dirty = true
