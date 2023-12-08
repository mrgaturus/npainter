# Import Canvas Proof
import ../canvas/context
import nogui/values

# Canvas Eyedropper
proc lookupColor*(ctx: var NCanvasContext, x, y: cint): RGBColor =
  if x < 0 or y < 0 or x >= ctx.w or y >= ctx.h: return
  # Lookup Color
  let
    idx = (ctx.w * y + x) shl 2
    buffer0 = cast[ptr UncheckedArray[uint16]](ctx.composed (0))
    r = cint buffer0[idx + 0] shr 8
    g = cint buffer0[idx + 1] shr 8
    b = cint buffer0[idx + 2] shr 8
    a = cint buffer0[idx + 3] shr 8
    a0 = 255 - a
    # Blending to White
    r1 = r + (255 * a0 + a0) shr 8
    g1 = g + (255 * a0 + a0) shr 8
    b1 = b + (255 * a0 + a0) shr 8
  # Convert to RGB Color
  result.r = r1 / 255
  result.g = g1 / 255
  result.b = b1 / 255
