# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
from matrix import
  NCanvasPoint, inverse
import render

type
  NCanvasEdge = object
    a, b, c: cint
  NCanvasTrivial = object
    check0, check1: cint
  NCanvasBounds = object
    x0, y0, x1, y1: cint
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
  result.c = (x0 * y1) - (y0 * x1)

proc trivial(e: NCanvasEdge): NCanvasTrivial =
  var ox, oy: cint
  # Calculate Reject Test
  ox = if e.a >= 0: 256 else: 0
  oy = if e.b >= 0: 256 else: 0
  result.check0 = e.a * ox + e.b * oy + e.c

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
  # Clamp With Canvas Size and Scale
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

# -------------------
# Canvas Culling Step
# -------------------

proc locate(cull: var NCanvasCulling) =
  let
    x = cull.bounds.x0 and 0xFF
    y = cull.bounds.y0 and 0xFF
  var idx: cint; while idx < 4:
    let 
      e = addr cull.edges[idx]
      c = addr cull.trivial[idx]
      # Equation Step
      a = e.a
      b = e.b
    # Locate Trivial Position
    c.check0 += a * x + b * y
    c.check1 = c.check0
    # Arrange Tile Step
    e.a = a shl 8
    e.b = b shl 8
    # Next Tile
    inc(idx)

proc step(cull: var NCanvasCulling, vertical: bool) =
  var idx: cint; while idx < 4:
    let 
      e = addr cull.edges[idx]
      c = addr cull.trivial[idx]
    # Step Trivial Position
    if likely(not vertical):
      c.check0 += e.a
    else:
      c.check0 += e.b
      c.check1 = c.check0
    # Next Tile
    inc(idx)

proc test(cull: var NCanvasCulling): bool =
  var idx, count: cint
  while idx < 4:
    # Test Trivially Rejection
    let check = cull.trivial[idx].check1
    count += cast[cint](check < 0)
  # Return Count
  count == 0

# ----------------------
# Canvas Culling Perform
# ----------------------

proc assemble*(view: var NCanvasViewport, cull: var NCanvasCulling) =
  # Locate Culling First
  view.clear()
  cull.locate()
  # Calculate Tiled Size
  let
    bounds = addr cull.bounds
    x0 = bounds.x0 shr 8
    x1 = bounds.x1 shr 8
    y0 = bounds.y0 shr 8
    y1 = bounds.y1 shr 8
  # Iterate Each Tile
  for y in y0 ..< y1:
    for x in x0 ..< x1:
      if cull.test():
        view.activate(x shl 8, y shl 8)
      # Next Tile
      cull.step(false)
    # Next Row
    cull.step(true)
  # Prepare View Tiles
  view.prepare()
