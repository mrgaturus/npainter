# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2023 Cristian Camilo Ruiz <mrgaturus>

type
  NLayerColor = ptr array[32768, cushort]
  NLayerMask = ptr array[8192, cushort]
  NLayerTile[T] = object
    x, y: cint
    uniform: bool
    buffer: T

type
  NLayerTiles[T] = distinct seq[NLayerTile[T]]
  NLayerList* = distinct seq[NLayer]
  # Layer Kind
  NLayerKind = enum
    lkColor, lkMask, lkFolder
  NLayerBlend = enum
    laNormal, laMultiply
  # Layer Flags
  NLayerFlag = enum
    lgVisible, lgClip, lgAlpha, lgLock
  NLayerFlags = set[NLayerFlag]
  # Layer General
  NLayerObject = object
    x, y: cint
    opacity: cushort
    # Layer Configuration
    flags: NLayerFlags
    blend: NLayerBlend
    # Layer Content
    case kind: NLayerKind
    of lkColor: color: NLayerTiles[NLayerColor]
    of lkMask: mask: NLayerTiles[NLayerMask]
    of lkFolder: folder: NLayerList
  NLayer* = ref NLayerObject
