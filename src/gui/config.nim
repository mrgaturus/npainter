# Global Values for GUI Creation

type
  # Theme Color Scheme
  CFGColors* = object
    # -- Core Widget Colors --
    text*, disabledText*: uint32 # Icons Included
    bgWidget*, hoverWidget*, grabWidget*: uint32
    # -- Other Widget Colors --
    bgButton*, hoverButton*, grabButton*: uint32
    bgScroll*, barScroll*, hoverScroll*, grabScroll*: uint32
    bgTab*, activeTab, hoverTab*: uint32
    mark*: uint32 # Checkbox/Radio
    # -- Container/Frame Colors --
    bgContainer*, bgFrame*: uint32
    bgHeader*, bgHeaderFocus*: uint32
  # Font Metrics
  CFGMetrics* = object
    # -- Window Dimensions --
    width*, height*: int32
    # -- Font and Glyph Metrics --
    ascender*, descender*, baseline*: int16
    fontSize*, iconSize*: int32
  # Runtime Globals
  CFGOpaque* = object
    queue*, atlas*: pointer
    # User Data Pointer
    user*: pointer

var # Global State
  theme*: CFGColors
  metrics*: CFGMetrics
  opaque*: CFGOpaque
  # -- Custom Flags --
  cflags*: uint

# -------------------
# DEFAULT COLOR THEME
# -------------------

# Text Colors
theme.text = 0xFFE6E6E6'u32
theme.disabledText = 0xFF808080'u32
# General Widget Colors
theme.bgWidget = 0xFF1E1E1E'u32
theme.hoverWidget = 0x66666666'u32
theme.grabWidget = 0xAB777777'u32
# Button Widget Colors
theme.bgButton = 0xFF4B4B4B'u32
theme.hoverButton = 0xFF5F5F5F'u32
theme.grabButton = 0xFF737373'u32
# Scroll Widget Colors
theme.bgScroll = 0x87090909'u32
theme.barScroll = 0xFF4F4F4F'u32
theme.hoverScroll = 0xFF696969'u32
theme.grabScroll = 0xFF828282'u32
# Tab Widget Colors
theme.bgTab = 0xFF2D2D2D'u32
theme.activeTab = 0xFF21201D'u32
theme.hoverTab = 0xFF333333'u32
# Checkbox/Radio Mark
theme.mark = 0xFFF0F0F0'u32
# Container/Frame Colors
theme.bgContainer = 0xFE323232'u32
theme.bgFrame = 0xFB323232'u32
theme.bgHeader = 0xFC191919'u32
theme.bgHeaderFocus = 0xFF191919'u32
