import layer

type
  NCanvasBlock = ref UncheckedArray[byte]
  NCanvasMap = ptr UncheckedArray[byte]
  NCanvas* = object
    w*, w64*, rw64*: cint 
    h*, h64*, rh64*: cint
    # Memory Block
    memory: NCanvasBlock
    layers*: NLayerList
    # Memory Block Sections
    buffer0*, buffer1*: NCanvasMap
    grayscale*, composite*: NCanvasMap