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
  if str[i].uint8 <= 127:
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
  else: # Invalid UTF8
    rune = str[i].uint16
    inc(i, 1) # Move 1 byte

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
  input.str = str
  # Set Cursor to Len
  input.cursor = 
    len(str).int32
  input.changed = true

template `text`*(input: ptr UTF8Input|UTF8Input): string =
  input.str # Returns Current String

# -----------------------
# UTF8 INPUT CURSOR PROCS
# -----------------------

proc forward*(input: ptr UTF8Input) =
  var i = input.cursor; inc(i)
  let l = len(input.str)
  while i < l and # Not UTF8 Chunk
      (input.str[i].uint8 and 0xC0) == 0x80:
    inc(i) # Next String Char
  if i <= l: input.cursor = i

proc reverse*(input: ptr UTF8Input) =
  var i = input.cursor; dec(i)
  while i > 0 and # Not UTF8 Chunk
      (input.str[i].uint8 and 0xC0) == 0x80:
    dec(i) # Prev String Char
  if i >= 0: input.cursor = i

proc backspace*(input: ptr UTF8Input) =
  var p = input.cursor; input.reverse()
  let delta = p - input.cursor
  if delta > 0: # Check Delta
    if p < len(input.str):
      copyMem(addr `[]`(input.str, input.cursor),
        addr input.str[p], len(input.str) - p)
    # Trim String Length
    input.str.setLen(input.str.len - delta)

proc delete*(input: ptr UTF8Input) =
  if input.cursor < len(input.str):
    # Delete Next Char
    input.forward()
    input.backspace()

proc insert*(input: ptr UTF8Input, str: cstring, l: int32) =
  let # Constants
    i = input.cursor
    pl = len(input.str)
  # Expand String
  input.str.setLen(
    len(input.str) + l)
  if i < pl: # Somewhere
    moveMem(addr input.str[i + l],
      addr input.str[i], len(input.str) - i)
  # Copy cString to String
  copyMem(addr input.str[i], str, l)
  # Forward Index
  input.cursor += l
