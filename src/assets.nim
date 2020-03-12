# TODO: Use fontconfig for extra fonts
# TODO: Use /usr/share/npainter

import logger
import libs/gl
from libs/ft2 import
  FT2Face,
  FT2Library,
  ft2_newFace,
  ft2_setCharSize

const
  shaderPath = "data/glsl/"
  fontPath = "data/font.ttf"

# ---------------------
# FT2 FONT LOADING PROC
# ---------------------

proc newFont*(ft2: FT2Library, size: int32): FT2Face =
  # Load Default Font File using FT2 Loader
  if ft2_newFace(ft2, fontPath, 0, addr result) != 0:
    log(lvError, "failed loading font file: ", fontPath)
  # Set Size With 96 of DPI, system DPI handling is bad
  if ft2_setCharSize(result, 0, size shl 6, 96, 96) != 0:
    log(lvWarning, "font size was setted not properly")

# -------------------
# SHADER LOADING PROC
# -------------------

proc newShader*(vert, frag: string): GLuint =
  var # Prepare Vars
    vertShader = glCreateShader(GL_VERTEX_SHADER)
    fragShader = glCreateShader(GL_FRAGMENT_SHADER)
    buffer: TaintedString
    bAddr: cstring
    success: GLint
  try: # -- LOAD VERTEX SHADER
    buffer = readFile(shaderPath & vert)
    bAddr = addr buffer[0]
  except: log(lvError, "failed loading shader: ", vert)
  glShaderSource(vertShader, 1, cast[cstringArray](addr bAddr), nil)
  try: # -- LOAD FRAGMENT SHADER
    buffer = readFile(shaderPath & frag)
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