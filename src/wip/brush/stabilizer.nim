# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2021 Cristian Camilo Ruiz <mrgaturus>

# TODO: Untangle Stroke Objects from brush.nim
# TODO: use NBrushPoint from brush.nim after untangling

type
  NBrushStable = object
    x*, y*: cfloat
    press*, angle*: cfloat
  NBrushStabilizer* = object
    points: array[64, NBrushStable]
    # Stabilizer Options
    capacity*: cint
    count: cint
    # Stabilizer Accumulator
    acc, first: NBrushStable

# -----------------------------
# Brush Stable Point Operations
# -----------------------------

proc broadcast(acc: var NBrushStable, point: NBrushStable, count: cint) =
  let c = cfloat(count)
  acc.x = point.x * c
  acc.y = point.y * c
  acc.press = point.press * c
  acc.angle = point.angle * c

proc decrement(acc: var NBrushStable, point: NBrushStable) =
  acc.x -= point.x
  acc.y -= point.y
  acc.press -= point.press
  acc.angle -= point.angle

proc accumulate(acc: var NBrushStable, point: NBrushStable) =
  acc.x += point.x
  acc.y += point.y
  acc.press += point.press
  acc.angle += point.angle

# -------------------------
# Brush Stabilizer Smoother
# -------------------------

proc accumulate(s: var NBrushStabilizer, point: NBrushStable) =
  let 
    roll = s.count >= s.capacity
    i = s.count mod s.capacity
    p = addr s.points[i]
  # Drecement Current Point
  if roll: decrement(s.acc, p[])
  else: decrement(s.acc, s.first)
  # Accumulate Current Point
  accumulate(s.acc, point)
  # Next Point
  p[] = point
  inc(s.count)

proc average(s: var NBrushStabilizer): NBrushStable =
  let c = 1.0 / cfloat(s.capacity)
  # Apply Average Count
  result = s.acc
  result.x *= c
  result.y *= c
  result.press *= c
  result.angle *= c

# ---------------------------
# Brush Stabilizer Operations
# ---------------------------

proc reset*(s: var NBrushStabilizer, capacity: cint) =
  s.capacity = capacity
  # Reset Index
  s.count = 0
  s.acc = default(NBrushStable)

proc smooth*(s: var NBrushStabilizer; x, y, press, angle: cfloat): NBrushStable =
  result = NBrushStable(x: x, y: y, press: press, angle: angle)
  # Broadcast First Point
  if s.count == 0:
    broadcast(s.acc, result, s.capacity)
    s.first = result
  # Stabilize Point
  s.accumulate(result)
  result = s.average()
