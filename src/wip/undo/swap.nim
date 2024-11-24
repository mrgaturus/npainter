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
    # Swap Seeking
    posWrite: int64
    posRead: int64
    side: NUndoSide
    chain: bool

# ------------------------------
# Undo Swap Creation/Destruction
# ------------------------------

proc configure*(swap: var NUndoSwap) =
  if not open(swap.file, "undo.bin", fmReadWrite):
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
  case side:
  of sideWrite:
    swap.posRead = getFilePos(swap.file)
    setFilePos(swap.file, swap.posWrite)
  of sideRead:
    swap.posWrite = getFilePos(swap.file)
    setFilePos(swap.file, swap.posRead)
  swap.side = side

# ------------------
# Undo Swap Writting
# ------------------

proc skipWrite(swap: var NUndoSwap, skip: ptr NUndoSkip) =
  let pos = skip.pos
  const bytes = sizeof(NUndoSkip)
  setFilePos(swap.file, pos)
  # Write Swap Seeking Header
  if writeBuffer(swap.file, skip, bytes) != bytes:
    echo "[WARNING] corrupted stamp write at: ", pos
  # Set Write Position
  swap.posWrite = pos + bytes
  swap.chain = true

proc setWrite*(swap: var NUndoSwap, skip: NUndoSkip) =
  swap.makeCurrent(sideWrite)
  # Locate Swap to Seeking
  setFilePos(swap.file, skip.pos)
  swap.posWrite = skip.pos
  swap.stampWrite0 = skip
  swap.stampWrite = skip
  swap.chain = false

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
  if stamp.prev == 0:
    stamp.prev = pos
  elif swap.chain:
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
  const head = sizeof(NUndoSeek)
  swap.write(seek, head)

proc endSeek*(swap: var NUndoSwap): NUndoSeek =
  swap.makeCurrent(sideWrite)
  result = move swap.seekWrite
  let pos = swap.posWrite
  # Calculate Seek Bytes
  const head = sizeof(NUndoSeek)
  result.bytes = pos - result.pos - head
  # Write Current Seek Again
  setFilePos(swap.file, result.pos)
  swap.write(addr result, head)
  setFilePos(swap.file, pos)
  swap.posWrite = pos

proc endWrite*(swap: var NUndoSwap): NUndoSkip =
  swap.makeCurrent(sideWrite)
  let stamp0 = addr swap.stampWrite0
  let stamp = addr swap.stampWrite
  # Current Write Position
  let pos = swap.posWrite
  let pos0 = stamp.pos
  # Update Current Write Stamp
  const head = sizeof(NUndoSkip)
  stamp.bytes = pos - (pos0 + head)
  swap.skipWrite(stamp)
  # Restore File Position
  swap.posWrite = pos
  setFilePos(swap.file, pos)
  flushFile(swap.file)
  # Update Stamp
  result = stamp[]
  stamp0[] = result

# -----------------
# Undo Swap Reading
# -----------------

proc setRead*(swap: var NUndoSwap, skip: NUndoSkip) =
  swap.makeCurrent(sideRead)
  const head = sizeof(NUndoSkip)
  # Locate Swap to Seeking
  let pos = skip.pos + head
  setFilePos(swap.file, pos)
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
  let pos = seek.pos + head
  setFilePos(swap.file, pos)
  swap.posRead = pos

proc read*(swap: var NUndoSwap, data: pointer, size: int) =
  swap.makeCurrent(sideRead)
  swap.posRead += size
  # Read Buffer From Current Swap Seeking
  if readBuffer(swap.file, data, size) != size:
    echo "[WARNING] corrupted read at: ", swap.posRead
    assert false

proc readSkip*(swap: var NUndoSwap): NUndoSkip =
  const head = sizeof(NUndoSkip)
  swap.read(addr result, head)
  assert result.pos == swap.posRead - head

proc readSeek*(swap: var NUndoSwap): NUndoSeek =
  const head = sizeof(NUndoSeek)
  swap.read(addr result, head)
  assert result.pos == swap.posRead - head

proc skipSeek*(swap: var NUndoSwap): NUndoSeek =
  result = swap.readSeek()
  # Skip Seeking Bytes
  swap.posRead += result.bytes
  setFilePos(swap.file, swap.posRead)
