# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
from math import cos, sin
import canvas

type
  NCanvasMatrix = array[9, cfloat]
  NCanvasTransform = object
    mirror*: bool
    x*, y*: cfloat
    zoom*, angle*: cfloat
  NCanvasView* = object
    canvas*: ptr NCanvas
    transform*: NCanvasTransform
    # OpenGL 3.3 Canvas
    program, pbo: cuint
    textures, unused: seq[cuint]
    # Affine Matrix Cache
    matrix0, matrix1: NCanvasMatrix

# --------------------
# Canvas View Creation
# --------------------

proc createCanvasView*(): NCanvasView =
  discard

# ----------------------------
# Canvas View Affine Transform
# ----------------------------

# <- [Translate][Rotate][Scale][Translate Center] <-
proc affine(view: var NCanvasView) =
  let
    a = addr view.transform
    m = addr view.matrix0
    # Scale, Zoom
    cs = cos(a.angle) * a.zoom
    ss = sin(a.angle) * a.zoom
  var # Center Position
    cx = cfloat(view.canvas.w) * 0.5
    cy = cfloat(view.canvas.h) * 0.5
  # Calculate Scale
  m[0] = cs
  m[3] = ss
  if a.mirror:
    m[0] = -m[0]
    m[3] = -m[3]
    cy = -cy
  m[1] = -ss
  m[4] = cs
  # Calculate Translate
  m[2] = a.x - cx * cs - cy * ss
  m[5] = a.y - cx * ss - cy * cs
  # Calculate Homogeneous Affine
  m[6] = 0.0; m[7] = 0.0; m[8] = 1.0
  
# -> [Translate][Rotate][Scale][Translate Center] ->
proc inverse(view: var NCanvasView) =
  let
    a = addr view.transform
    m = addr view.matrix0
    # Position
    x = a.x
    y = a.y
    # Scale, Zoom
    zoom = a.zoom
    cs = cos(a.angle) * zoom
    ss = sin(a.angle) * zoom
    rcp = 1.0 / zoom
  var # Center Position
    cx = cfloat(view.canvas.w) * 0.5
    cy = cfloat(view.canvas.h) * 0.5
  # Calculate Scale
  m[0] = cs * rcp
  m[1] = ss * rcp
  # Calculate Position
  m[2] = (x * cs + y * ss - cx * zoom) * rcp
  if a.mirror:
    m[0] = -m[0]
    m[1] = -m[1]
    m[2] = -m[2]
    cy = -cy
  # Calculate Scale
  m[3] = -ss * rcp
  m[4] = cs * rcp
  # Calculate Position
  m[5] = (x * ss - y * cs - cy * zoom) * rcp
  # Calculate Homogeneous Affine
  m[6] = 0.0; m[7] = 0.0; m[8] = 1.0

# ----------------------------
# Canvas View Update Transform
# ----------------------------

proc upload(view: var NCanvasView) =
  discard

proc update*(view: var NCanvasView, force: bool) =
  # Calculate Matrix
  view.affine()
  view.inverse()
  # Upload Canvas Image
  view.upload()
