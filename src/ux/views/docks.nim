import nogui/gui/value
import nogui/ux/layouts/base
import nogui/builder
# Import State Controllers
import state
# Import Docks
import ../containers/dock
from ../containers/dock/dock import replace0awful
from ../containers/dock/session import watch
import docks/[
  color/color,
  brush/brush,
  navigator/navigator,
  layers/layers,
  tools/bucket
]

# --------------------
# Dock Tool Controller
# --------------------

controller CXToolDock:
  attributes:
    # State Controller
    {.cursor.}:
      state: NPainterState
      session: UXDockSession
    # Tool Dock Controllers
    dockBrush: CXBrushDock
    dockBucket: CXBucketDock
    dockDummy: UXDock
    # Dock Array
    lookup: array[CKPainterTool, UXDock]
    # Usable Dock
    {.public.}:
      dock: UXDock

  callback cbChange:
    var
      idx = CKPainterTool self.state.tool.peek[]
      found {.cursor.} = self.lookup[idx]
    # Replace Current Dock
    replace0awful(self.dock, found)

  proc createLookups =
    let 
      lo = addr self.lookup
      dummy = self.dockDummy
    # Manupulation Docks
    lo[stMove] = dummy
    lo[stLasso] = dummy
    lo[stSelect] = dummy
    lo[stWand] = dummy
    # Painting Tools
    lo[stBrush] = self.dockBrush.dock
    lo[stEraser] = self.dockBrush.dock
    lo[stFill] = self.dockBucket.dock
    lo[stEyedrop] = dummy
    # Special Tools
    lo[stShapes] = dummy
    lo[stGradient] = dummy
    lo[stText] = dummy

  new cxtooldock(state: NPainterState, session: UXDockSession):
    result.state = state
    result.session = session
    # Initialize Docks
    result.dockBrush = cxbrushdock(state.brush)
    result.dockBucket = cxbucketdock(state.bucket)
    # XXX: docking needs a callback when tool is changed
    #      eventually more widgets may need react to tool change
    #      -- possiblity when change tool, also change dispatcher --
    state.tool = value(int32 stBrush, result.cbChange)
    let dummy = dock("wip tool", CTXIconEmpty, dummy())
    result.dockDummy = dummy
    # XXX: hacky way to change a dock
    #      this will be fixed when nogui core
    #      and dock system got remake
    result.dock = dock("wip tool", CTXIconEmpty, dummy())
    # Create Dock Lookups
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
    # TODO: this will be a widget
    {.public.}:
      session: UXDockSession

  new cxdocks(state: NPainterState):
    let session = docksession()
    result.session = session
    result.state = state
    # Initialize Docks
    result.dockColor = cxcolordock(state.color)
    result.dockNav = cxnavigatordock(state.canvas)
    result.dockLayers = cxlayersdock()
    result.dockTool = cxtooldock(state, session)
    # Session Watch Docks
    session.watch(result.dockColor.dock)
    session.watch(result.dockNav.dock)
    session.watch(result.dockLayers.dock)
    session.watch(result.dockTool.dock)

# --------------------------------
# Proof of Concept Default Arrange
# --------------------------------
import ../containers/dock/group

proc proof0arrange*(docks: CXDocks) =
  let session = docks.session
  # Left Panel
  block leftPanel:
    let 
      row = dockrow()
      d0 = docks.dockColor.dock
      d1 = docks.dockTool.dock
      n0 = docknode(d0)
      n1 = docknode(d1)
      group = dockgroup(row)
    # Resize Docks
    d0.resize(230, 220)
    d1.resize(230, 350)
    # Watch Group to Session
    session.left = group
    session.watch(group)
    # Attach Nodes
    row.attach(n0)
    n0.attach(n1)
    # Open Nodes
    d0.open()
    d1.open()
    group.open()
  # Right Panel
  block rightPanel:
    let 
      row = dockrow()
      d0 = docks.dockNav.dock
      d1 = docks.dockLayers.dock
      # Awful Nodes
      n0 = docknode(d0)
      n1 = docknode(d1)
      group = dockgroup(row)
    # Resize Docks
    d0.resize(250, 220)
    d1.resize(250, 450)
    # Watch Group to Session
    session.right = group
    session.watch(group)
    # Attach Nodes
    row.attach(n0)
    n0.attach(n1)
    # Open Nodes
    d0.open()
    d1.open()
    group.open()
