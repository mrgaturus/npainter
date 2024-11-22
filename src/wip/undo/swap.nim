# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>

type
  NUndoSeek* = object
    pos*: int64
    bytes*: int64
  NUndoSkip* = object
    prev*, next*: int64
    pos*, bytes*: int64
  # Undo Swap File
  NUndoSide = enum
    sideWrite, sideRead
  NUndoSwap* = object
    file: File
    # Swap Stamping
    seekWrite: NUndoSeek
    stampWrite0: NUndoSkip
    stampWrite: NUndoSkip
    stampRead: NUndoSkip
    # Swap Seeking
    posWrite: int64
    posRead: int64
    side: NUndoSide

# ------------------------------
# Undo Swap Creation/Destruction
# ------------------------------

proc configure*(swap: var NUndoSwap) =
  if not open(swap.file, "undo.bin", fmWrite):
    echo "[ERROR]: failed creating swap file"
    quit(1)
  # Write Padding Header
  var pad: array[4, uint32]
  const head = sizeof(pad)
  if writeBuffer(swap.file, addr pad, head) != head:
    echo "[ERROR]: failed configure swap file"
    quit(1)
  # Initialize Current Seeking
  swap.posWrite = head
  swap.posRead = head

proc destroy*(swap: var NUndoSwap) =
  close(swap.file)
  `=destroy`(swap)

# -------------------------
# Undo Swap Read/Write Side
# -------------------------

proc makeCurrent(swap: var NUndoSwap, side: NUndoSide) =
  if swap.side == side:
    return
  # Change Current Seek
  case swap.side:
  of sideWrite:
    swap.posRead = getFilePos(swap.file)
    setFilePos(swap.file, swap.posWrite)
  of sideRead:
    swap.posWrite = getFilePos(swap.file)
    setFilePos(swap.file, swap.posRead)

# ------------------
# Undo Swap Writting
# ------------------

proc skipWrite(swap: var NUndoSwap, skip: ptr NUndoSkip) =
  const bytes = sizeof(NUndoSkip)
  setFilePos(swap.file, skip.pos)
  # Write Swap Seeking Header
  if writeBuffer(swap.file, skip, bytes) != bytes:
    echo "[WARNING] corrupted stamp write at: ", skip.pos
  swap.posWrite += bytes

proc setWrite*(swap: var NUndoSwap, skip: NUndoSkip) =
  swap.makeCurrent(sideWrite)
  # Locate Swap to Seeking
  setFilePos(swap.file, skip.pos)
  swap.posWrite = skip.pos
  swap.stampWrite0 = skip
  swap.stampWrite = skip

proc startWrite*(swap: var NUndoSwap) =
  swap.makeCurrent(sideWrite)
  let pos = swap.posWrite
  let stamp0 = addr swap.stampWrite0
  let stamp = addr swap.stampWrite
  # Initialize Current Seeking
  stamp.pos = pos
  stamp.next = pos
  stamp.bytes = 0
  # Check Previous Seeking
  if stamp.prev <= 0:
    stamp.prev = pos
  if stamp.pos != stamp0.pos:
    stamp.prev = stamp0.pos
    stamp0.next = pos
    swap.skipWrite(stamp0)
  # Write Current Seeking
  swap.skipWrite(stamp)
  stamp0[] = stamp[]

proc write*(swap: var NUndoSwap, data: pointer, size: int) =
  swap.makeCurrent(sideWrite)
  swap.posWrite += size
  # Write Buffer to Current Swap Seeking
  if writeBuffer(swap.file, data, size) != size:
    echo "[WARNING] corrupted write at: ", swap.posWrite

proc startSeek*(swap: var NUndoSwap) =
  swap.makeCurrent(sideWrite)
  let seek = addr swap.seekWrite
  seek.pos = swap.posWrite
  # Write Current Seek
  const bytes = sizeof(NUndoSeek)
  swap.write(seek, bytes)

proc endSeek*(swap: var NUndoSwap): NUndoSeek =
  swap.makeCurrent(sideWrite)
  result = move swap.seekWrite
  let pos = swap.posWrite
  # Calculate Seek Bytes
  const bytes = sizeof(NUndoSeek)
  result.bytes = pos - (result.pos + bytes)
  # Write Current Seek Again
  setFilePos(swap.file, result.pos)
  swap.write(addr result, bytes)
  setFilePos(swap.file, pos)

proc endWrite*(swap: var NUndoSwap): NUndoSkip =
  swap.makeCurrent(sideWrite)
  # Current Write Stamp
  const head = sizeof(NUndoSkip)
  let stamp = addr swap.stampWrite
  let pos = swap.posWrite
  let pos0 = stamp.pos
  # Update Current Write Stamp
  stamp.bytes = pos - (pos0 + head)
  swap.skipWrite(stamp)
  setFilePos(swap.file, pos)
  flushFile(swap.file)
  # Return Current Seeking
  result = stamp[]

# -----------------
# Undo Swap Reading
# -----------------

proc setRead*(swap: var NUndoSwap, skip: NUndoSkip) =
  swap.makeCurrent(sideRead)
  const head = sizeof(NUndoSkip)
  # Locate Swap to Seeking
  let pos = skip.pos + head
  setFilePos(swap.file, pos)
  swap.stampRead = skip
  swap.posRead = pos

proc setRead*(swap: var NUndoSwap, skip: int64): NUndoSkip =
  swap.makeCurrent(sideRead)
  const head = sizeof(NUndoSkip)
  # Read Current Seeking Header
  setFilePos(swap.file, skip)
  if readBuffer(swap.file, addr result, head) != head:
    echo "[WARNING] corrupted stamp read at: ", skip
  # Set Current Skip
  assert result.pos == skip
  swap.setRead(result)

proc setRead*(swap: var NUndoSwap, seek: NUndoSeek) =
  swap.makeCurrent(sideRead)
  const head = sizeof(NUndoSeek)
  # Check Seeking Bounds
  var pos = seek.pos + head
  setFilePos(swap.file, pos)
  swap.posRead = pos

proc readSeek*(swap: var NUndoSwap): NUndoSeek =
  swap.makeCurrent(sideRead)
  const head = sizeof(NUndoSeek)
  # Read Current Seeking
  if readBuffer(swap.file, addr result, head) != head:
    echo "[WARNING] corrupted seek read at: ", swap.posRead
  # Step Current Seeking
  assert result.pos == swap.posRead
  swap.posRead += head

proc skipSeek*(swap: var NUndoSwap): NUndoSeek =
  result = swap.readSeek()
  # Skip Seeking Bytes
  swap.posRead += result.bytes
  setFilePos(swap.file, swap.posRead)

proc read*(swap: var NUndoSwap, data: pointer, size: int) =
  swap.makeCurrent(sideRead)
  swap.posRead += size
  # Read Buffer From Current Swap Seeking
  if readBuffer(swap.file, data, size) != size:
    echo "[WARNING] corrupted read at: ", swap.posRead
