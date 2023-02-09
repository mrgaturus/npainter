# TODO: Create Layer Block Allocator

type
  NLayerColor = ptr array[32768, cushort]
  NLayerMask = ptr array[8192, cushort]
  NLayerTile[T] = object
    x, y: cint
    uniform: bool
    buffer: T
  # Layer Content
  NLayerImage[T] = distinct 
    seq[NLayerTile[T]]
  NLayerList* = distinct 
    seq[NLayer]
  NLayerKind = enum
    lkColor, lkMask, lkFolder
  # Layer General
  NLayerFlag = enum
    lgVisible, lgClip, lgAlpha, lgLock
  NLayerBlend = enum
    laNormal, laMultiply
  NLayerFlags = set[NLayerFlag]
  NLayer* = ref object
    x, y: cint
    opacity: cushort
    # Layer Configuration
    flags: NLayerFlags
    blend: NLayerBlend
    # Layer Content
    case kind: NLayerKind
    of lkColor: color: NLayerImage[NLayerColor]
    of lkMask: mask: NLayerImage[NLayerMask]
    of lkFolder: folder: NLayerList
