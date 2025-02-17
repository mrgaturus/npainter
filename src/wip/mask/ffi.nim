# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2025 Cristian Camilo Ruiz <mrgaturus>
import ../image/ffi

{.compile: "mask.c".}
{.compile: "outline.c".}
{.compile: "polygon.c".}
{.compile: "unpack.c".}
{.push header: "wip/mask/mask.h".}

type
  NPolyLine* {.importc: "polygon_line_t".} = object
    offset*: cint
    stride*: cint
    # Writer Pointers
    buffer*: pointer
    smooth*: pointer
  # -- Image Mask Operations --
  NMaskCombine* {.importc: "mask_combine_t".} = object
    co*: NImageCombine
    color*: uint64
    alpha*: uint64
  NMaskVertex* = ptr UncheckedArray[uint16]
  NMaskOutline* {.importc: "mask_outline_t".} = object
    tiles*: array[9, pointer]
    ox*, oy*: cint
    # Vertex Output
    log*, count*: cint
    buffer*: NMaskVertex

{.push importc.}

# Polygon Lane Location
proc polygon_line_range*(line: ptr NPolyLine, x0, x1: cint)
proc polygon_line_skip*(line: ptr NPolyLine, y0: cint)
proc polygon_line_clear*(line: ptr NPolyLine)
proc polygon_line_next*(line: ptr NPolyLine)
# Polygon Lane Rasterization
proc polygon_line_simple*(line: ptr NPolyLine)
proc polygon_line_coverage*(line: ptr NPolyLine)
proc polygon_line_smooth*(line: ptr NPolyLine)

# Polygon Combine Mask: unpack.c
proc polygon_mask_blit*(co: ptr NMaskCombine)
proc polygon_mask_union*(co: ptr NMaskCombine)
proc polygon_mask_exclude*(co: ptr NMaskCombine)
proc polygon_mask_intersect*(co: ptr NMaskCombine)
# Polygon Combine Color: unpack.c
proc polygon_color_blit16*(co: ptr NMaskCombine)
proc polygon_color_blit8*(co: ptr NMaskCombine)
proc polygon_color_blend16*(co: ptr NMaskCombine)
proc polygon_color_blend8*(co: ptr NMaskCombine)
proc polygon_color_erase16*(co: ptr NMaskCombine)
proc polygon_color_erase8*(co: ptr NMaskCombine)

# Combine Mask Operations: mask.c
proc combine_mask_union*(co: ptr NMaskCombine)
proc combine_mask_exclude*(co: ptr NMaskCombine)
proc combine_mask_intersect*(co: ptr NMaskCombine)
proc combine_mask_invert*(co: ptr NMaskCombine)
proc combine_mask_outline*(co: ptr NMaskOutline)
# Combine Color to Mask: mask.c
proc convert_color16_mask*(co: ptr NMaskCombine)
proc convert_color8_mask*(co: ptr NMaskCombine)
proc convert_gray16_mask*(co: ptr NMaskCombine)
proc convert_gray8_mask*(co: ptr NMaskCombine)
# Combine Mask to Color: mask.c
proc convert_mask_color16*(co: ptr NMaskCombine)
proc convert_mask_color8*(co: ptr NMaskCombine)
proc convert_mask_blend16*(co: ptr NMaskCombine)
proc convert_mask_blend8*(co: ptr NMaskCombine)
proc convert_mask_erase16*(co: ptr NMaskCombine)
proc convert_mask_erase8*(co: ptr NMaskCombine)
proc convert_mask_clip16*(co: ptr NMaskCombine)
proc convert_mask_clip8*(co: ptr NMaskCombine)

{.pop.} # importc
{.pop.} # header
