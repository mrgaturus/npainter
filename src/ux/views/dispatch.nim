import nogui/ux/prelude
# TODO: make backup affine backup on engine side
import ../../wip/canvas/matrix
# Import NPainter State
import state

# --------------------------
# NPainter Engine Controller
# --------------------------

# ------------------------------------------
# NPainter Engine Dispatcher Widget
# TODO: make separated widgets for each mode
# ------------------------------------------

widget UXPainterDispatch:
  attributes:
    {.cursor.}:
      state: NPainterState
    # TODO: remove this after fixing nogui issue #23
    affine: NCanvasAffine
    [x, y]: cfloat
    # XXX: hacky way to avoid flooding engine events
    #      - This will be solved unifying event/callback queue
    #      - Also deferring a callback after polling events of a frame
    busy: bool

  # -- Engine Constructor --
  new npainterdispatch():
    discard

  # -- Engine Dispatcher --
  method event(state: ptr GUIState) =
    discard

  method handle(kind: GUIHandle) =
    discard
