import ../../canvas
import view
# Import Builder
import nogui/pack
import nogui/ux/prelude
import nogui/builder
# Import Widgets
import nogui/ux/layouts/[box, level, form, misc]
import nogui/ux/widgets/[button, slider]
import ../../../containers/dock
import ../../../widgets/separator

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
      dock: UXDock

  callback cbDummy:
    discard

  proc createWidget: GUIWidget =
    let
      canvas {.cursor.} = self.canvas
      view = navigatorview()
      cb = self.cbDummy
    # Store View
    self.view = view
    vertical().child:
      view
      # Quick Canvas Buttons
      min: horizontal().child:
        level().child:
          # Zoom Control
          button(iconZoomFit, cb).opaque()
          button(iconZoomPlus, cb).opaque()
          button(iconZoomMinus, cb).opaque()
          vseparator() # Angle Control
          button(iconRotateReset, cb).opaque()
          button(iconRotateLeft, cb).opaque()
          button(iconRotateRight, cb).opaque()
          # Mirror Control
          tail: button(iconMirrorVer, cb).opaque
          tail: button(iconMirrorHor, cb).opaque
      # Canvas Sliders
      min: margin(4): form().child:
        field("Zoom"): slider(canvas.zoom)
        field("Angle"): slider(canvas.angle)

  proc createDock() =
    let body = self.createWidget()
    self.dock = dock("Navigator", iconNavigator, body)

  new cxnavigatordock(canvas: CXCanvas):
    result.canvas = canvas
    # Create Widgets
    result.createDock()
