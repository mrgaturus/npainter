# Package

version       = "0.0.2"
author        = "Cristian Camilo Ruiz"
description   = "fast and simple digital painting software"
license       = "GPL-3.0"
srcDir        = "src"
bin           = @["npainter"]

# Dependencies
requires "nim >= 2.2.0"
requires "https://github.com/mrgaturus/nogui#d6e86ce"
requires "tinyfiledialogs"
