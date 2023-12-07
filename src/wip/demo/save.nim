import nimPNG
import tinyfiledialogs
# Import Canvas Proof
import ../canvas/context

# --------------------
# Canvas Saving to PNG
# --------------------

proc savePNG*(ctx: var NCanvasContext) =
  # Load File Location
  let loc0 = tinyfd_saveFileDialog("Save PNG", "~/", aFilterPatterns = "*.png")
  if isNil(loc0): return
  # Convert Buffer to Uint8 and Store
  let loc = $ loc0
  if loc.len > 0:
    let 
      l = ctx.w * ctx.h * 4
      buffer0 = cast[ptr UncheckedArray[uint16]](ctx.composed (0))
    var 
      buffer1 = newSeqUninitialized[uint8](l)
      i = 0
    while i < l:
      let
        r = cint buffer0[i + 0] shr 8
        g = cint buffer0[i + 1] shr 8
        b = cint buffer0[i + 2] shr 8
        a = cint buffer0[i + 3] shr 8
        a0 =  255 - a
        # Blending to White
        r1 = r + (255 * a0 + a0) shr 8
        g1 = g + (255 * a0 + a0) shr 8
        b1 = b + (255 * a0 + a0) shr 8
        a1 = a + (255 * a0 + a0) shr 8
      # Store Pixel Unpremultiplied
      buffer1[i + 0] = uint8(r1)
      buffer1[i + 1] = uint8(g1)
      buffer1[i + 2] = uint8(b1)
      buffer1[i + 3] = uint8(a1)
      # Next Pixel
      i += 4
    # Store PNG File
    discard savePNG32(loc, buffer1, ctx.w, ctx.h)
