# 🎨 NPainter
fast and simple digital painting software, work in progress

⚠️ **this project is not dead**, i'm rewriting the project to another language (not Rust...) but first i'm rewriting the gui tookit and making it ultimately better, powerful and easier than what is possible with Nim ⚠️

![Proof of Concept](https://raw.githubusercontent.com/mrgaturus/npainter/master/proof.png)

## 🛠️ Building
<details>
<summary>Building for Linux</summary>

- Requires GCC 10+ or Clang 10+
- Requires Additional Developing Packages on some distros:
  * Ubuntu/Debian: `libgdk-pixbuf2.0-dev libfreetype-dev libpng-dev libegl-dev libxcursor-dev libxi-dev libzstd-dev`
  * Fedora/RHEL: `gdk-pixbuf2-devel freetype-devel libpng-devel libglvnd-devel libXcursor-devel libXi-devel libzstd-devel`

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
  - [x] Anti-Aliased and Amazing Brush Engine *
  - [x] Anti-Aliased Bucket Fill + Gap Closing *
  - [x] GPU Accelerated Canvas
  - [x] Tiled Layering
    - [x] Raster Layers
    - [x] Mask/Stencil Layers
    - [x] Folder Layers
    - [x] 25 Blending Modes
    - [x] Clipping Group
    - [ ] Alpha Lock
  - [ ] Selection Tools
  - [ ] Transform Tool
    - [ ] Perspective
    - [ ] Mesh
    - [ ] Liquify
  - [ ] Fundamental Filters
  - [ ] Intuitive and Professional UI/UX
  - [x] Infinite Undo using Compressed Files
  - [x] Multi Platform Support
    - [x] Linux/X11
    - [x] Windows
    - [ ] macOS

### 🕙 Planned Features
  * Vector & Shape Layers
  * On-canvas Text Layers
  * Frame by Frame Animation
  * Android and iPad

### ❌ Not-Planned Features
  - Perfect Color Accuracy
  - Realistic Color Mixing
  - The Fastest Painting Software Ever
  - 1:1 Features with Similar Software
  - AI, Machine Learning and NFT
