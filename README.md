# NPainter
fast and simple digital painting software (work in progress, still planning)

![Proof of Concept](https://raw.githubusercontent.com/mrgaturus/npainter/master/proof.png)

## Building
- For now, Only works on Linux/X11/XWayland.
- Arch Linux or Manjaro is Recommended.
- Requires [Nim Programming Language](https://nim-lang.org/) for Compiling.
```sh
# Building Debug Binary
$ nimble build
# Building Fast Binary
$ nimble build -d:danger

# Running Program
$ ./npainter
```

## Current Features
  - Graphics Tablet Pressure using XInput2
  - Fast Enough Rendering using SSE4.1
  - Anti-Aliased and Amazing Brush Engine
  - Anti-Aliased Bucket Fill + Gap Closing
  - OpenGL 3.3 Accelerated Canvas

## Work in Progress Features
  * Tiled Layering
    - Raster Layers
    - Mask/Stencil Layers
    - Folder Layers
    - Fundamental Blending Modes
    - Clipping Group & Alpha Lock
  - Intuitive and Similar UI/UX
  - Transform Tool (Standard, Mesh, Liquify)
  - Infinite Undo using Compressed Files
  - Basic and Useful Filters
  - Windows and Mac Versions

## Very Future Features
  * Semi-Vector Layer
    - Catmull
    - Bezier
  - Frame by Frame Animation

## Avoided Features
  - Maximum Color Accuracy
  - Very Realistic Brushes
  - 1:1 Features with Similar Software
  - AI Filters and Cryptocurrency
  - Animated GUI
