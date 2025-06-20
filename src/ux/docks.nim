import nogui/core/value
import nogui/ux/layouts/base
import nogui/builder
# Import State Controllers
import state
# Import Docks
import nogui/ux/containers/dock
import docks/[
  color/color,
  brush/brush,
  navigator/navigator,
  layers/layers,
  tools/bucket,
  tools/shape
]

# ------------------------------------------------
# Dock Tool Controller
# TODO: create a proper way to swap a dock content
#       nogui -> ux: docking part 2
# ------------------------------------------------

controller CXToolDock:
  attributes:
    # State Controller
    {.cursor.}:
      state: NPainterState
    # Tool Dock Controllers
    dockLasso: CXLassoDock
    dockSelect: CXSelectionDock
    dockBrush: CXBrushDock
    dockBucket: CXBucketDock
    dockShapes: CXShapeDock
    dockDummy: UXDockContent
    # Dock Content Array Lookup
    lookup: array[CKPainterTool, UXDockContent]
    {.public.}:
      dock: UXDockContent

  proc createDummy =
    self.dockDummy = dockcontent("Wip Tool", dummy())
    self.dock = dockcontent("Wip Tool", dummy())

  proc createLookups =
    let 
      lo = addr self.lookup
      dummy = self.dockDummy
    # Manupulation Docks
    lo[stMove] = dummy
    lo[stLasso] = self.dockLasso.dock
    lo[stSelect] = self.dockSelect.dock
    lo[stWand] = dummy
    # Painting Tools
    lo[stBrush] = self.dockBrush.dock
    lo[stEraser] = self.dockBrush.dock
    lo[stFill] = self.dockBucket.dock
    lo[stEyedrop] = dummy
    # Special Tools
    lo[stShapes] = self.dockShapes.dock
    lo[stGradient] = dummy
    lo[stText] = dummy
    lo[stCanvas] = dummy

  proc select(tool: CKPainterTool) =
    let
      found {.cursor.} = self.lookup[tool]
      dock {.cursor.} = self.dock
    # Avoid Replace Same Widget
    if found.widget == dock.widget:
      return
    # Replace Current Dock
    privateAccess(UXDockContent)
    dock.widget = found.widget
    dock.serial = found.serial
    dock.title = found.title
    dock.icon = found.icon
    # Update Dock if Attached
    if dock.attached():
      dock.select()

  new cxtooldock(state: NPainterState):
    result.state = state
    # Initialize Docks
    result.dockLasso = cxlassodock(state.shape)
    result.dockSelect = cxselectiondock(state.shape)
    result.dockBrush = cxbrushdock(state.brush)
    result.dockBucket = cxbucketdock(state.bucket)
    result.dockShapes = cxshapedock(state.shape)
    # Create Dock Lookups
    result.createDummy()
    result.createLookups()

# ----------------
# Docks Controller
# ----------------

controller CXDocks:
  attributes:
    # State Controller
    {.cursor.}:
      state: NPainterState
    # Dock Controllers
    dockColor: CXColorDock
    dockNav: CXNavigatorDock
    dockLayers: CXLayersDock
    dockTool: CXToolDock
    # Session Manager
    {.public.}:
      session: UXDockSession

  proc select*(tool: CKPainterTool) =
    self.dockTool.select(tool)

  new cxdocks(state: NPainterState, root: GUIWidget):
    let session = docksession(root)
    result.session = session
    result.state = state
    # Initialize Docks
    result.dockColor = cxcolordock(state.color)
    result.dockNav = cxnavigatordock(state.canvas)
    result.dockLayers = cxlayersdock(state.layers)
    result.dockTool = cxtooldock(state)

# --------------------------------
# Proof of Concept Default Arrange
# --------------------------------

proc dockpanel(dock: UXDockContent): UXDockPanel =
  result = dockpanel()
  result.add(dock)

proc proof0arrange*(self: CXDocks) =
  let
    session {.cursor.} = self.session
    docks {.cursor.} = session.docks
  # Adjust Dock Sizes
  self.dockTool.dock.h = 400
  self.dockNav.dock.h = 220
  self.dockLayers.dock.h = 400
  # Create Left Side
  let left = dockgroup:
    dockcolumns().child:
      dockrow().child:
        dockpanel(self.dockColor.dock)
        dockpanel(self.dockTool.dock)
  # Create Right Side
  let right = dockgroup:
    dockcolumns().child:
      dockrow().child:
        dockpanel(self.dockNav.dock)
        dockpanel(self.dockLayers.dock)
  # Add Docks to Session
  docks.add(left)
  docks.add(right)
  docks.left = left
  docks.right = right
