import libs/gl

proc newProgram*(vert, frag: string): GLuint =
  var
    vertShader = glCreateShader(GL_VERTEX_SHADER)
    fragShader = glCreateShader(GL_FRAGMENT_SHADER)
    buffer: TaintedString
    bAddr: ptr char
    success: GLint

  # LOAD VERTEX SHADER
  try: 
    buffer = readFile(vert)
    bAddr = buffer[0].addr
  except: echo "ERROR: failed loading shader " & vert
  glShaderSource(vertShader, 1, cast[cstringArray](bAddr.addr), nil)

  # LOAD FRAGMENT SHADER
  try: 
    buffer = readFile(frag)
    bAddr = buffer[0].addr
  except: echo "ERROR: failed loading shader " & frag
  glShaderSource(fragShader, 1, cast[cstringArray](bAddr.addr), nil)

  # COMPILE SHADERS: TODO: CHECK ERRORS
  glCompileShader(vertShader)
  glCompileShader(fragShader)

  glGetShaderiv(vertShader, GL_COMPILE_STATUS, addr success)
  if not success.bool:
    echo "failed compiling vert"
  glGetShaderiv(fragShader, GL_COMPILE_STATUS, addr success)
  if not success.bool:
    echo "failed compiling frag"

  # CREATE PROGRAM
  result = glCreateProgram()
  glAttachShader(result, vertShader)
  glAttachShader(result, fragShader)
  glLinkProgram(result)

  # CLEAN UP SHADERS
  glDeleteShader(vertShader)
  glDeleteShader(fragShader)