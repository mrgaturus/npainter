import nogui/builder
import nogui/gui/value
import nogui/values
# Import PI for Angle
from math import PI

# -----------------
# Canvas Controller
# -----------------

controller CXCanvas:
  attributes: {.public.}:
    [zoom, angle]: @ Lerp2
    [x, y]: @ float32
    # Mirror Buttons
    mirrorX: @ bool
    mirrorY: @ bool

  new cxcanvas():
    result.zoom = value lerp2(-5, 5)
    result.angle = value lerp2(-PI, PI)
