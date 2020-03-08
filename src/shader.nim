import logger
import libs/gl

# ---------------------
# FT2 FONT LOADING PROC
# ---------------------

# -------------------
# SHADER LOADING PROC
# -------------------

proc newProgram*(vert, frag: string): GLuint =
  var # Prepare Vars
    vertShader = glCreateShader(GL_VERTEX_SHADER)
    fragShader = glCreateShader(GL_FRAGMENT_SHADER)
    buffer: TaintedString
    bAddr: cstring
    success: GLint
  try: # -- LOAD VERTEX SHADER
    buffer = readFile(vert)
    bAddr = addr buffer[0]
  except: log(lvError, "failed loading shader: ", vert)
  glShaderSource(vertShader, 1, cast[cstringArray](addr bAddr), nil)
  try: # -- LOAD FRAGMENT SHADER
    buffer = readFile(frag)
    bAddr = addr buffer[0]
  except: log(lvError, "failed loading shader: ", frag)
  glShaderSource(fragShader, 1, cast[cstringArray](addr bAddr), nil)
  # -- COMPILE SHADERS
  glCompileShader(vertShader)
  glCompileShader(fragShader)
  # -- CHECK SHADER ERRORS
  glGetShaderiv(vertShader, GL_COMPILE_STATUS, addr success)
  if not success.bool:
    log(lvError, "failed compiling: ", vert)
  glGetShaderiv(fragShader, GL_COMPILE_STATUS, addr success)
  if not success.bool:
    log(lvError, "failed compiling: ", frag)
  # -- CREATE PROGRAM
  result = glCreateProgram()
  glAttachShader(result, vertShader)
  glAttachShader(result, fragShader)
  glLinkProgram(result)
  # -- CLEAN UP TEMPORALS
  glDeleteShader(vertShader)
  glDeleteShader(fragShader)