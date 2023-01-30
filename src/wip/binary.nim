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

# ------------------------
# Flood Fill DEMO Dispatch
# ------------------------

