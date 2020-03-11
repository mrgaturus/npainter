# Minimal FT2 Wrappers for basic font rendering
# Freetype 2.10.1

type # Trimmed Types for basic usage
  FT2Pos = clong
  FT2Fixed = clong
  FT2Int = cint
  FT2UInt = cuint
  FT2Long = clong
  FT2Short = cshort
  FT2UShort = cushort
  # Generic Unused, only for padding
  FT2Generic {.bycopy.} = object
    use, less: pointer
  # Vector for Advance and Kerning
  FT2Vector* {.bycopy.} = object
    x*, y*: FT2Pos
  # FT2 Glyph Rendered Bitmap
  FT2Bitmap* {.bycopy.} = object
    rows*: cuint
    width*: cuint
    pitch*: cint
    buffer*: cstring
    num_grays*: cushort
    pixel_mode*: cuchar
    palette_mode*: cuchar
    palette*: pointer
  # FT2 Bounding Box
  FT2BBox* {.bycopy.} = object
    xMin*, yMin*: FT2Pos
    xMax*, yMax*: FT2Pos
  # Glyph Metrics in original measures
  FT2Glyph_Metrics* {.bycopy.} = object
    width*: FT2Pos
    height*: FT2Pos
    horiBearingX*: FT2Pos
    horiBearingY*: FT2Pos
    horiAdvance*: FT2Pos
    vertBearingX*: FT2Pos
    vertBearingY*: FT2Pos
    vertAdvance*: FT2Pos
  # FT2 Important Objects -Trimmed-
  FT2Library* = pointer
  FT2Glyph* {.bycopy.} = ptr object
    library*: FT2Library
    face*: FT2Face
    next*: FT2Glyph
    glyph_index*: FT2UInt
    generic*: FT2Generic
    metrics*: FT2Glyph_Metrics
    linearHoriAdvance*: FT2Fixed
    linearVertAdvance*: FT2Fixed
    advance*: FT2Vector
    format*: culong
    bitmap*: FT2Bitmap
    bitmap_left*: FT2Int
    bitmap_top*: FT2Int
  FT2Face* {.bycopy.} = ptr object
    num_faces*: FT2Long
    face_index*: FT2Long
    face_flags*: FT2Long
    style_flags*: FT2Long
    num_glyphs*: FT2Long
    family_name*: cstring
    style_name*: cstring
    num_fixed_sizes*: FT2Int
    available_sizes: pointer
    num_charmaps*: FT2Int
    charmaps: pointer
    generic: FT2Generic
    bbox*: FT2BBox
    units_per_EM*: FT2UShort
    ascender*: FT2Short
    descender*: FT2Short
    height*: FT2Short
    max_advance_width*: FT2Short
    max_advance_height*: FT2Short
    underline_position*: FT2Short
    underline_thickness*: FT2Short
    glyph*: FT2Glyph

const # FT2 CONSTANTS
  FT_LOAD_RENDER* = 1 shl 2
  FT_KERNING_DEFAULT* = 0'i32

{.passL: "-lfreetype".} # FT2 PROCS
proc ft2_init*(lib: ptr FT2Library): int32 {.importc: "FT_Init_FreeType", cdecl.}
proc ft2_newFace*(lib: FT2Library, file: cstring, faceIndex: int32, face: ptr FT2Face): int32 {.importc: "FT_New_Face", cdecl.}
proc ft2_setCharSize*(face: FT2Face, cWidth, cHeight: int32, width, height: uint32): int32 {.importc: "FT_Set_Char_Size", cdecl.}
proc ft2_getCharIndex*(face: FT2Face, charcode: culong): uint32 {.importc: "FT_Get_Char_Index", cdecl.}
proc ft2_loadGlyph*(face: FT2Face, glyphIndex: uint32, loadFlags: int32): int32 {.importc: "FT_Load_Glyph", cdecl.}
proc ft2_getKerning*(face: FT2Face, left, right, mode: uint32, kvec: ptr FT2Vector): int32 {.importc: "FT_Get_Kerning", cdecl.}
proc ft2_done*(lib: FT2Library): int32 {.importc: "FT_Done_FreeType", cdecl.}