# Pedro Felzenszwalb's SDF Generator
from math import sqrt

type
  SDFGenerator = object
    w, h: int
    # SDF Buffers
    v: seq[int]
    f, d, z: seq[float]
    # Raw SDF Output
    output*: seq[float]
# Nim's Inf leads formula to 0
const Infinite = float(1e20)

proc newSDFGenerator*(w, h: int): SDFGenerator =
  # Set Dimensions
  result.w = w
  result.h = h
  # Calculate Max Dimension
  let dim = max(w, h)
  # Alloc SDF Buffer
  result.v.setLen(dim)
  result.f.setLen(dim)
  result.d.setLen(dim)
  result.z.setLen(dim + 1)
  # Output Formatted as float
  result.output.setLen(w * h)

# -- SDF from a RGBA8888 Image
proc edt_1D(sdf: var SDFGenerator, stride: int) =
  var
    q, k, vk = 0
    s, vc, qc: float
  sdf.v[0] = 0
  sdf.z[0] = -Infinite
  sdf.z[1] = +Infinite
  # -----------
  q = 1; while q < stride:
    while true:
      vk = sdf.v[k]
      vc = vk.float
      qc = q.float
      s = ( (sdf.f[q] + (qc*qc)) - (sdf.f[vk] + (vc*vc)) ) / (qc - vc) / 2
      if not (s <= sdf.z[k] and (dec(k); k) >= 0): break
    inc(k); sdf.v[k] = q; sdf.z[k] = s; sdf.z[k+1] = +Infinite
    # Next Q
    inc(q)
  # -----------
  k = 0; q = 0
  while q < stride:
    qc = q.float
    while sdf.z[k+1] < qc: inc(k)
    vk = sdf.v[k]; vc = vk.float 
    sdf.d[q] = (qc - vc) * (qc - vc) + sdf.f[vk]
    # Next Q
    inc(q)

proc edt(sdf: var SDFGenerator) =
  let 
    w = sdf.w
    h = sdf.h
  # Transform Columns
  for x in 0..<w:
    for y in 0..<h: # Load Column
      sdf.f[y] = sdf.output[y * h + x]
    # Perform 1D EDT
    sdf.edt_1D(h)
    for y in 0..<h: # Save Column
      sdf.output[y * h + x] = sdf.d[y]
  # Transform Rows
  for y in 0..<h:
    for x in 0..<w: # Load Row
      sdf.f[x] = sdf.output[y * h + x]
    # Perform 1D EDT
    sdf.edt_1D(w)
    for x in 0..<w: # Save Column
      sdf.output[y * h + x] = sdf.d[x]

proc image*(sdf: var SDFGenerator, buf: cstring) =
  # Prepare EDT Buffer
  for i, pixel in mpairs(sdf.output):
    # Get Alpha Channel
    let a = buf[i shl 2 + 3].byte
    pixel = # Prepare Mask
      if a == 255: 0.0
      else: Infinite
  # Perform EDT
  sdf.edt()
  # Perform Square Root
  for pixel in mitems(sdf.output):
    pixel = sqrt(pixel)

# -- SDF with simple circle distance
proc circle*(sdf: var SDFGenerator) =
  discard