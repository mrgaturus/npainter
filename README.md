# 🎨 NPainter
fast and simple digital painting software, work in progress

![Proof of Concept](https://raw.githubusercontent.com/mrgaturus/npainter/master/proof.png)

## 🛠️ Building
<details>
<summary>Building for Linux</summary>

- Requires GCC 10+ or Clang 10+
- Requires Additional Developing Packages on some distros:
  * Ubuntu/Debian: `libfreetype-dev libegl-dev libgdk-pixbuf-2.0-dev`
  * Fedora/RHEL: `freetype-devel libglvnd-devel gdk-pixbuf2-devel`

### Building Release Build
```sh
# Install Latest Stable Nim
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
# Build Program
./build_linux.sh

# Running Program
./npainter
```

### Developing Project
```sh
# Compile Program
nimble build
# Pack Data when needed
nopack

# Debug Program
./npainter
```

</details>

<details>
<summary>Building for Windows</summary>

- Requires MSYS2 Environment
  * Download: https://www.msys2.org/
  * Only works on MINGW64 Environment
- Requires Nim Programming Language
  * Download: https://nim-lang.org/
  * Must be configured on PATH

### Building Release Build
```sh
# Build Program
./build_win32.sh
# Executing Program
./release/npainter.exe
```

### Developing Project
```sh
# Prepare Building
./build_win32.sh

# Compile Program
nimble build
# Pack Data when needed
nopack

# Debug Program
./npainter
```

</details>

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
  - [ ] Transform Tool
    - [ ] Perspective
    - [ ] Mesh
    - [ ] Liquify
  - [ ] Selection Tools
  - [ ] Infinite Undo using Compressed Files
  - [ ] Fundamental Filters
  - [ ] Intuitive and Professional UI/UX
  - [x] Multi Platform Support
    - [x] Linux/X11
    - [x] Windows
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
