# Scanline Using Fast Voxel Traversal
# Used by Canvas Render and Brush Engine
# -------------------------------
# Convex Quads With Clockwise Order
# Transformed With Affine Matrix
# 0 -------------------- 1
# |                      |
# |                      |
# |                      |
# 3 -------------------- 2
from math import floor

type
  # Primitives
  NPoint* = object
    x*, y*: float32
  NQuad* = array[4, NPoint]
  # Bounding Box
  NBoundBox = object
    xmin, xmax: float32
    ymin, ymax: float32
  # Voxel Scanline
  NLane = object
    min, max: int16
  NScanline* = object
    # Voxel Count
    n: int32
    # Dimensions
    w, h: int16
    # Position
    x, y: int16
    # X, Y Steps
    sx, sy: int8
    # Voxel Traversal DDA
    dx, dy, error: float32
    # Scanline Lanes Buffer
    lanes: array[64, NLane]
    # Scanline Interval
    y1, y2: int16

# ---------------------------
# BOUNDING BOX - SORT HELPERS
# ---------------------------

proc aabb(quad: NQuad): NBoundBox =
  var # Iterator
    i = 1
    p = quad[0]
  # Set XMax/XMin
  result.xmin = p.x
  result.xmax = p.x
  # Set YMax/YMin
  result.ymin = p.y
  result.ymax = p.y
  # Build AABB
  while i < 4:
    p = quad[i]
    # Check XMin/XMax
    if p.x < result.xmin:
      result.xmin = p.x
    elif p.x > result.xmax:
      result.xmax = p.x
    # Check YMin/YMax
    if p.y < result.ymin:
      result.ymin = p.y
    elif p.y > result.ymax:
      result.ymax = p.y
    # Next Point
    inc(i)

proc sort(quad: var NQuad, box: NBoundBox) =
  var sorted: NQuad
  # Sort Using AABB
  for p in quad:
    if p.y == box.ymax: 
      sorted[0] = p
    elif p.x == box.xmin: 
      sorted[1] = p
    elif p.y == box.ymin: 
      sorted[2] = p
    elif p.x == box.xmax: 
      sorted[3] = p
  # Replace Sorted
  quad = sorted

proc straight(quad: NQuad, box: NBoundBox): bool =
  for p in quad: # At least one equal to xmin, ymin
    if p.x == box.xmin and p.y == box.ymin:
      return true # Is Straight

# -------------------------------------
# A FAST VOXEL TRAVERSAL 1.0 Voxel Unit
# -------------------------------------

proc line(dda: var NScanline, a, b: NPoint) =
  let # Point Distances
    dx = abs(b.x - a.x)
    dy = abs(b.y - a.y)
    # Floor X Coordinates
    x1 = floor(a.x)
    y1 = floor(a.y)
    # Floor Y Coordinates
    x2 = floor(b.x)
    y2 = floor(b.y)
  # Reset Count
  dda.n = 1
  # X Incremental
  if dx == 0:
    dda.sx = 0 # No X Step
    dda.error = high(float32)
  elif b.x > a.x:
    dda.sx = 1 # Positive
    dda.n += int32(x2 - x1)
    dda.error = (x1 - a.x + 1) * dy
  else:
    dda.sx = -1 # Negative
    dda.n += int32(x1 - x2)
    dda.error = (a.x - x1) * dy
  # Y Incremental
  if dy == 0:
    dda.sy = 0 # No Y Step
    dda.error -= high(float32)
  elif b.y > a.y:
    dda.sy = 1 # Positive
    dda.n += int32(y2 - y1)
    dda.error -= (y1 - a.y + 1) * dx
  else:
    dda.sy = -1 # Negative
    dda.n += int32(y1 - y2)
    dda.error -= (a.y - y1) * dx
  # Set Start Position
  dda.x = int16(x1)
  dda.y = int16(y1)
  # Set DDA Deltas
  dda.dx = dx
  dda.dy = dy

proc lane(dda: var NScanline): ptr NLane =
  # Check Current Y Bounds
  if dda.y >= 0 and dda.y < dda.h:
    result = addr dda.lanes[dda.y]

proc left(dda: var NScanline) =
  var lane = dda.lane()
  # Do DDA Loop
  while dda.n > 0:
    # Clamp to Bounds
    if not isNil(lane):
      lane.min = max(dda.x, 0)
    # Next Lane
    if dda.error > 0:
      dda.y += dda.sy
      dda.error -= dda.dx
      # Lookup Lane
      lane = dda.lane()
    else: # Next X
      dda.x += dda.sx
      dda.error += dda.dy
    # Next Voxel
    dec(dda.n)

proc right(dda: var NScanline) =
  var lane = dda.lane()
  # Do DDA Loop
  while dda.n > 0:
    # Clamp to Bounds
    if not isNil(lane):
      lane.max = 
        min(dda.x, dda.w - 1)
    # Next Lane
    if dda.error > 0:
      dda.y += dda.sy
      dda.error -= dda.dx
      # Lookup Lane
      lane = dda.lane()
    else: # Next X
      dda.x += dda.sx
      dda.error += dda.dy
    # Next Voxel
    dec(dda.n)

# ----------------------------
# SCANLINE CONFIGURATION PROCS
# ----------------------------

proc dimensions*(dda: var NScanline, w, h: int16) =
  # Ensure is not 0
  assert(w > 0 and h > 0)
  # Set Dimensions up to 64
  dda.w = # Clip
    if w > 64: 64
    else: w
  dda.h = # Clip
    if h > 64: 64
    else: h

# Rectangle Scanline
proc rectangle(dda: var NScanline, aabb: NBoundBox) =
  # Define Y Interval
  dda.y1 = floor(aabb.ymin).int16
  dda.y2 = floor(aabb.ymax).int16
  # Clamp Y Interval
  if dda.y1 < 0: 
    dda.y1 = 0
  if dda.y2 >= dda.h:
    dda.y2 = dda.h - 1
  # Define X Lanes
  var lane: NLane
  lane.min = floor(aabb.xmin).int16
  lane.max = floor(aabb.xmax).int16
  # Clamp X Lanes
  if lane.min < 0:
    lane.min = 0
  if lane.max >= dda.w:
    lane.max = dda.w - 1
  # Define Lanes
  for y in dda.y1..dda.y2:
    dda.lanes[y] = lane

# Voxel Traversal Scanline, for Rotated
proc traversal(dda: var NScanline, quad: NQuad) =
  # Define Y Interval
  dda.y1 = floor(quad[2].y).int16
  dda.y2 = floor(quad[0].y).int16
  # Clamp Intervals
  if dda.y1 < 0: 
    dda.y1 = 0
  if dda.y2 >= dda.h: 
    dda.y2 = dda.h - 1
  # Calculate Minimun/Left Lanes
  dda.line(quad[0], quad[1]); dda.left()
  dda.line(quad[2], quad[1]); dda.left()
  # Calculate Maximun/Right Lanes
  dda.line(quad[2], quad[3]); dda.right()
  dda.line(quad[0], quad[3]); dda.right()

proc scanline*(dda: var NScanline, quad: NQuad, unit: float32) =
  var region = quad
  block: # Scale to Unit
    let u = 1 / unit
    for p in mitems(region):
      p.x *= u; p.y *= u
  # Perform Scanline
  let aabb = region.aabb
  if straight(region, aabb):
    dda.rectangle(aabb)
  else: # Voxel Traversal
    region.sort(aabb)
    dda.traversal(region)

# ---------------------------------
# VOXEL TRAVERSAL SCANLINE ITERATOR
# ---------------------------------

iterator voxels*(dda: var NScanline): tuple[x, y: int16] =
  var # Intervals
    y1 = dda.y1
    y2 = dda.y2
    lane: NLane
  # Iterate Each Y
  while y1 <= y2:
    lane = dda.lanes[y1]
    # Iterate Each X
    while lane.min <= lane.max:
      yield (x: lane.min, y: y1)
      inc(lane.min) # Next X
    inc(y1) # Next Y
