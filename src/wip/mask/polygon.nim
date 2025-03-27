# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2025 Cristian Camilo Ruiz <mrgaturus>
import nogui/async/core
import ffi, ../image/ffi

type
  NPolyBounds = object
    x0, y0: int32
    x1, y1: int32
  # Polygon Line Segments
  NPolyPoint* = object
    x*, y*: float32
  NPolyFix = tuple[x, y: int32]
  NPolySegment = tuple[a, b: NPolyFix]
  # -- Polygon Rasterizer: Lane --
  NPolyHits = UncheckedArray[NPolyFix]
  NPolyGather = UncheckedArray[NPolySegment]
  NPolyLane = object
    rast: ptr NPolygon
    offset, skip: int32
    count, cap: int
    # Lane Temporal Buffers
    bucket: ptr NPolyGather
    aux: ptr NPolyHits
    hits: ptr NPolyHits
    smooth: pointer
  # -- Polygon Rasterizer --
  NPolyRule* = enum
    ruleNonZero
    ruleOddEven
  NPolygon* = object
    pool: NThreadPool
    buffer: NImageBuffer
    # Polygon Points
    bounds: NPolyBounds
    points: seq[NPolyFix]
    lanes: seq[NPolyLane]
    # Polygon Properties
    rule*: NPolyRule
    smooth*: bool

# ---------------------------
# Polygon Rasterizer Bounding
# ---------------------------

proc newBounds(): NPolyBounds =
  result = NPolyBounds(
    x0: high int32,
    y0: high int32,
    x1: low int32,
    y1: low int32)

proc catch(bounds: var NPolyBounds, point: NPolyFix) =
  bounds.x0 = min(bounds.x0, point.x)
  bounds.y0 = min(bounds.y0, point.y)
  bounds.x1 = max(bounds.x1, point.x)
  bounds.y1 = max(bounds.y1, point.y)

proc clip(bounds: var NPolyBounds, w, h: int32): bool =
  bounds.x0 = clamp(bounds.x0, 0, w shl 8)
  bounds.y0 = clamp(bounds.y0, 0, h shl 8)
  bounds.x1 = clamp(bounds.x1, 0, w shl 8)
  bounds.y1 = clamp(bounds.y1, 0, h shl 8)
  # Align Bounds to 32x32 Tiles
  bounds.x0 = bounds.x0 and not 0x1FFF
  bounds.y0 = bounds.y0 and not 0x1FFF
  bounds.x1 = (bounds.x1 + 0x1FFF) and not 0x1FFF
  bounds.y1 = (bounds.y1 + 0x1FFF) and not 0x1FFF
  # Check if There are Bounds
  bounds.x0 != bounds.x1 and
  bounds.y0 != bounds.y1

# ----------------------------
# Polygon Rasterizer Configure
# ----------------------------

proc configure*(rast: var NPolygon,
    pool: NThreadPool, buffer: NImageBuffer) =
  rast.pool = pool
  rast.buffer = buffer
  # Configure Pool Lanes
  let cores = pool.cores
  setLen(rast.lanes, cores)
  for i, lane in mpairs(rast.lanes):
    lane.rast = addr rast
    # Threading Offset
    lane.offset = int32(i)
    lane.skip = int32(cores)

proc clear*(rast: var NPolygon) =
  rast.bounds = newBounds()
  setLen(rast.points, 0)

proc push*(rast: var NPolygon, point: NPolyPoint) =
  var p: NPolyFix = (
    int32(point.x * 256.0 + 0.5) and not 0x7,
    int32(point.y * 256.0 + 0.5) and not 0x7)
  # Check Minimun Distance
  if len(rast.points) > 0:
    let peek = addr rast.points[^1]
    let dx: int64 = p.x - peek.x
    let dy: int64 = p.y - peek.y
    # Check Minimun Distance
    let dist = dx * dx + dy * dy
    if dist < 131072:
      return
  # Push Polygon Point
  rast.points.add(p)
  rast.bounds.catch(p)

# -------------------------------------
# Polygon Rasterizer Scanline: Segments
# -------------------------------------

proc fix(s: var NPolySegment, a, b: NPolyFix) =
  const mask: int32 = not 0xF
  s.a.x = a.x and mask
  s.a.y = a.y and mask
  s.b.x = b.x and mask
  s.b.y = b.y and mask

iterator segments(rast: var NPolygon): NPolySegment =
  var s {.noinit.}: NPolySegment
  let l = len(rast.points)
  # Collect Segments
  {.push checks: off.}
  var i = 0; while i < l:
    var i0 = i + 1
    if i0 >= l: i0 = 0
    s.fix(rast.points[i], rast.points[i0])
    yield s; inc(i)
  {.pop.}

# -----------------------------------
# Polygon Rasterizer Scanline: Bucket
# -----------------------------------

proc inside(s: NPolySegment, y0, y1: int32): bool =
  let check0 = uint32(s.a.y < y0) or uint32(s.a.y > y1) shl 1
  let check1 = uint32(s.b.y < y0) or uint32(s.b.y > y1) shl 1
  (check0 and check1) == 0

proc allocate(lane: ptr NPolyLane) =
  if lane.cap == 0:
    const bytes = 16384 * sizeof(NPolySegment)
    const bytesAux = 16384 * sizeof(NPolyFix)
    # Allocate Lane Buffers with Initial Capacity
    lane.bucket = cast[ptr NPolyGather](alloc bytes)
    lane.aux = cast[ptr NPolyHits](alloc bytesAux)
    lane.hits = cast[ptr NPolyHits](alloc bytesAux)
    lane.cap = 16384
    return
  dealloc(lane.aux)
  dealloc(lane.hits)
  # Expand Bucket Buffer with new Capacity
  let bytes = lane.cap * sizeof(NPolySegment) * 2
  let bytesAux = lane.cap * sizeof(NPolyFix) * 2
  let buffer = cast[ptr NPolyGather](alloc bytes)
  copyMem(buffer, lane.bucket, bytes shr 1)
  dealloc(lane.bucket)
  lane.bucket = buffer
  # Expand Auxiliars
  lane.aux = cast[ptr NPolyHits](alloc bytesAux)
  lane.hits = cast[ptr NPolyHits](alloc bytesAux)
  lane.cap *= 2

proc gather(lane: ptr NPolyLane, s: NPolySegment) =
  if lane.count >= lane.cap:
    lane.allocate()
  # Add Segment to Bucket
  lane.bucket[lane.count] = s
  inc(lane.count)

proc gather(lane: ptr NPolyLane, y0, y1: int32) =
  let rast = lane.rast
  lane.count = 0
  # Collect Segments Inside Range
  for s in rast[].segments():
    if s.inside(y0, y1):
      lane.gather(s)

# --------------------------------------
# Polygon Rasterizer Scanline: Collision
# --------------------------------------

proc merge(lane: ptr NPolyLane, i0, mid, i1: int) =
  let hits = lane.hits
  let aux = lane.aux
  # Calculate Slice Sizes
  let n0 = mid - i0 + 1
  let n1 = i1 - mid
  # Copy Data to Temporal Slices
  const size = NPolyFix.sizeof
  let s0 = cast[ptr NPolyHits](addr aux[0])
  let s1 = cast[ptr NPolyHits](addr aux[n0])
  copyMem(s0, addr hits[i0], n0 * size)
  copyMem(s1, addr hits[mid + 1], n1 * size)
  # Sort Slices and Merge to Original Array
  var i = 0; var j = 0; var k = i0
  while i < n0 and j < n1:
    if s0[i].x <= s1[j].x:
      hits[k] = s0[i]
      inc(i)
    else:
      hits[k] = s1[j]
      inc(j)
    inc(k)
  # Merge Remain Slices
  copyMem(addr hits[k], addr s0[i], (n0 - i) * size)
  copyMem(addr hits[k + n0 - i], addr s1[j], (n1 - j) * size)

proc sort(lane: ptr NPolyLane, i0, i1: int) =
  if i0 >= i1: return
  let mid = i0 + (i1 - i0) shr 1
  # Merge Sort Collisions
  sort(lane, i0, mid)
  sort(lane, mid + 1, i1)
  merge(lane, i0, mid, i1)

proc hit(s: NPolySegment, y: int32): NPolyFix =
  result = default(NPolyFix)
  # Check if Scanline in Range
  if s.a.y == s.b.y or
    (y < s.a.y or y > s.b.y) and
    (y < s.b.y or y > s.a.y):
      return result
  # Calculate Intersection and Winding Order
  let t = int64(y - s.a.y) shl 16 div (s.b.y - s.a.y)
  result.x = int32(s.a.x + t * (s.b.x - s.a.x) shr 16)
  result.y = int32(s.b.y < s.a.y) shl 1 - 1

# ----------------------------------
# Polygon Rasterizer Scanline: Lines
# ----------------------------------

proc collide(lane: ptr NPolyLane, y: int32): int =
  result = 0
  # Check Collision Hits
  let l = lane.count
  let bucket = lane.bucket
  let hits = lane.hits
  # Gather Collision Hits
  for i in 0 ..< l:
    var hit = bucket[i].hit(y)
    if hit.y == 0:
      continue
    # Add Collision Hit
    hits[result] = hit
    inc(result)
  # Sort Collision Hits
  if result < 2: return 0
  lane.sort(0, result - 1)

proc oddeven(lane: ptr NPolyLane, y: int32): int =
  let hits = lane.hits
  let count = lane.collide(y + 4)
  let bounds = addr lane.rast.bounds
  # Polygon Clamping
  let x0 = bounds.x0
  let x1 = bounds.x1
  # Check Pixel Lanes
  result = 0
  var idx = 0
  while idx < count - 1:
    let hit0 = hits[idx + 0]
    let hit1 = hits[idx + 1]
    # Odd-Even Winding Order
    if (idx and 1) == 0:
      let lane = addr hits[result]
      lane.x = clamp(hit0.x, x0, x1)
      lane.y = clamp(hit1.x, x0, x1)
      inc(result)
    inc(idx)

proc nonzero(lane: ptr NPolyLane, y: int32): int =
  let hits = lane.hits
  let count = lane.collide(y + 4)
  let bounds = addr lane.rast.bounds
  # Polygon Clamping
  let x0 = bounds.x0
  let x1 = bounds.x1
  # Check Pixel Lanes
  result = 0
  var idx, winding = 0
  while idx < count - 1:
    let hit0 = hits[idx + 0]
    let hit1 = hits[idx + 1]
    # Non-Zero Winding Order
    winding += hit0.y
    if winding != 0:
      let lane = addr hits[result]
      lane.x = clamp(hit0.x, x0, x1)
      lane.y = clamp(hit1.x, x0, x1)
      inc(result)
    inc(idx)

proc clear(lane: ptr NPolyLane) =
  if lane.cap > 0:
    dealloc(lane.bucket)
    dealloc(lane.aux)
    dealloc(lane.hits)
  # Remove Coverage Buffer
  if not isNil(lane.smooth):
    dealloc(lane.smooth)
    wasMoved(lane.smooth)
  # Remove Capacity
  wasMoved(lane.cap)
  wasMoved(lane.count)

# -----------------------------------
# Polygon Rasterizer Scanline: Render
# -----------------------------------

proc prepare(lane: ptr NPolyLane, smooth: bool): NPolyLine =
  let rast = lane.rast
  let bo = rast.bounds
  # Prepare Polygon Line
  result = NPolyLine(
    offset: bo.x0,
    stride: (bo.x1 - bo.x0) shr 8,
    buffer: rast.buffer.buffer)
  # Prepare Polygon Smooth
  if smooth:
    lane.smooth = alloc(result.stride * 2)
    result.smooth = lane.smooth

proc rasterizeSimple(lane: ptr NPolyLane) =
  let skip = lane.skip * 8192
  let offset = lane.offset * 8192
  var line = lane.prepare(smooth = false)
  polygon_line_skip(addr line, offset)
  # Rasterize by 32
  let rast = lane.rast
  var y0 = rast.bounds.y0 + offset
  let y2 = rast.bounds.y1
  while y0 < y2:
    let y1 = y0 + 8192
    lane.gather(y0, y1)
    # Rasterize Scanline
    var y = y0
    while y < y1:
      let count = case rast.rule
      of ruleNonZero: lane.nonzero(y)
      of ruleOddEven: lane.oddeven(y)
      polygon_line_clear(addr line)
      # Rasterize Lines
      let hits = lane.hits
      for i in 0 ..< count:
        let hit = hits[i]
        polygon_line_range(addr line, hit.x, hit.y)
        polygon_line_simple(addr line)
      # Next Scanline
      polygon_line_next(addr line); y += 256
    polygon_line_skip(addr line, skip); y0 += skip
  # Clear Temporals
  lane.clear()

proc rasterizeSmooth(lane: ptr NPolyLane) =
  let skip = lane.skip * 8192
  let offset = lane.offset * 8192
  var line = lane.prepare(smooth = true)
  polygon_line_skip(addr line, offset)
  # Rasterize by 32
  let rast = lane.rast
  var y0 = rast.bounds.y0 + offset
  let y2 = rast.bounds.y1
  while y0 < y2:
    let y1 = y0 + 8192
    lane.gather(y0, y1)
    # Rasterize Scanline
    var y = y0
    while y < y1:
      let y16 = y + 256
      polygon_line_clear(addr line)
      # Rasterize Coverage
      while y < y16:
        let count = case rast.rule
        of ruleNonZero: lane.nonzero(y)
        of ruleOddEven: lane.oddeven(y)
        # Rasterize Lines
        let hits = lane.hits
        for i in 0 ..< count:
          let hit = hits[i]
          polygon_line_range(addr line, hit.x, hit.y)
          polygon_line_coverage(addr line)
        y += 16
      # Next Scanline
      polygon_line_smooth(addr line)
      polygon_line_next(addr line)
    polygon_line_skip(addr line, skip)
    y0 += skip
  # Clear Temporals
  lane.clear()

# ---------------------------
# Polygon Rasterizer Scanline
# ---------------------------

proc rasterize*(rast: var NPolygon): NImageBuffer =
  result = rast.buffer
  let pool = rast.pool
  # Rasterizer Mode
  let fn =
    if rast.smooth:
      rasterizeSmooth
    else: rasterizeSimple
  # Dispatch Rasterizer
  let bo0 = rast.bounds
  if clip(rast.bounds, result.w, result.h):
    pool.start()
    for lane in rast.lanes:
      pool.spawn(fn, addr lane)
    # Adjust Buffer Dimensions
    let bo = addr rast.bounds
    result.x = bo.x0 shr 8
    result.y = bo.y0 shr 8
    result.w = (bo.x1 - bo.x0) shr 8
    result.h = (bo.y1 - bo.y0) shr 8
    result.stride = result.w
    # Wait Threading
    pool.sync()
    pool.stop()
  else: wasMoved(result)
  rast.bounds = bo0
