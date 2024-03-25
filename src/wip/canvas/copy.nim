# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>

{.compile: "copy0.c".}
{.compile: "copy1.c".}
{.push header: "wip/canvas/canvas.h".}

type
  NCanvasBG* {.importc: "canvas_bg_t".} = object
    color0: cuint
    color1: cuint
    # Checker Pattern
    buffer: pointer
    shift: cint
  NCanvasSrc* {.importc: "canvas_src_t".} = object
    w0*, h0*, s0*: cint
    buffer*: pointer
  # Canvas Copy Transfer to PBO
  NCanvasCopy* {.importc: "canvas_copy_t".} = object
    x256*, y256*: cint
    x*, y*, w*, h*: cint
    # Canvas Data
    bg*: NCanvasBG
    src*: NCanvasSrc
    # Canvas PBO Buffer
    buffer*: pointer

{.push importc.}

# Canvas Stream Copy + Background
proc canvas_copy_stream(copy: ptr NCanvasCopy)
proc canvas_copy_white(copy: ptr NCanvasCopy)
proc canvas_copy_color(copy: ptr NCanvasCopy)
# Canvas Stream Copy + Pattern
proc canvas_gen_checker(bg: ptr NCanvasBG)
proc canvas_copy_checker(copy: ptr NCanvasCopy)
# Canvas Stream Padding
proc canvas_copy_padding(copy: ptr NCanvasCopy)

{.pop.} # importc
{.pop.} # canvas.h

# ------------------------
# Canvas Background Colors
# ------------------------

func color(r, g, b: cuint): cuint {.inline.} =
  r or (g shl 8) or (b shl 16) or (0xFF shl 24)

proc color0*(bg: var NCanvasBG, r, g, b: cuint) =
  bg.color0 = color(r, g, b)

proc color1*(bg: var NCanvasBG, r, g, b: cuint) =
  bg.color1 = color(r, g, b)

# -------------------------
# Canvas Background Pattern
# -------------------------

proc pattern*(bg: var NCanvasBG, shift: cint) =
  let
    size = 2 shl shift
    bytes = size * size * sizeof(cuint)
  # Deallocate Previous Buffer
  if not isNil(bg.buffer):
    dealloc(bg.buffer)
  # Allocate Checker Buffer
  bg.buffer = alloc(bytes)
  bg.shift = shift
  # Generate Checker Buffer
  canvas_gen_checker(addr bg)

proc clear*(bg: var NCanvasBG) =
  # Deallocate Previous Buffer
  if not isNil(bg.buffer):
    dealloc(bg.buffer)
  # Remove Shift
  bg.shift = 0
  bg.buffer = nil

# --------------------
# Canvas Copy Dispatch
# --------------------

proc stream*(copy: var NCanvasCopy) =
  let
    bg = copy.bg
    cp = addr copy
  # Stream + Background
  if bg.shift > 1:
    canvas_copy_checker(cp)
  elif bg.color0 == high(cuint):
    canvas_copy_white(cp)
  elif bg.color0 > 0:
    canvas_copy_color(cp)
  # Stream - Background
  else: canvas_copy_stream(cp)
  # Apply Copy Padding
  canvas_copy_padding(cp)
