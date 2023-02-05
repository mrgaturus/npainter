# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>

# -------------------------
# Smooth Numbers Generation
# -------------------------

func offsets(mask0, mask1: sink uint16, single: bool): uint8 =
  var offset0, offset1: uint8
  # Analyze Each Bit
  var i: uint8 = 8; while i > 0:
    if (mask0 and 0x100) > 0:
      let
        check0 = ((mask1 shr 1) and 0x100) > 0
        check1 = ((mask1 shl 1) and 0x100) > 0
      if not single:
        offset1 = offset0
        offset0 =
          if check0: i + 1
          elif check1: i - 1
          else: i
      else:
        offset0 = i
        offset1 = i
        if check0: offset1 = i + 1
        if check1: offset0 = i - 1
        # Stop Single
        break
    # Next Bit
    mask0 = mask0 shl 1
    mask1 = mask1 shl 1
    # Next Index
    dec(i)
  # Merge Each Offset
  result = (offset1 and 0x7) shl 3
  result = result or (offset0 and 0x7)

func magic(pattern: uint8): uint8 =
  type
    NSmoothKind = enum
      smInvalid, smStart, smStep, smEnd
  var 
    kind: NSmoothKind
    vertical, horizontal: uint8
    mask0, mask1: uint16
  # Check if is able to check
  result = pattern and 0x55
  if result == 0x55 or result == 0:
    return 0
  # Check Symetries and Alones
  vertical = result and 0x11
  horizontal = result and 0x44
  # Check if is there is not Vertical, Horizontal Symetric
  if vertical < 0x11 and horizontal < 0x44:
    # Check Diagonal Symetric
    mask0 = vertical or horizontal
    result = case mask0:
    of 0x5, 0x50: 0x88
    of 0x14, 0x41: 0x22
    else: 0xFF
    mask1 = result
    # Check if is a Diagonal Step or Start
    result = pattern and result
    if result == 0x88 or result == 0x22:
      kind = smStep
    else: kind = smStart
  elif vertical == 0x11:
    kind = smEnd
    mask0 = vertical
    # Verify Horizontal Diagonals
    if (pattern and 0x04) == 0x04:
      mask1 = pattern and 0xE0
    elif (pattern and 0x40) == 0x40:
      mask1 = pattern and 0x0E
    if mask1 == 0: kind = smStep
  elif horizontal == 0x44:
    kind = smEnd
    mask0 = horizontal
    # Verify Horizontal Diagonals
    if (pattern and 0x01) == 0x01:
      mask1 = pattern and 0x38
    elif (pattern and 0x10) == 0x10:
      mask1 = pattern and 0x83
    if mask1 == 0: kind = smStep
  # Mask Which Kind is
  result = case kind
  of smStart: 0x80
  of smEnd: 0xC0
  of smStep: 0x40
  of smInvalid: 0x00
  # Include Offsets
  if result > 0x40:
    # Arrange Masks
    let single = mask1 == 0xFF
    mask0 = mask0 and pattern
    mask1 = mask1 and pattern
    mask0 = (mask0 shl 8) or mask0
    mask1 = (mask1 shl 8) or mask1
    # Calculate Offsets and Merge With Magic Number
    result = result or offsets(mask0, mask1, single)

func magics*(): array[256, uint8] =
  for x in 0 ..< 256:
    result[x] = magic(uint8 x)

const magic_numbers {.exportc.} = magics()
# Avoid Optimizing Out
{.push checks: off.}
let dummy {.nodecl.} = 0
{.emit: ["/*", magic_numbers[dummy], "*/"].}
{.pop.}

# ---------------------------------------------------------
# This is for proof of concept until NCanvas/NLayer is done
# ---------------------------------------------------------
import binary/ffi

type
  NBucketCheck* = enum
    bkColor, bkAlpha
    bkMinimun, bkSimilar
  NBucketProof* = object
    bin: NBinary
    smooth: NBinarySmooth
    clear: NBinaryClear
    flood: NFloodFill
    chamfer: NDistance
    # Stride, Rows
    stride, rows: cint
    # Buffer Pointers
    s0, s1, s2: pointer
    a0, b0, b1, b2: pointer
    # Bucket Parameters
    tolerance*, gap*: cint
    check*: NBucketCheck
    antialiasing*: bool
    # Bucket Color
    rgba*: cuint

func index(buffer: pointer; w, h, idx: cint): pointer =
  let i = cast[cuint](w * h * idx)
  cast[pointer](cast[uint](buffer) + i)

func pixel(bucket: NBucketProof; x, y: cint): cuint =
  let 
    i = (bucket.stride * y + x) shl 2
    p = cast[ptr UncheckedArray[cushort]](bucket.s0)
    # Get Colors
    r = cast[cuint](p[i + 0] shr 8)
    g = cast[cuint](p[i + 1] shr 8)
    b = cast[cuint](p[i + 2] shr 8)
    a = cast[cuint](p[i + 3] shr 8)
  # Merge To 32 Bits
  result = r or (g shl 8) or (b shl 16) or (a shl 24)

proc configure*(buffer0, buffer1, buffer2: pointer; w, h: cint): NBucketProof =
  let
    b0 = index(buffer1, w, h, 2)
    b1 = index(buffer1, w, h, 3)
    b2 = index(buffer1, w, h, 4)
    # Auxiliar Buffers
    a0 = index(buffer2, w, h, 4)
  result.s0 = buffer0
  result.s1 = buffer1
  result.s2 = buffer2
  # Configure Pointers
  result.b0 = b0
  result.b1 = b1
  result.b2 = b2
  # Configure Auxiliar
  result.a0 = a0
  # Create Auxiliar Buffer
  result.stride = w
  result.rows = h
  # Configure Bounds
  result.bin.bounds(w, h)
  result.flood.bounds(w, h)
  result.chamfer.bounds(w, h)
  # Configure Regions
  result.bin.region(0, 0, w, h)
  result.clear.region(0, 0, w, h)
  result.chamfer.region(0, 0, w, h)

proc flood*(bucket: var NBucketProof, x, y: cint) =
  let 
    pix = pixel(bucket, x, y)
    bytes = bucket.stride * bucket.rows
    chunk = bytes shl 3
  var test: cuint = 0xFF
  # Clear All Buffers
  zeroMem(bucket.s2, chunk)
  zeroMem(bucket.s1, chunk)
  # Convert to Binary
  bucket.bin.target(bucket.s0, bucket.b0)
  case bucket.check
  of bkColor, bkSimilar: bucket.bin.toBinary(pix, cuint bucket.tolerance, true)
  of bkAlpha: bucket.bin.toBinary(pix, cuint bucket.tolerance, false)
  of bkMinimun: bucket.bin.toBinary(cuint bucket.tolerance)
  # First Flood Fill
  bucket.flood.target(bucket.b0, bucket.b1)
  bucket.flood.stack cast[ptr cshort](bucket.b2)
  bucket.flood.dispatch(x, y, false)
  # Close Gaps
  if bucket.gap > 0:
    let 
      positions = cast[ptr cuint](bucket.s2)
      distances = cast[ptr cuint](bucket.a0)
    bucket.chamfer.auxiliars(positions, distances)
    bucket.chamfer.checks(255, bucket.gap)
    # Fast Erode Dilate Using Chamfer
    bucket.chamfer.buffers(bucket.b1, bucket.b0)
    bucket.chamfer.dispatch_almost()
    bucket.chamfer.buffers(bucket.b0, bucket.b0)
    bucket.chamfer.dispatch_almost()
    # TODO: after NCanvas/NLayer and some gui i will refactor
    let d = cast[ptr UncheckedArray[uint8]](bucket.b0)
    for i in 0 ..< bytes: d[i] = not d[i]
    # Perform Gap Closing
    bucket.flood.target(bucket.b1, bucket.b0)
    bucket.flood.dispatch(x, y, true)
    # Convert Gaps
    test = 0x7F
  # Convert and Apply Color
  bucket.bin.target(bucket.s2, bucket.b1)
  if bucket.antialiasing:
    bucket.smooth.toSmooth(bucket.bin, bucket.rgba, test)
    bucket.smooth.auxiliar(cast[ptr cushort](bucket.b2))
    bucket.smooth.dispatch()
  else: bucket.bin.toColor(bucket.rgba, test)

proc similar*(bucket: var NBucketProof, x, y: cint) =
  let 
    pix = pixel(bucket, x, y)
    bytes = (bucket.stride * bucket.rows) shl 3
  # Clear All Buffers
  zeroMem(bucket.s2, bytes)
  zeroMem(bucket.s1, bytes)
  # Convert to Binary
  bucket.bin.target(bucket.s0, bucket.b0)
  bucket.bin.toBinary(pix, cuint bucket.tolerance, true)
  # Apply Color
  bucket.bin.target(bucket.s2, bucket.b0)
  if bucket.antialiasing:
    bucket.smooth.toSmooth(bucket.bin, bucket.rgba, 0)
    bucket.smooth.auxiliar(cast[ptr cushort](bucket.b2))
    bucket.smooth.dispatch()
  else: bucket.bin.toColor(bucket.rgba, 0)

proc blend*(bucket: var NBucketProof) =
  let # TODO: change when NLayer is done
    src = cast[ptr UncheckedArray[cushort]](bucket.s2)
    dst = cast[ptr UncheckedArray[cushort]](bucket.s0)
    l = cint(bucket.stride * bucket.rows * 4)
  var cursor: cint; while cursor < l:
    let
      # Source Colors
      rsrc: cuint = src[cursor + 0]
      gsrc: cuint = src[cursor + 1]
      bsrc: cuint = src[cursor + 2]
      asrc: cuint = src[cursor + 3]
      # Destination Colors
      rdst: cuint = dst[cursor + 0]
      gdst: cuint = dst[cursor + 1]
      bdst: cuint = dst[cursor + 2]
      adst: cuint = dst[cursor + 3]
      # Interpolator
      a: cuint = 65535 - asrc
    # Blend Two Colors
    dst[cursor + 0] = cast[cushort](rsrc + ((rdst * a + a) shr 16))
    dst[cursor + 1] = cast[cushort](gsrc + ((gdst * a + a) shr 16))
    dst[cursor + 2] = cast[cushort](bsrc + ((bdst * a + a) shr 16))
    dst[cursor + 3] = cast[cushort](asrc + ((adst * a + a) shr 16))
    # Next Pixel
    cursor += 4
