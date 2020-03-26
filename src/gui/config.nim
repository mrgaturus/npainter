# Import Freetype2
import ../assets
import ../libs/ft2

type
  CFGColors* = object
    # -- Core Widget Colors --
    text*, disabledText*: uint32 # Icons Included
    bgWidget*, disabledWidget*: uint32
    hoverWidget*, focusWidget*, grabWidget*: uint32
    # -- Other Widget Colors --
    bgScroll*, barScroll, hoverScroll*, grabScroll*: uint32
    bgTab*, hoverTab*, grabTab*: uint32
    markSelector*: uint32 # Radio and Checkbox
    # -- Container/Frame Colors --
    bgContainer*, bgFrame*, edgeFrame*: uint32
    bgHeader*, bgHeaderFocus*: uint32
  INFOMetrics* = object
    # -- Window Dimensions --
    width*, height*: int32
    # -- Font and Glyph Metrics --
    ascender*, descender*, baseline*: int16
    fontSize*, iconSize*: int32

var # Global State
  font*: FT2Face
  icons*: BUFIcons
  colors*: CFGColors
  metrics*: INFOMetrics
  # -- Custom Flags --
  cflags*: uint

proc initialized*(): bool =
  # Check if there is a GUIWindow 
  not isNil(font) and not isNil(icons)

proc loadResources*() =
  font = newFont(10)
  icons = newIcons()
  # Compute Font Metrics
  metrics.fontSize = # Max Height
    cast[int16](font.height shr 6)
  metrics.ascender = # Over Origin
    cast[int16](font.ascender shr 6)
  metrics.descender = # Under Origin
    cast[int16](font.descender shr 6)
  metrics.baseline = # Average Height
    metrics.ascender + metrics.descender
  # Set Icon Size*Size Metric
  metrics.iconSize = icons.size
