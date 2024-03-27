# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
import canvas/[matrix, render, copy]
import image

type
  NCanvasManager* = ref object
    render: NCanvasRenderer
    actives: seq[NCanvasImage]
  # -- Canvas Image --
  NCanvasInfo = object
    stamp*: uint64
    w*, h*, bpp*: cint
    # Background Colors
    r0*, b0*, g0*, a0: uint8
    r1*, b1*, g1*, a1: uint8
    # Background Pattern Size
    checker*: cint
  NCanvasImage* = ref object
    image*: NImage
    # Canvas Viewport
    view: NCanvasViewport
    affine*: ptr NCanvasAffine
    data: NCanvasData
    # Canvas Info
    path*: string
    info*: NCanvasInfo
    # Associated Canvas Manager
    man {.cursor.}: NCanvasManager

# ---------------------
# Canvas Image Creation
# ---------------------

proc createCanvasManager*(): NCanvasManager =
  new result
  # Initialize Canvas Renderer
  result.render = createCanvasRenderer()

proc createCanvas*(man: NCanvasManager, w, h: cint): NCanvasImage =
  new result
  # Initialize Canvas Image
  result.image = createImage(w, h)
  # Initialize Canvas View
  result.view = createCanvasViewport(man.render, w, h)
  result.view.data = addr result.data
  result.affine = addr result.view.affine
  # Register to Canvas Manager
  man.actives.add(result)
  result.man = man

# -----------------------
# Canvas Image Destructor
# -----------------------

proc destroy*(canvas: NCanvasImage) =
  destroy(canvas.image)
  destroy(canvas.data.bg)

proc destroy*(man: NCanvasManager) =
  # Destroy Actives
  for canvas in man.actives:
    canvas.destroy()

# -------------------
# Canvas Image Update
# -------------------

proc background*(canvas: NCanvasImage) =
  let
    info = addr canvas.info
    bg = addr canvas.data.bg
  # Set Background Colors
  bg[].color0(info.r0, info.g0, info.b0)
  bg[].color1(info.r1, info.g1, info.b1)
  # Set Background Pattern
  bg[].pattern(info.checker)

proc stream*(canvas: NCanvasImage) =
  discard
