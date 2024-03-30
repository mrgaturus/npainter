# 🎨 NPainter
fast and simple digital painting software, work in progress

![Proof of Concept](https://raw.githubusercontent.com/mrgaturus/npainter/master/proof.png)

## 🛠️ Building
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
# Generate Assets (using GUI tool)
$ ~/.nimble/bin/nopack

# Running Program
$ ./npainter
```

## ⚙️ Roadmap Features
  - [x] Pen Pressure Support
  - [x] Multithreading and SIMD Optimization
  - [x] Anti-Aliased and Amazing Brush Engine
  - [x] Anti-Aliased Bucket Fill + Gap Closing
  - [x] GPU Accelerated Canvas
  - [x] Tiled Layering
    - [x] Raster Layers
    - [ ] Mask/Stencil Layers
    - [x] Folder Layers
    - [x] Fundamental Blending Modes
    - [x] Clipping Group & Alpha Lock
  - [ ] Intuitive and Professional UI/UX
  - [ ] Transform Tool
    - [ ] Perspective
    - [ ] Mesh
    - [ ] Liquify
  - [ ] Selection Tools
  - [ ] Infinite Undo using Compressed Files
  - [ ] Fundamental Filters
  - [ ] Multi Platform Support
    - [x] Linux/X11
    - [ ] Windows
    - [ ] macOS

### 🕙 Planned Features
  * Vector Layer
    - Catmull
    - Bezier
  * Frame by Frame Animation
  * On-canvas Text Tool
  * Android and iPad

### ❌ Not-Planned Features
  - Maximum Color Accuracy
  - The Fastest Painting Software ever
  - Very Realistic Brushes
  - 1:1 Features with Similar Software
  - AI, Machine Learning and Cryptocurrency
