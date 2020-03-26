# TODO: Use fontconfig for extra fonts
# TODO: Use /usr/share/npainter

import macros
import logger
import libs/gl
from libs/ft2 import
  FT2Face,
  FT2Library,
  ft2_init,
  ft2_newFace,
  ft2_setCharSize

type # Buffer Data
  BUFIcons* = ptr object
    size*: int16 # size*size
    count*, len*: int32
    buffer*: UncheckedArray[byte]
const # Common Paths
  shaderPath = "data/glsl/"
  fontPath = "data/font.ttf"
  iconsPath = "data/icons.dat"

when defined(packIcons):
  from strutils import join
  const icons_pack = 
    "../svg/icons_pack.sh"

# Initialize Freetype2
var freetype: FT2Library
if ft2_init(addr freetype) != 0:
  log(lvError, "failed initialize FreeType2")

# ------------------------------
# GUI FONT & ICONS LOADING PROCS
# ------------------------------

proc newFont*(size: int32): FT2Face =
  # Load Default Font File using FT2 Loader
  if ft2_newFace(freetype, fontPath, 0, addr result) != 0:
    log(lvError, "failed loading font file: ", fontPath)
  # Set Size With 96 of DPI, system DPI handling is bad
  if ft2_setCharSize(result, 0, size shl 6, 96, 96) != 0:
    log(lvWarning, "font size was setted not properly")

proc newIcons*(): BUFIcons =
  var icons: File
  if open(icons, iconsPath):
    # Copy File to Buffer
    var read: int # Bytes Readed
    let size = getFileSize(icons)
    result = cast[BUFIcons](alloc size)
    read = readBuffer(icons, result, size)
    if read != size: # Check if was loaded correctly
      log(lvWarning, "bad icons file size: ", iconsPath)
    # Close Icons File
    close(icons)
  else: # Failed Loading Icons
    log(lvError, "failed loading icons file: ", iconsPath)

macro setIcons*(size: Natural, list: untyped) =
  var index: uint16 # Current Icon ID
  result = newNimNode(nnkConstSection)
  when defined(packIcons): # Generate Dat file
    var args = # icons_pack arguments
      @[icons_pack, iconsPath, $size.intVal]
    for icon in list:
      # Create New Icon Constant
      expectKind(icon[0], nnkIdent)
      result.add(newNimNode(nnkConstDef).add(
        postfix(icon[0], "*"), newEmptyNode(), newLit(index)))
      # Add Icon Pack Argument
      expectKind(icon[1], nnkStrLit)
      args.add icon[1].strVal
      # Next Icon ID
      inc(index)
    # Create Icon Data using icon_pack
    let exec = gorgeEx(args.join " ")
    if exec.exitCode != 0: error(exec.output)
  else: # Only Generate Enum
    for icon in list:
      # Create New Icon Constant
      expectKind(icon[0], nnkIdent)
      result.add(newNimNode(nnkConstDef).add(
        postfix(icon[0], "*"), newEmptyNode(), newLit(index)))
      # Next Icon ID
      inc(index)

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
