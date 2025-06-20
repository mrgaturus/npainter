# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2025 Cristian Camilo Ruiz <mrgaturus>
import math

type
  NShapeEval = proc (c: NShapeCurve, s, t: float32): NShapePoint {.nimcall.}
  NShapePoints* = seq[NShapePoint]
  NShapeCurve* = array[4, NShapePoint]
  NShapePoint* = object
    x*, y*: float32
  # Shape Basic Prepare
  NShapeRound* {.size: 4.} = enum
    curveNone
    curveBezier
    curveCatmull
  NShapeRod* = object
    p0*, p1*: NShapePoint
    angle*: float32
    # Rod Snapping
    square*: bool
    center*: bool
  # Shape Basic Figures
  NShapeBasic* = object
    tmp0: NShapePoints
    tmp: NShapePoints
    cache: NShapePoints
    points*: NShapePoints
    # Basic Rod Location
    x*, y*, w*, h*: float32
    rod: NShapeRod
    # Basic Descriptor
    curve*: NShapeRound
    round*, inset*: float32
    angle*: float32
    sides*: int32
    done: bool

proc point(x, y: float32): NShapePoint {.inline.} = 
  NShapePoint(x: x, y: y)

proc `+`(a, b: NShapePoint): NShapePoint =
  NShapePoint(x: a.x + b.x, y: a.y + b.y)

proc `-`(a, b: NShapePoint): NShapePoint =
  NShapePoint(x: a.x - b.x, y: a.y - b.y)

proc `*`(a: NShapePoint, c: float32): NShapePoint =
  NShapePoint(x: a.x * c, y: a.y * c)

proc lerp(p0, p1: NShapePoint, t: float32): NShapePoint =
  result = p0 + (p1 - p0) * t

proc angle(p0, p1: NShapePoint): float32 =
  result = arctan2(p1.y - p0.y, p1.x - p0.x)
  if result < 0.0: result += 2.0 * PI

# ----------------------------------
# Basic Shape Figure: Prepare Figure
# ----------------------------------

proc restore(p: var NShapePoint, p0: NShapePoint, oc, os: float32) =
  let x = p.x; let y = p.y
  p.x = p0.x + (x * oc - y * os)
  p.y = p0.y + (x * os + y * oc)

proc restore(rod: var NShapeRod, ro0: NShapeRod) =
  let oc = cos(rod.angle)
  let os = sin(rod.angle)
  restore(rod.p0, ro0.p0, oc, os)
  restore(rod.p1, ro0.p0, oc, os)

proc origin(rod: var NShapeRod) =
  let oc = cos(-rod.angle)
  let os = sin(-rod.angle)
  # Remove Rod Rotation
  let x = rod.p1.x - rod.p0.x
  let y = rod.p1.y - rod.p0.y
  rod.p0 = default(NShapePoint)
  rod.p1.x = x * oc - y * os
  rod.p1.y = x * os + y * oc

proc adjust(rod: var NShapeRod) =
  if rod.square:
    let w = abs(rod.p1.x)
    let h = abs(rod.p1.y)
    let m = max(w, h)
    # Apply Square Size
    rod.p1.x = copySign(m, rod.p1.x)
    rod.p1.y = copySign(m, rod.p1.y)
  if rod.center:
    rod.p0.x = -rod.p1.x
    rod.p0.y = -rod.p1.y

proc prepare*(basic: var NShapeBasic, rod: NShapeRod) =
  basic.rod = rod
  let ro0 = addr basic.rod
  ro0[].origin(); ro0[].adjust()
  basic.w = abs(ro0.p0.x - ro0.p1.x)
  basic.h = abs(ro0.p0.y - ro0.p1.y)
  # Prepare Basic Location
  ro0[].restore(rod)
  basic.x = (ro0.p0.x + ro0.p1.x) * 0.5
  basic.y = (ro0.p0.y + ro0.p1.y) * 0.5
  basic.angle = 0.0
  basic.rod = rod

# ---------------------------------
# Basic Shape Figure: Smooth Curves
# ---------------------------------

func bezier(c: NShapeCurve, s, t: float32): NShapePoint =
  var w0 = 1.0 - t
  let w1 = (t + t) * w0
  let w2 = t * t
  # Calculate Bezier
  w0 *= w0; result =
    c[0] * w0 +
    c[1] * w1 +
    c[2] * w2

func catmull(c: NShapeCurve, s, t: float32): NShapePoint =
  let t2 = t * t
  let t3 = t2 * t
  # Calculate Coeffients
  let w0 = s * (2.0 * t2 - t3 - t)
  let w1 = s * (t2 - t3)
  let w2 = (2.0 * t3 - 3.0 * t2 + 1.0)
  let w3 = (3.0 * t2 - 2.0 * t3)
  result = # Calculate Catmull
    (c[0] * w0) +
    (c[1] * w1) +
    (c[1] * w2) -
    (c[2] * w0) +
    (c[2] * w3) -
    (c[3] * w1)

# ------------------------------------
# Basic Shape Figure: Smooth Subdivide
# ------------------------------------

func collinear(p0, p1, p: NShapePoint): bool =
  const tol: float32 = 8.0
  # Check if p is inside line p0-p1
  let c0 = (p.x - p0.x) * (p1.y - p0.y)
  let c1 = (p.y - p0.y) * (p1.x - p0.x)
  result = abs(c0 - c1) < tol

proc subdivide(basic: var NShapeBasic, fn: NShapeEval, c: NShapeCurve) =
  let s = basic.round
  # Initialize Key Subdivision
  var keys {.noinit.}: array[9, NShapePoint]
  var step: float32 = 1.0 / 8.0
  var t: float32 = 0.0
  for i in 0 ..< 9:
    keys[i] = fn(c, s, t)
    t += step
  # Calculate Subdivision
  for i in 0 ..< 8:
    step = 1.0 / 8.0
    let t0 = step * float32(i)
    # Prepare First Subdivision
    setLenUninit(basic.tmp, 2)
    basic.tmp[0] = keys[i + 0]
    basic.tmp[1] = keys[i + 1]
    # Subdivide Line Segment
    var subdivide = true
    while subdivide:
      subdivide = false
      t = t0 + step * 0.5
      let cap = len(basic.tmp) * 2 - 1
      setLenUninit(basic.tmp0, cap)
      # Prepare Key Points
      for j, p in pairs(basic.tmp):
        basic.tmp0[j shl 1] = p
      # Subdivide Key Points
      var j = 1; while j < cap:
        let p = fn(c, s, t)
        let p0 = basic.tmp0[j - 1]
        let p1 = basic.tmp0[j + 1]
        subdivide = subdivide or
          not collinear(p0, p1, p)
        # Store Subdivision
        basic.tmp0[j] = p
        j += 2; t += step
      swap(basic.tmp, basic.tmp0)
      step *= 0.5
    # Append to Points
    basic.points.add(basic.tmp)
    setLenUninit(basic.points,
      basic.points.len - 1)

# --------------------------
# Basic Shape Figure: Smooth
# --------------------------

proc smoothCatmull(basic: var NShapeBasic) =
  var c {.noinit.}: NShapeCurve
  setLen(basic.points, 0)
  # Subdivide Points
  let l = len(basic.cache)
  var i = l; while i < l + l:
    c[0] = basic.cache[(i - 1) mod l]
    c[1] = basic.cache[(i + 0) mod l]
    c[2] = basic.cache[(i + 1) mod l]
    c[3] = basic.cache[(i + 2) mod l]
    basic.subdivide(catmull, c); inc(i)
  # Replace Cached Points
  swap(basic.cache, basic.points)
  setLen(basic.points, 0)

proc smoothBezier(basic: var NShapeBasic) =
  let t = clamp(basic.round, 0.0, 1.0) * 0.5
  var c {.noinit.}: NShapeCurve
  setLen(basic.points, 0)
  # Subdivide Points
  let l = len(basic.cache)
  var i = l; while i < l + l:
    c[0] = basic.cache[(i - 1) mod l]
    c[1] = basic.cache[(i + 0) mod l]
    c[2] = basic.cache[(i + 1) mod l]
    # Calculate Bezier Corner
    c[0] = lerp(c[1], c[0], t)
    c[2] = lerp(c[1], c[2], t)
    basic.subdivide(bezier, c); inc(i)
  # Replace Cached Points
  swap(basic.cache, basic.points)
  setLen(basic.points, 0)

# -----------------------------
# Basic Shape Figure: Raw Shape
# -----------------------------

proc rawBegin*(basic: var NShapeBasic) =
  setLen(basic.cache, 0)
  setLen(basic.points, 0)
  basic.done = false

proc rawPush*(basic: var NShapeBasic, p: NShapePoint) {.inline.} =
  if basic.done: return
  basic.cache.add(p)

proc rawEnd*(basic: var NShapeBasic) =
  if basic.done: return
  basic.done = true
  # Apply Brush Smooth
  if basic.round != 0.0:
    case basic.curve
    of curveNone: discard
    of curveBezier: basic.smoothBezier()
    of curveCatmull: basic.smoothCatmull()

proc rawPoints*(basic: var NShapeBasic, p: NShapePoints) =
  basic.rawBegin()
  basic.cache = p
  basic.rawEnd()
  # Return Processed Points
  swap(basic.cache, basic.points)

# -----------------------------
# Basic Shape Figure: Rectangle
# -----------------------------

proc roundtangle(basic: var NShapeBasic): bool =
  let w = basic.w; let h = basic.h
  let r = basic.round * min(w, h) * 0.5
  result = r > 1.0
  if not result: return result
  let count = int32 log2(r).ceil() * 2.0
  # Define Corner Angles
  const angles = [
    point(PI, 1.5 * PI),
    point(1.5 * PI, 2.0 * PI),
    point(0.0, PI * 0.5),
    point(PI * 0.5, PI)
  ]
  # Define Corner Centers
  let corners = [
    point(r, r),
    point(w - r, r),
    point(w - r, h - r),
    point(r, h - r)
  ]
  # Calculate Polygon
  for i in 0 ..< 4:
    let c = corners[i]
    let a = angles[i]
    # Calculate Corner
    let da = a.y - a.x
    for j in 0 ..< count:
      let angle = a.x + (j / count) * da
      var p {.noinit.}: NShapePoint
      # Calculate Corner Point
      p.x = c.x + r * cos(angle)
      p.y = c.y + r * sin(angle)
      basic.cache.add(p)

proc rectangle*(basic: var NShapeBasic) =
  let c0 = basic.curve
  basic.curve = curveNone
  # Rounded Rectangle
  basic.rawBegin()
  if basic.roundtangle():
    basic.rawEnd()
    basic.curve = c0
    return
  # Simple Rectangle
  let w = basic.w
  let h = basic.h
  setLen(basic.cache, 4)
  basic.cache[0] = point(0, 0)
  basic.cache[1] = point(w, 0)
  basic.cache[2] = point(w, h)
  basic.cache[3] = point(0, h)
  # Finalize Shape
  basic.rawEnd()
  basic.curve = c0

# --------------------------
# Basic Shape Figure: Convex
# --------------------------

proc convex*(basic: var NShapeBasic) =
  let
    sides = basic.sides
    sx = float32(basic.w) * 0.5
    sy = float32(basic.h) * 0.5
    theta = (2.0 * PI) / float32(sides)
  # Calculate Convex Polygon
  basic.rawBegin()
  if sides < 3: return
  var o: float32 = -PI * 0.5
  for i in 0 ..< sides:
    let ox = cos(o)
    let oy = sin(o)
    # Calculate Convex Point
    var p {.noinit.}: NShapePoint
    p.x = sx + ox * sx
    p.y = sy + oy * sy
    basic.cache.add(p)
    # Next Angle
    o += theta
  # Finalize Shape
  basic.rawEnd()

proc circle*(basic: var NShapeBasic) =
  let c0 = basic.curve
  let s0 = basic.sides
  # Calculate Circle
  let d = max(basic.w, basic.h)
  if d < 1.0: basic.rawBegin(); return
  basic.sides = int32 log2(d).ceil() * 8.0
  basic.curve = curveNone
  basic.convex()
  # Restore Attritues
  basic.curve = c0
  basic.sides = s0

# ------------------------
# Basic Shape Figure: Star
# ------------------------

proc star*(basic: var NShapeBasic) =
  let
    inset = basic.inset
    sides = basic.sides * 2
    sx = float32(basic.w) * 0.5
    sy = float32(basic.h) * 0.5
    theta = (2.0 * PI) / float32(sides)
  # Calculate Star Polygon
  basic.rawBegin()
  if sides < 3: return
  var o: float32 = -PI * 0.5
  for i in 0 ..< sides:
    let ox = cos(o)
    let oy = sin(o)
    var p {.noinit.}: NShapePoint
    # Calculate Star Point
    p.x = ox * sx
    p.y = oy * sy
    if (i and 1) == 1:
      p.x *= inset
      p.y *= inset
    p.x += sx
    p.y += sy
    # Next Angle
    basic.cache.add(p)
    o += theta
  # Finalize Shape
  basic.rawEnd()

# -----------------------------
# Basic Shape Figure: Transform
# -----------------------------

proc rotate*(basic: var NShapeBasic, p: NShapePoint) =
  let rod = addr basic.rod
  let p0 = point(basic.x, basic.y)
  # Calculate Rotation Angle
  let a0 = angle(p0, rod.p1)
  let a1 = angle(p0, p)
  basic.angle = a1 - a0

proc calculate*(basic: var NShapeBasic) =
  let
    a0 = basic.rod.angle
    ox = float32(basic.w) * 0.5
    oy = float32(basic.h) * 0.5
    oc = cos(a0 + basic.angle)
    os = sin(a0 + basic.angle)
    x = basic.x
    y = basic.y
  # Apply Rotate -> Translate to Points
  var i = 0
  let l = len(basic.cache)
  setLen(basic.points, l)
  while i < l:
    var p = basic.cache[i]
    let x0 = p.x - ox
    let y0 = p.y - oy
    # Store Rotated and Translated
    p.x = (x0 * oc - y0 * os) + x
    p.y = (x0 * os + y0 * oc) + y
    basic.points[i] = p
    inc(i)
