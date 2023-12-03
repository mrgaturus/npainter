# 🎨 NPainter
fast and simple digital painting software, work in progress

![Proof of Concept](https://raw.githubusercontent.com/mrgaturus/npainter/master/proof.png)

## Building
- Only works on Linux X11/XWayland. Other Platforms are Work in Progress
- Requires [Nim Programming Language](https://nim-lang.org/) for Compiling.
- Requires Addtional Developing Packages
  - Ubuntu, Debian: `libfreetype-dev, libegl-dev`
  - Fedora: `freetype-devel, libglvnd-devel`:
- Requires GCC 10+:
  - Clang can be used appending `--cc:clang` to nimble command
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
  - Intuitive and Professional UI/UX
  * Tiled Layering
    - Raster Layers
    - Mask/Stencil Layers
    - Folder Layers
    - Fundamental Blending Modes
    - Clipping Group & Alpha Lock
  - Selection Tools
  - Transform Tool 
    - Perspective
    - Mesh
    - Liquify
  - Infinite Undo using Compressed Files
  - Fundamental Filters
  - Windows and Mac Support

## Very Future Features
  * Lineart Vector Layer
    - Catmull
    - Bezier
  * Frame by Frame Animation
  * On-canvas Text Tool
  * Android Support

## Avoided Features
  - Maximum Color Accuracy
  - Maximum Optimization possible
  - Very Realistic Brushes
  - 1:1 Features with Similar Software
  - AI Filters and Cryptocurrency
