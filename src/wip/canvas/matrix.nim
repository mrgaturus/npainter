# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
from math import cos, sin
import ../../omath

type
  NCanvasPoint* = tuple[x, y: cfloat]
  NCanvasMatrix* = array[9, cfloat]
  NCanvasProjection* = array[16, cfloat]
  NCanvasAffine* = object
    mirror*: bool
    x*, y*: cfloat
    zoom*, angle*: cfloat
    # Canvas & Viewport Sizes
    cw*, ch*: cint
    vw*, vh*: cint
    # Matrix Calculation
    projection*: NCanvasProjection
    model0*, model1*: NCanvasMatrix

# -------------------------------
# Canvas Affine Matrix Calculator
# -------------------------------

# <- [Translate][Rotate][Scale][Translate Center] <-
proc affine(a: var NCanvasAffine) =
  let
    m = addr a.model0
    # Scale, Zoom
    cs = cos(a.angle) * a.zoom
    ss = sin(a.angle) * a.zoom
  var # Center Position
    cx = cfloat(a.cw) * 0.5
    cy = cfloat(a.ch) * 0.5
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
proc inverse(a: var NCanvasAffine) =
  let
    m = addr a.model1
    # Position
    x = a.x
    y = a.y
    # Scale, Zoom
    zoom = a.zoom
    cs = cos(a.angle) * zoom
    ss = sin(a.angle) * zoom
    rcp = 1.0 / zoom
  var # Center Position
    cx = cfloat(a.cw) * 0.5
    cy = cfloat(a.ch) * 0.5
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
# Canvas Transform Calculation
# ----------------------------

proc calculate*(a: var NCanvasAffine) =
  # Calculate Model
  a.affine()
  a.inverse()
  # Calculate Projection
  guiProjection(addr a.projection, 
    cfloat a.vw, cfloat a.vh)

proc inverse*(a: NCanvasAffine; x, y: cfloat): NCanvasPoint =
  let m = unsafeAddr a.model1
  result.x = a.x * m[0] + a.y * m[1] + m[2]
  result.y = a.y * m[3] + a.y * m[4] + m[5]
