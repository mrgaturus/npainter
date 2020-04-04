# Up to 0xFFFF, No Emojis, Sorry

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

# -------------------
# UTF8 STRING HELPERS
# -------------------

proc forward*(str: string, i: var int32) =
  if i < len(str): # Find Next Codepoint
    inc(i) # Next String Char
    while i < len(str) and # Not Chunk
        (str[i].uint8 and 0xC0) == 0x80:
      inc(i) # Next String Char

proc reverse*(str: string, i: var int32) =
  if i > 0: # Find Next Codepoint
    dec(i) # Next String Char
    while i > 0 and # Not Chunk
        (str[i].uint8 and 0xC0) == 0x80:
      dec(i) # Next String Char

proc backspace*(str: var string, i: var int32) =
  var p = i; reverse(str, i)
  if p != i:
    if p != len(str):
      copyMem(addr str[i], 
        addr str[p], len(str) - p)
    # Trim String Length
    str.setLen(str.len - p + i)

proc delete*(str: var string, i: var int32) =
  if i < len(str):
    # Delete Next Char
    forward(str, i)
    backspace(str, i)

proc insert*(str: var string, cstr: cstring, i: var int32) =
  let l = len(cstr).int32
  # Expand String Capacity
  str.setLen(str.len + l)
  # Move For Copy String
  if len(str) - i != l:
    moveMem(addr str[i + l], 
      addr str[i], len(str) - i)
  # Copy cString to String
  copyMem(addr str[i], cstr, l)
  # Forward Index
  i += l 
