# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>

type
  NUndoSeek* = object
    seek*: int64
    bytes*: int64
  NUndoSkip* = object
    seek*: NUndoSeek
    prev*, next*: int64
  # Undo Swap File
  NUndoSwap* = object
    swap: File
    # Swap Seeking
    seekWrite: NUndoSeek
    seekRead: NUndoSeek

# ------------------------------
# Undo Swap Creation/Destruction
# ------------------------------

proc configure*(swap: var NUndoSwap) =
  discard

proc destroy*(swap: var NUndoSwap) =
  `=destroy`(swap)
