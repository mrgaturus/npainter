# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
import nogui/ux/values/linear
import nogui/ux/prelude
import nogui/builder
# Import Engine State
import ../../wip/canvas/matrix
import engine, color

# -----------------------
# Bucket Tool: Controller
# -----------------------

type
  CKBucketMode* = enum
    bcmAlphaMin
    bcmAlphaDiff
    bcmColorDiff
    bcmColorSimilar
  CKBucketTarget* = enum
    bctCanvas
    bctLayer
    bctWandTarget

controller CXBucket:
  attributes:
    {.cursor.}:
      engine: NPainterEngine
      color: CXColor
    # Bucket Properties
    {.public.}:
      mode: @ int32
      target: @ int32
      # Bucket Fill Parameters
      threshold: @ Linear
      gap: @ Linear
      antialiasing: @ bool

  proc modecheck: NBucketCheck =
    case CKBucketMode self.mode.peek[]
    of bcmAlphaMin: bkMinimun
    of bcmAlphaDiff: bkAlpha
    of bcmColorDiff: bkColor
    of bcmColorSimilar: bkSimilar

  new cxbucket(engine: NPainterEngine, color: CXColor):
    result.engine = engine
    result.color = color
    # Configure Bucket Values
    let liBasic = linear(0, 100)
    result.threshold = liBasic
    result.gap = liBasic

# -------------------
# Bucket Tool: Widget
# -------------------

widget UXBucketDispatch:
  attributes: {.cursor.}:
    bucket: CXBucket

  new uxbucketdispatch(bucket: CXBucket):
    result.bucket = bucket

  # -- Bucket Dispatcher --
  method event(state: ptr GUIState) =
    let
      bucket {.cursor.} = self.bucket
      engine {.cursor.} = bucket.engine
    if state.kind != evCursorClick:
      return
    let
      fill = addr engine.bucket
      canvas = addr engine.canvas
      # Map Current Position
      affine = canvas[].affine
      p = affine[].forward(state.px, state.py)
      # Integer Position
      x = int32 p.x
      y = int32 p.y
    # Configure Bucket - proof of concept
    discard engine.proxyBucket0proof()
    fill.tolerance = cint(bucket.threshold.peek[].toRaw * 255)
    fill.gap = cint(bucket.gap.peek[].toRaw * 255)
    fill.check = bucket.modecheck
    fill.antialiasing = bucket.antialiasing.peek[]
    fill.rgba = bucket.color.color32()
    # Dispatch Position
    if fill.check != bkSimilar:
      fill[].flood(x, y)
    else: fill[].similar(x, y)
    fill[].blend()
    # Update Render Region
    engine.commit0proof()

  method handle(reason: GUIHandle) =
    echo "bucket reason: ", reason
    let win = getWindow()
    if reason == inHover:
      win.cursor(cursorBasic)
    elif reason == outHover:
      win.cursorReset()
