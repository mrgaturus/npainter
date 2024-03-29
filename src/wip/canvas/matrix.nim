# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
from math import cos, sin, floor
from nogui/values import guiProjection

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
    # Center Position
    cx = -cfloat(a.vw shr 1)
    cy = -cfloat(a.vh shr 1)
    # Scale and Rotation
    cs = cos(a.angle) * a.zoom
    ss = sin(a.angle) * a.zoom
  # Calculate Scale & Rotation
  m[0] = cs
  m[1] = -ss
  m[3] = ss
  m[4] = cs
  # Calculate Translate
  m[2] = cx * cs - cy * ss
  m[5] = cx * ss + cy * cs
  if a.mirror:
    m[0] = -m[0]
    m[1] = -m[1]
    m[2] = -m[2]
  m[2] += a.x
  m[5] += a.y
  # Calculate Affine
  m[6] = 0.0 
  m[7] = 0.0 
  m[8] = 1.0
  
# -> [Translate][Rotate][Scale][Translate Center] ->
proc inverse(a: var NCanvasAffine) =
  let
    m = addr a.model1
    # Center Position
    cx = -cfloat(a.vw shr 1)
    cy = -cfloat(a.vh shr 1)
    # Offset Position
    x = a.x
    y = a.y
    # Scale and Rotation
    zoom = a.zoom
    rcp = 1.0 / zoom
    cs = cos(a.angle)
    ss = sin(a.angle)
  var rcp2 = rcp * rcp
  # Calculate Scale
  m[0] = cs * rcp
  m[1] = ss * rcp
  m[3] = -ss * rcp
  m[4] = cs * rcp
  # Calculate Position
  m[2] = zoom * (ss * y + cx * zoom)
  m[5] = zoom * (cs * y + cy * zoom)
  # Calculate Mirror
  if a.mirror:
    m[0] = -m[0]
    m[2] = -m[2]
    m[3] = -m[3]
    rcp2 = -rcp2
  else:
    m[5] = -m[5]
  # Calculate Position
  m[2] = -(zoom * cs * x + m[2]) * rcp2
  m[5] = (zoom * ss * x + m[5]) * rcp2
  # Calculate Homogeneous Affine
  m[6] = 0.0 
  m[7] = 0.0 
  m[8] = 1.0

# ------------------------------
# Canvas Affine Matrix Configure
# ------------------------------

proc perfect(a: var NCanvasAffine) =
  let
    zoom = a.zoom
    x = a.x / zoom
    y = a.y / zoom
  # Floor Position
  a.x = floor(x) * zoom
  a.y = floor(y) * zoom

proc calculate*(a: var NCanvasAffine) =
  a.perfect()
  # Calculate Model
  a.affine()
  a.inverse()
  # Calculate Projection
  guiProjection(addr a.projection, 
    cfloat a.vw, cfloat a.vh)

# ----------------------------
# Canvas Affine Matrix Mapping
# ----------------------------

proc forward*(a: NCanvasAffine; x, y: cfloat): NCanvasPoint =
  let m = unsafeAddr a.model0
  result.x = x * m[0] + y * m[1] + m[2]
  result.y = x * m[3] + y * m[4] + m[5]

proc inverse*(a: NCanvasAffine; x, y: cfloat): NCanvasPoint =
  let m = unsafeAddr a.model1
  result.x = x * m[0] + y * m[1] + m[2]
  result.y = x * m[3] + y * m[4] + m[5]
