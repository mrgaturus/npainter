# Package

version       = "0.2.0"
author        = "Cristian Camilo Ruiz"
description   = "fast and simple digital painting software"
license       = "GPL-3.0"
srcDir        = "src"
bin           = @["npainter"]

# Dependencies
requires "nim >= 2.0.0"
requires "https://github.com/mrgaturus/nogui#head"
requires "tinyfiledialogs"
