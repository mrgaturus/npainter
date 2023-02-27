# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
from matrix import
  NCanvasPoint, inverse
import render

type
  NCanvasEdge = object
    a, b, c: cint
  NCanvasTrivial = object
    reject, accept: cint
  NCanvasBounds = object
    x0, x1, y0, y1: cint
  NCanvasQuad = array[4, NCanvasPoint]
  NCanvasCulling = object
    trivial: array[4, NCanvasTrivial]
    edges: array[4, NCanvasEdge]
    # Culling Region
    bounds: NCanvasBounds

# ------------------------
# Canvas Culling Preparing
# ------------------------

proc edge(a, b: NCanvasPoint): NCanvasEdge =
  let
    x0 = cint(a.x * 16.0)
    y0 = cint(a.y * 16.0)
    x1 = cint(b.x * 16.0)
    y1 = cint(b.y * 16.0)
    # Define Incrementals
  result.a = (y0 - y1) shl 4
  result.b = (x1 - x0) shl 4
  result.c = (x0 * y1) - (x1 * y0)

proc trivial(e: NCanvasEdge): NCanvasTrivial =
  var ox, oy: cint
  # Calculate Reject
  ox = if e.a >= 0: 256 else: 0
  oy = if e.b >= 0: 256 else: 0
  result.reject = e.a * ox + e.b * oy + e.c
  # Calculate Accept
  ox = if e.a >= 0: 0 else: 256
  oy = if e.b >= 0: 0 else: 256
  result.accept = e.a * ox + e.b * oy + e.c

proc bounds(quad: NCanvasQuad, w, h: cint): NCanvasBounds =
  var
    x = cint(quad[0].x)
    y = cint(quad[0].y)
  # Define First Point
  result.x0 = x
  result.y0 = y
  result.x1 = x
  result.y1 = y
  for i in 1 ..< 4:
    # Current Point 
    x = cint(quad[i].x)
    y = cint(quad[i].y)
    # Calculate Bounding Box
    result.x0 = min(x, result.x0)
    result.y0 = min(y, result.y0)
    result.x1 = max(x, result.x1)
    result.y1 = max(y, result.y1)
  # Clamp With Canvas Size
  result.x0 = max(0, result.x0)
  result.y0 = max(0, result.y0)
  result.x1 = min(w, result.x1)
  result.y1 = max(h, result.y1)

proc prepare*(view: NCanvasViewport, cull: var NCanvasCulling) =
  let 
    m = view.affine
    # Canvas Dimensions
    w = cfloat(m.cw)
    h = cfloat(m.ch)
  var 
    p: NCanvasQuad
  # Define Points
  p[0] = m.inverse(0, 0)
  p[1] = m.inverse(w, 0)
  p[2] = m.inverse(w, h)
  p[3] = m.inverse(0, h)
  # Create Edge Equations
  cull.edges[0] = edge(p[0], p[1])
  cull.edges[1] = edge(p[1], p[2])
  cull.edges[2] = edge(p[2], p[3])
  cull.edges[3] = edge(p[3], p[0])
  # Calculate Trivial Checks
  cull.trivial[0] = trivial(cull.edges[0])
  cull.trivial[1] = trivial(cull.edges[1])
  cull.trivial[2] = trivial(cull.edges[2])
  cull.trivial[3] = trivial(cull.edges[3])
  # Calculate Bounding Box
  cull.bounds = p.bounds(m.cw, m.ch)

# ----------------------
# Canvas Culling Perform
# ----------------------

proc perform(view: NCanvasViewport, cull: var NCanvasCulling) =
  discard
