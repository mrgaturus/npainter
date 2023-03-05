# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>
import canvas/[context, layer]

type
  NCanvas* = object
    context*: NCanvasContext
    layers*: NLayerList

# ---------------
# Canvas Creation
# ---------------

proc createCanvas*(w, h: cint): NCanvas =
  result.context = createCanvasContext(w, h)
