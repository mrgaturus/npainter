# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2021 Cristian Camilo Ruiz <mrgaturus>
{.compile: "distort/sample.c".}
{.compile: "distort/triangle.c".}
{.compile: "distort/rasterize.c".}
{.compile: "distort/surface.c".}
{.push header: "distort/distort.h", used.}

type
  NTriangleFunc = distinct pointer
  NTriangleEquation {.importc: "equation_t".} = object
  NTriangleVertex {.importc: "vertex_t".} = object
    x, y, u, v: cfloat
  NTriangle = # Pass as Pointer
    array[3, NTriangleVertex]
  NTriangleDerivative {.importc: "derivative_t".} = object
  NTriangleBinning {.importc: "binning_t".} = object
  NTriangleSampler {.importc: "sampler_t".} = object
    # SW, SH -> Repeat Size
    # W, H -> Texture Size
    sw, sh, w, h: cint
    buffer: ptr cshort
    # Sampler Func
    fn: NTriangleFunc
  NTriangleRender {.importc: "fragment_t".} = object
    x, y, w, h: cint
    # Source Pixels Sampler
    sampler: ptr NTriangleSampler
    # Target Pixels
    dst_w, dst_h: cint
    dst: ptr cshort
  # -------------------------------------------
  NSurfaceVec2D {.importc: "vec2_t".} = object
    x, y: cfloat # Vector2 is only relevant here
  NSurfaceBilinear {.importc: "perspective_t".} = object
  NSurfaceCatmull {.importc: "catmull_t".} = object

{.push importc.}

# Pixel Resampling Function Pointers
proc sample_nearest(render: ptr NTriangleRender, u, v: cfloat) {.used.}
proc sample_bilinear(render: ptr NTriangleRender, u, v: cfloat) {.used.}
proc sample_bicubic(render: ptr NTriangleRender, u, v: cfloat) {.used.}

# Triangle Equation
proc eq_winding(v: ptr NTriangle): int32
proc eq_calculate(eq: ptr NTriangleEquation, v: ptr NTriangle)
proc eq_gradient(eq: ptr NTriangleEquation, v: ptr NTriangle)
proc eq_derivative(eq: ptr NTriangleEquation, dde: ptr NTriangleDerivative)

# Triangle Binning, Multiply By A Power Of Two
proc eq_binning(eq: ptr NTriangleEquation, bin: ptr NTriangleBinning, shift: cint)
# Triangle Binning Steps
proc eb_step_xy(bin: ptr NTriangleBinning, x, y: cint)
proc eb_step_x(bin: ptr NTriangleBinning)
proc eb_step_y(bin: ptr NTriangleBinning)
# Triangle Binning Trivially Count
proc eb_check(bin: ptr NTriangleBinning): int32

# Triangle Equation Realtime Rendering
proc eq_partial(eq: ptr NTriangleEquation, render: ptr NTriangleRender)
proc eq_full(eq: ptr NTriangleEquation, render: ptr NTriangleRender)
# Triangle Equation Rendering Subpixel Antialiasing Post-Procesing
proc eq_partial_subpixel(eq: ptr NTriangleEquation, dde: ptr NTriangleDerivative, render: ptr NTriangleRender)
proc eq_full_subpixel(eq: ptr NTriangleEquation, dde: ptr NTriangleDerivative, render: ptr NTriangleRender)

# --------------------------------------------
proc perspective_calc(surf: ptr NSurfaceBilinear, v: ptr NSurfaceVec2D, fract: cfloat)
proc perspective_evaluate(surf: ptr NSurfaceBilinear, p: ptr NTriangleVertex)

proc catmull_surface_calc(surf: ptr NSurfaceCatmull, c: ptr NSurfaceVec2D, w, h: cint)
proc catmull_surface_evaluate(surf: ptr NSurfaceCatmull, p: ptr NTriangleVertex)

{.pop.} # -- End Importing Procs
{.pop.} # -- End distort.h
