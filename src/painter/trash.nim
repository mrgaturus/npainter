# GPU-Accelerated Brush Engine
# PBO Upload->FBO->PBO Download
import ../libs/gl
import canvas
# Import Orthogonal Projection
from ../assets import newShader
from ../omath import guiProjection
# Reuse Vertex Attribute of NCanvasView
from voxel import 
  NQuad, NMatrix, 
  mat3_brush, vec2_mat3

type 
  # -- Primitives
  NVertex {.packed.} = object
    x, y: float32
    u, v: float32
  # -- Brush Engine
  #NAverage = object
  NTrashEngine* = object
    program: GLuint
    uPro, uModel, uScale: GLint
    # OpenGL Objects
    vao, vbo: GLuint
    tex*, mask, fbo: GLuint
    unpack, pack: GLuint
    # Current Layer
    canvas: ptr NCanvas
    # Voxel Quad
    quad: NQuad
    matrix: NMatrix
    # GUI Viewport Backup
    viewport: array[4, int32]
const # Vertex Layout Stride
  STRIDE_SIZE = # Casting
    sizeof(NVertex).int32

# ------------------------------
# BRUSH ENGINE CONSTRUCTOR PROCS
# ------------------------------

proc newTrashEngine*(): NTrashEngine =
  block: # -- Define Shader and Uniforms
    result.program = # Compile Shader
      newShader("canvas.vert", "brush.frag")
    # -- Use Program for Define Uniforms
    glUseProgram(result.program)
    # Define Projection and Texture Uniforms
    result.uPro = glGetUniformLocation(result.program, "uPro")
    result.uModel = glGetUniformLocation(result.program, "uModel")
    result.uScale = glGetUniformLocation(result.program, "uScale")
    # Set Default Uniform Value: Tile Texture
    glUniform1i glGetUniformLocation(result.program, "uMask"), 0
    # Calculate Projection Using GUI Projection
    var uPro: array[16, float32]
    guiProjection(addr uPro, 2048, 2048)
    glUniformMatrix4fv(result.uPro, 
      1, false, addr uPro[0])
    # Unuse Program
    glUseProgram(0)
  block: # -- Define Textures and Framebuffers
    glGenFramebuffers(1, addr result.fbo)
    glGenTextures(2, addr result.tex)
    # Bind Framebuffer Object
    glBindFramebuffer(GL_FRAMEBUFFER, result.fbo)
    # Define Render Target Texture
    glBindTexture(GL_TEXTURE_2D, result.tex)
    glTexImage2D(GL_TEXTURE_2D, 0, cast[GLint](GL_RGBA8), 
      2048, 2048, 0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
    # Set Mig/Mag Filter
    glTexParameteri(GL_TEXTURE_2D, 
      GL_TEXTURE_MIN_FILTER, cast[GLint](GL_NEAREST))
    glTexParameteri(GL_TEXTURE_2D, 
      GL_TEXTURE_MAG_FILTER, cast[GLint](GL_NEAREST))
    # Set Framebuffer Attachment
    glFramebufferTexture2D(GL_FRAMEBUFFER, 
      GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, result.tex, 0)
    # Define Stencil Selection Texture
    glBindTexture(GL_TEXTURE_2D, result.mask)
    glTexImage2D(GL_TEXTURE_2D, 0, cast[GLint](GL_R16), 
      128, 128, 0, GL_RED, GL_UNSIGNED_BYTE, nil)
    # Set Mig/Mag Filter
    glTexParameteri(GL_TEXTURE_2D, 
      GL_TEXTURE_MIN_FILTER, cast[GLint](GL_LINEAR_MIPMAP_NEAREST))
    glTexParameteri(GL_TEXTURE_2D, 
      GL_TEXTURE_MAG_FILTER, cast[GLint](GL_LINEAR))
    # Unbind FBO and Textures
    glBindTexture(GL_TEXTURE_2D, 0)
    glBindFramebuffer(GL_FRAMEBUFFER, 0)
  block: # -- Define Pixel Buffer Objects
    glGenBuffers(2, addr result.unpack)
    # Define Pixel Unpack Buffer
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, result.unpack)
    glBufferData(GL_PIXEL_UNPACK_BUFFER, 
      sizeof(NPixel) * 2048*2048, nil, GL_STREAM_DRAW)
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0)
    # Define Pixel Pack Buffer
    glBindBuffer(GL_PIXEL_PACK_BUFFER, result.pack)
    glBufferData(GL_PIXEL_PACK_BUFFER, 
      sizeof(NPixel) * 2048*2048, nil, GL_STREAM_READ)
    glBindBuffer(GL_PIXEL_PACK_BUFFER, 0)
  block: # -- Define Vertex Array Object
    glGenVertexArrays(1, addr result.vao)
    glGenBuffers(1, addr result.vbo)
    # Bind VAO and VBO
    glBindVertexArray(result.vao)
    glBindBuffer(GL_ARRAY_BUFFER, result.vbo)
    # Alloc Brush Quadrilateral
    glBufferData(GL_ARRAY_BUFFER, 
      sizeof(NVertex) * 4, nil, GL_STATIC_DRAW)
    # Vertex Attribs XYVUV 12bytes
    glVertexAttribPointer(0, 2, cGL_FLOAT, false, 
      STRIDE_SIZE, cast[pointer](0)) # VERTEX
    glVertexAttribPointer(1, 2, cGL_FLOAT, true, 
      STRIDE_SIZE, cast[pointer](sizeof(float32)*2)) # UV
    # Enable Verter Attribs
    glEnableVertexAttribArray(0)
    glEnableVertexAttribArray(1)
    # Unbind VBO and VAO
    glBindBuffer(GL_ARRAY_BUFFER, 0)
    glBindVertexArray(0)

# --------------------------------
# BRUSH ENGINE CONFIGURATION PROCS
# --------------------------------

# Brush Engine Vertex Definition
proc vertex*(vp: var NVertex, x, y, u, v: float32) =
  # Set Position
  vp.x = x; vp.y = y
  # Set Texture Coordinates
  vp.u = u; vp.v = v

# Test Brush Engine Quadrilateral
proc test*(brush: var NTrashEngine) =
  var quad: array[4, NVertex]
  quad[0].vertex(-512, -512, 0, 0)
  quad[1].vertex(512, -512, 1, 0)
  quad[2].vertex(-512, 512, 0, 1)
  quad[3].vertex(512, 512, 1, 1)
  # Upload Quad to VBO
  glBindBuffer(GL_ARRAY_BUFFER, brush.vbo)
  glBufferSubData(GL_ARRAY_BUFFER, 0, 
    sizeof(NVertex) * 4, addr quad[0])
  glBindBuffer(GL_ARRAY_BUFFER, 0)

proc mask*(brush: var NTrashEngine, tex: pointer) =
  glBindTexture(GL_TEXTURE_2D, brush.mask)
  #glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 128, 128, GL_RED, GL_UNSIGNED_BYTE, tex)
  echo "ERROR: ", glGetError()
  glGenerateMipmap(GL_TEXTURE_2D)
  #glPixelStorei(GL_UNPACK_ALIGNMENT, 4)
  glBindTexture(GL_TEXTURE_2D, 0)

# --------------------------------
# BRUSH ENGINE TEST PIPELINE PROCS
# --------------------------------

proc begin*(brush: var NTrashEngine) =
  # Backup GUI Viewport
  glGetIntegerv(GL_VIEWPORT, 
    addr brush.viewport[0])
  # Set Brush Engine Viewport
  glViewport(0, 0, 2048, 2048)
  # Use Shader Program and FBO
  glUseProgram(brush.program)
  glBindFramebuffer(GL_FRAMEBUFFER, brush.fbo)
  # Use Vertex Array Buffer
  glBindVertexArray(brush.vao)
  glBindTexture(GL_TEXTURE_2D, brush.mask)

# --> Debug Prototype
proc clear*(brush: var NTrashEngine) =
  glClearColor(1.0, 1.0, 1.0, 1.0)
  glClear(GL_COLOR_BUFFER_BIT)

proc transform*(brush: var NTrashEngine, x, y, s, o: float32) =
  # Calculate Transform Matrix
  mat3_brush(brush.matrix, x, y, s, o)
  # Upload Transform Matrix
  glUniformMatrix3fv(brush.uModel, 1, 
    true, addr brush.matrix[0])
  # Update Scale Uniform
  glUniform1f(brush.uScale, s)

# Used By Voxel Scanline
proc quad*(brush: var NTrashEngine): NQuad =
  for i in 0..3: # Iterate Points
    result[i] = brush.quad[i]
    vec2_mat3(result[i], brush.matrix)

proc draw*(brush: var NTrashEngine) {.inline.} =
  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)

proc finish*(brush: var NTrashEngine) =
  glBindTexture(GL_TEXTURE_2D, 0)
  # Unbind Vertex Array Buffer
  glBindVertexArray(0)
  # Unuse Shader Program and FBO
  glBindFramebuffer(GL_FRAMEBUFFER, 0)
  glUseProgram(0)
  # Restore GUI Viewport
  let viewport = addr brush.viewport
  glViewport(
    viewport[0], viewport[1], 
    viewport[2], viewport[3])
