# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
import canvas/[context, layer]

type
  NCanvas* = object
    ctx*: NCanvasContext
    layers*: NLayerList

# ---------------
# Canvas Creation
# ---------------

proc createCanvas*(w, h: cint): NCanvas =
  result.ctx = createCanvasContext(w, h)
