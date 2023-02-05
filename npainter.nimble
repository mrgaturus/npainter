# Package

version       = "0.1.0"
author        = "Cristian Camilo Ruiz"
description   = "A simple gpu-accelerated painter"
license       = "GPL-3.0"
srcDir        = "src"
bin           = @["npainter"]

# Dependencies
requires "nim >= 1.6.10"
requires "x11"
requires "nimPNG"