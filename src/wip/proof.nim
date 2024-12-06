import tinyfiledialogs
import nogui/bst
import nogui/async/core
import nogui/libs/png
import undo/[swap, stream]
import image/[context, composite]
import image, undo

proc loadFile*(image: NImage, undo0: NImageUndo): set[NUndoEffect] =
  let pattern = cstring("*.npdemo")
  let name = tinyfd_openFileDialog(
    "Load NPainter File", "",
    aNumOfFilterPatterns = 1,
    aFilterPattern =
      cast[cstring](addr pattern))
  result = {}
  # Create Write File
  var file {.noinit.}: File
  if not open(file, $name, fmReadWriteExisting):
    echo "[ERROR]: failed loading save file"
    return result
  # Remove Undo
  hang(undo0)
  flush(undo0)
  # Store Current ID Tickets
  let undo = createImageUndo(image, file)
  let stream = addr undo.stream
  image.owner.ticket = readNumber[uint32](stream)
  image.t0 = readNumber[cint](stream)
  image.t1 = readNumber[cint](stream)
  let skip = stream.swap[].readSkip()
  # Restore Root Layer
  undo.seed(skip)
  result = undo.redo()
  undo.hang()
  undo.flush()

proc saveFile*(image: NImage) =
  let pattern = cstring("*.npdemo")
  let name = tinyfd_saveFileDialog(
    "Save NPainter File", "file.npdemo",
    aNumOfFilterPatterns = 1,
    aFilterPatterns =
      cast[cstring](addr pattern))
  # Create Write File
  var file {.noinit.}: File
  if not open(file, $name, fmReadWrite):
    echo "[ERROR]: failed creating save file"
    return
  # Store Current ID Tickets
  let undo = createImageUndo(image, file)
  let stream = addr undo.stream
  stream.writeNumber(image.owner.ticket)
  stream.writeNumber(image.t0)
  stream.writeNumber(image.t1)
  # Capture Image Root
  let data = undo.push(ucLayerCreate)
  data.capture(image.root)
  undo.flush()
  undo.hang()

# ---------------
# Export PNG File
# ---------------

proc copyBuffer(png: PNGnimWrite, buffer: NImageMap) =
  let w = buffer.w
  let rows = buffer.h
  let stride = buffer.stride
  let src = cast[ptr UncheckedArray[PNGbyte]](buffer.buffer)
  let dst = cast[ptr UncheckedArray[PNGbyte]](png.buffer)
  # Transfer Bytes to Buffer
  var idx0, idx1 = 0
  for _ in 0 ..< rows:
    var idx00 = idx0
    for _ in 0 ..< w:
      let
        r = uint32(src[idx00 + 0])
        g = uint32(src[idx00 + 1])
        b = uint32(src[idx00 + 2])
        a = uint32(src[idx00 + 3])
      # Store Pixel
      dst[idx1 + 0] = cast[uint8](r + 255 - a)
      dst[idx1 + 1] = cast[uint8](g + 255 - a)
      dst[idx1 + 2] = cast[uint8](b + 255 - a)
      dst[idx1 + 3] = cast[uint8](a + 255 - a)
      # Next Pixel
      idx00 += 4
      idx1 += 4
    idx0 += stride

proc saveFilePNG*(image: NImage) =
  let pattern = cstring("*.png")
  let name = tinyfd_saveFileDialog(
    "Save NPainter File", "image.png",
    aNumOfFilterPatterns = 1,
    aFilterPatterns =
      cast[cstring](addr pattern))
  # Create PNG File
  let ctx = addr image.ctx
  let png = createWritePNG($name, ctx.w, ctx.h)
  # Redraw Whole Canvas
  let status = addr image.status
  complete(status.clip)
  status[].mark(status.clip)
  let com = addr image.com
  let mip = com.mipmap
  image.com.mipmap = 0

  for c in status[].checkFlat(0):
    let
      tx = c.tx
      ty = c.ty
    # Mark Compositor and Tile
    com[].mark(tx, ty)
    c.check[] = c.check[] or 1

  let pool = getPool()
  pool.start()
  image.com.dispatch(pool)
  pool.stop()
  image.com.mipmap = mip
  # Close PNG File
  png.copyBuffer(ctx[].mapFlat(0))
  discard png.writeRGB()
  png.close()

