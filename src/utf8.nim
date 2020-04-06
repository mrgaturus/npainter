# Up to 0xFFFF, No Emojis, Sorry

type
  UTF8Input* = object
    str: string
    cursor*: int32
    changed*: bool

# -------------------
# UINT16 RUNE DECODER
# -------------------

template rune16*(str: string, i: int32, rune: uint16) =
  if str[i].uint8 <= 128:
    rune = str[i].uint16
    inc(i, 1) # Move 1 Byte
  elif str[i].uint8 shr 5 == 0b110:
    rune = # Use 2 bytes
      (str[i].uint16 and 0x1f) shl 6 or
      str[i+1].uint16 and 0x3f
    inc(i, 2) # Move 2 Bytes
  elif str[i].uint8 shr 4 == 0b1110:
    rune = # Use 3 bytes
      (str[i].uint16 and 0xf) shl 12 or
      (str[i+1].uint16 and 0x3f) shl 6 or
      str[i+2].uint16 and 0x3f
    inc(i, 3) # Move 3 bytes
  else: inc(i, 1) # Invalid UTF8

iterator runes16*(str: string): uint16 =
  var # 2GB str?
    i: int32
    result: uint16
  while i < len(str):
    rune16(str, i, result)
    yield result # Return Rune

# ------------------------------
# UTF8 INPUT DIRECT MANIPULATION
# ------------------------------

proc `text=`*(input: var UTF8Input, str: string) =
  input.str = str # Set New Str
  # Reset Cursor and Mark Changed
  input.cursor = 0; input.changed = true

template `text`*(input: ptr UTF8Input|UTF8Input): string =
  input.str # Returns Current String

# -----------------------
# UTF8 INPUT CURSOR PROCS
# -----------------------

proc forward*(input: ptr UTF8Input) =
  if input.cursor < len(input.str):
    var i = input.cursor + 1 # Start At Next
    while i < len(input.str) and # Not Chunk
        (input.str[i].uint8 and 0xC0) == 0x80:
      inc(i) # Next String Char
    input.cursor = i # Set New Position

proc reverse*(input: ptr UTF8Input) =
  if input.cursor > 0:
    var i = input.cursor - 1 # Start at Prev
    while i > 0 and # Not Chunk
        (input.str[i].uint8 and 0xC0) == 0x80:
      dec(i) # Prev String Char
    input.cursor = i

proc backspace*(input: ptr UTF8Input) =
  var p = input.cursor; input.reverse()
  if p != input.cursor: # Check if is not 0
    if p != len(input.str):
      copyMem(addr `[]`(input.str, input.cursor), 
        addr input.str[p], len(input.str) - p)
    # Trim String Length
    input.str.setLen(input.str.len - p + input.cursor)

proc delete*(input: ptr UTF8Input) =
  if input.cursor < len(input.str):
    # Delete Next Char
    input.forward()
    input.backspace()

proc insert*(input: ptr UTF8Input, str: cstring) =
  let # Shortcuts
    l = len(str).int32
    i = input.cursor
  # Expand String Capacity
  input.str.setLen len(input.str) + l
  # Move For Copy String
  if len(input.str) - i != l:
    moveMem(addr input.str[i + l], 
      addr input.str[i], len(input.str) - i)
  # Copy cString to String
  copyMem(addr input.str[i], str, l)
  # Forward Index
  input.cursor += l 
