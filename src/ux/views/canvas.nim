import nogui/builder
import nogui/gui/value
import nogui/values

# -----------------
# Canvas Controller
# -----------------

controller CXCanvas:
  attributes: {.public.}:
    [zoom, angle]: @ Lerp
    [x, y]: @ float32
    # Mirror Buttons
    mirrorX: @ bool
    mirrorY: @ bool

  new cxcanvas():
    result.zoom = value lerp(0.015625, 6400)
    result.angle = value lerp(0, 360)
