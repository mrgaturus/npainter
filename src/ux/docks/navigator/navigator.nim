import ../../state/canvas
import view
# Import Value Formatting
import nogui/format
import nogui/ux/values/dual
from math import pow, radToDeg
# Import Builder
import nogui/pack
import nogui/ux/prelude
import nogui/builder
# Import Widgets
import nogui/ux/layouts/[box, level, form, misc]
import nogui/ux/widgets/[button, slider, check]
import nogui/ux/containers/dock
import nogui/ux/separator

# ----------------
# Value Formatting
# ----------------

proc fmtZoom(s: ShallowString, v: LinearDual) =
  let 
    f = v.toFloat
    fs = pow(2.0, f) * 100.0
  if f >= 0:
    let i = int32(fs)
    s.format("%d%%", i)
  else: s.format("%.1f%%", fs)

proc fmtAngle(s: ShallowString, v: LinearDual) =
  let deg = radToDeg(v.toFloat)
  s.format("%.1f°", deg)

# ---------------------
# Canvas Navigator Dock
# ---------------------

icons "dock/navigator", 16:
  navigator := "navigator.svg"
  # Zoom Control
  zoomFit := "zoom_fit.svg"
  zoomPlus := "zoom_plus.svg"
  zoomMinus := "zoom_minus.svg"
  # Angle Control
  rotateReset := "rotate_reset.svg"
  rotateLeft := "rotate_left.svg"
  rotateRight := "rotate_right.svg"
  # Mirror Control
  mirrorHor := "mirror_hor.svg"
  mirrorVer := "mirror_ver.svg"

controller CXNavigatorDock:
  attributes:
    canvas: CXCanvas
    # Navigator View
    {.cursor.}:
      view: UXNavigatorView
    # Usable Dock
    {.public.}:
      dock: UXDockContent

  callback cbDummy:
    discard

  proc createWidget: GUIWidget =
    let
      canvas {.cursor.} = self.canvas
      view = navigatorview()
    # Store View
    self.view = view
    vertical().child:
      view
      # Quick Canvas Buttons
      min: horizontal().child:
        level().child:
          # Zoom Control
          glass: button(iconZoomFit, canvas.cbZoomReset)
          glass: button(iconZoomPlus, canvas.cbZoomInc)
          glass: button(iconZoomMinus, canvas.cbZoomDec)
          vseparator() # Angle Control
          glass: button(iconRotateReset, canvas.cbAngleReset)
          glass: button(iconRotateLeft, canvas.cbAngleDec)
          glass: button(iconRotateRight, canvas.cbAngleInc)
          # Mirror Control
          tail: button(iconMirrorVer, canvas.mirrorY)
          tail: button(iconMirrorHor, canvas.mirrorX)
      # Canvas Sliders
      min: margin(4): form().child:
        field("Zoom"): dual0float(canvas.zoom, fmtZoom)
        field("Angle"): dual0float(canvas.angle, fmtAngle)

  proc createDock() =
    let body = self.createWidget()
    self.dock = dockcontent("Navigator", iconNavigator, body)

  new cxnavigatordock(canvas: CXCanvas):
    result.canvas = canvas
    # Create Widgets
    result.createDock()
