# NPainter
fast and simple digital painting software (Work in Progress)

![Proof of Concept](https://raw.githubusercontent.com/mrgaturus/npainter/master/proof.png)

## Building
For now, only works on Linux/X11/XWayland. Arch/Manjaro is Recommended
```sh
# Building Fast Binary
$ nimble build -d:danger
# Building Debug Binary
$ nimble build

# Running Program
$ ./npainter
```

## Current Features
  - Graphics Tablet Pressure via XInput2
  - Antialiased and Almost Consistent Brushes
  - Fast Enough Rendering using SSE4.1

## Future Features
  * Tiled Layering
    - Raster Layers
    - Mask/Stencil Layers
    - Folder Layers
    - Fundamental Blending Modes
    - Clipping Group & Alpha Lock
  - Transform Tool (Standard, Mesh, Liquify)
  - Antialiased Fill With Closing Gap
  - OpenGL 3.3 Acceletared Canvas View
  - Basic but very Useful Filters
  - Infinite Undo using Compressed Files with zstd
  - Intuitive and Very Simple GUI

## Very Future Features
  * Semi-Vector Layer
    - Catmull
    - Bezier
  - Frame by Frame Animation

## Out of Scope Features
  - Maximun Pixel Precision
  - Very Realistic Brushes
  - 1:1 Features with Similar Software
  - Machine Learning Filters
  - Animated GUI
