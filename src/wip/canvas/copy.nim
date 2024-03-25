# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>

{.compile: "copy0.c".}
{.compile: "copy1.c".}
{.push header: "wip/canvas/canvas.h".}

type
  NCanvasBG* {.importc: "canvas_bg_t".} = object
    color0: cuint
    color1: cuint
    # Checker Size
    shift*: cint
  NCanvasCopy* {.importc: "canvas_copy_t".} = object
    x256*, y256*: cint
    x*, y*, w*, h*: cint
    bg*: NCanvasBG
    # Copy Buffers
    w0, h0, s0: cint
    buffer0: pointer
    buffer1: pointer

{.push importc.}

# Canvas Stream Copy + Background
proc canvas_copy_stream(copy: ptr NCanvasCopy)
proc canvas_copy_white(copy: ptr NCanvasCopy)
proc canvas_copy_color(copy: ptr NCanvasCopy)
# Canvas Stream Copy + Pattern
proc canvas_copy_checker(copy: ptr NCanvasCopy)
proc canvas_gen_checker(bg: ptr NCanvasBG)
# Canvas Stream Copy - Padding
proc canvas_copy_padding(copy: ptr NCanvasCopy)

{.pop.} # importc
{.pop.} # canvas.h

# ---------------------------
# Canvas Background Preparing
# ---------------------------

func color(r, g, b: cuint): cuint {.inline.} =
  r or (g shl 8) or (b shl 16) or (0xFF shl 24)

proc color0*(bg: var NCanvasBG, r, g, b: cuint) =
  bg.color0 = color(r, g, b)

proc color1*(bg: var NCanvasBG, r, g, b: cuint) =
  bg.color1 = color(r, g, b)

# ---------------------
# Canvas Copy Preparing
# ---------------------

proc src*(copy: var NCanvasCopy, buffer: pointer, w, h, stride: cint) =
  copy.w0 = w
  copy.h0 = h
  # Source Buffer
  copy.s0 = stride
  copy.buffer0 = buffer

proc dst*(copy: var NCanvasCopy, buffer: pointer) =
  copy.buffer1 = buffer

# --------------------
# Canvas Copy Dispatch
# --------------------

proc stream*(copy: var NCanvasCopy) =
  discard
#kfjsjkdjskd im here