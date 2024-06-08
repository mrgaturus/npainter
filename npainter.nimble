# Package

version       = "0.1.0"
author        = "Cristian Camilo Ruiz"
description   = "fast and simple digital painting software"
license       = "GPL-3.0"
srcDir        = "src"
bin           = @["npainter"]

# Dependencies
requires "nim >= 2.0.0"
requires "nimPNG"
# nogui import
requires "https://github.com/mrgaturus/nogui#538f6ec"
