# Global Values for GUI Creation

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
  CFGMetrics* = object
    # -- Window Dimensions --
    width*, height*: int32
    # -- Font and Glyph Metrics --
    ascender*, descender*, baseline*: int16
    fontSize*, iconSize*: int32
    # -- Font Hidden Metrics --
    opaque*: pointer

var # Global State
  colors*: CFGColors
  metrics*: CFGMetrics
  # -- Custom Flags --
  cflags*: uint