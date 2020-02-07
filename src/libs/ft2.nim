# Minimal FT2 Wrappers for basic font rendering
# Freetype 2.10.1

type # FT2 TYPES
  FT2Library* = ptr object
  FT2GlyphMetrics = object
    width*, height*: int32
    hBearingX*, hBearingY*: int32
    hAdvance*: int32
    # VERTICAL IS UNUSED
    vertical: array[3, int32]
  FT2Bitmap = object
    rows*, width*: uint32
    pitch*: int32
    buffer*: ptr UncheckedArray[byte]
    # PALETTE IS UNUSED
    unused: array[12, byte]
  FT2Glyph = ptr object
    header: array[24, byte]
    index*: uint32 # GLYPH INDEX
    generic: array[16, byte]
    metrics*: FT2GlyphMetrics
    format: byte # BITMAP ALWAYS
    bitmap*: FT2Bitmap
  FT2Face* = ptr object
    unused: array[108, byte]
    glyph*: FT2Glyph
  # Kerning Vector
  FT2Vector* = object
    x*, y*: int32

const # FT2 CONSTANTS
  FT_LOAD_RENDER* = 4'i32
  FT_KERNING_DEFAULT* = 0'i32

{.passL: "-lfreetype".} # FT2 PROCS
proc ft2_init*(lib: ptr FT2Library): int32 {.importc: "FT_Init_FreeType", cdecl.}
proc ft2_done*(lib: FT2Library): int32 {.importc: "FT_Done_FreeType", cdecl.}
proc ft2_newFace*(lib: FT2Library, file: cstring, faceIndex: int32, face: ptr FT2Face): int32 {.importc: "FT_New_Face", cdecl.}
proc ft2_setCharSize*(face: FT2Face, cWidth, cHeight: int32, width, height: uint32): int32 {.importc: "FT_Set_Char_Size", cdecl.}
proc ft2_loadChar*(face: FT2Face, charcode: uint32, loadFlags: int32): int32 {.importc: "FT_Load_Char", cdecl.}
proc ft2_getKerning*(face: FT2Face, left, right, mode: uint32, kvec: ptr FT2Vector): int32 {.importc: "FT_Get_Kerning", cdecl.}