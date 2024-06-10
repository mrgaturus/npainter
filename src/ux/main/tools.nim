from nogui/builder import controller, child
from nogui/pack import icons
# Import Widget and Layout
import nogui/core/value
import nogui/ux/layouts/level
import nogui/ux/widgets/radio
import nogui/ux/separator
# Import Selected Kind Dock
from ../state import CKPainterTool

icons "tools", 24:
  logo *= "circle.svg"
  move := "move.svg"
  lasso := "lasso.svg"
  select := "select.svg"
  wand := "wand.svg"
  # Painting Tools
  brush := "brush.svg"
  eraser := "eraser.svg"
  fill := "fill.svg"
  eyedrop := "eyedrop.svg"
  # Special Tools
  shapes := "shapes.svg"
  gradient := "gradient.svg"
  text := "text.svg"
  canvas := "canvas.svg"

controller NCMainTools:
  attributes:
    select: & int32

  new ncMainTools(select: & CKPainterTool):
    result.select = cast[& int32](select)

  proc createToolbar*: UXLayoutVLevel =
    let s = self.select
    vlevel().child:
      button(iconMove, s, ord stMove)
      button(iconLasso, s, ord stLasso)
      button(iconSelect, s, ord stSelect)
      button(iconWand, s, ord stWand)
      # Paint Tools
      separator()
      button(iconBrush, s, ord stBrush)
      button(iconEraser, s, ord stEraser)
      button(iconFill, s, ord stFill)
      button(iconEyedrop, s, ord stEyedrop)
      # Special Tools
      separator()
      button(iconShapes, s, ord stShapes)
      button(iconGradient, s, ord stGradient)
      button(iconText, s, ord stText)
      separator()
      button(iconCanvas, s, ord stCanvas)
