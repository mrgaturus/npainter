import nogui/core/[value, callback]
import nogui/ux/values/linear
import nogui/builder
import ../../wip/image
import ../../wip/image/[layer, tiles, context]
import ../../wip/canvas
# This is a proof of concept
# nogui needs to be remaked again to do remaining parts
export layer

controller CXLayers:
  attributes:
    canvas: NCanvasImage
    image: NImage
    # Current State
    {.public.}:
      mode: @ NBlendMode
      opacity: @ Linear
      # Dummies Flags
      clipping: @ bool
      protect: @ bool
      lock: @ bool
      wand: @ bool
      visible: bool
      # On Select Callback
      onselect: GUICallback
      onstructure: GUICallback

  proc root*: NLayer =
    self.image.root
    
  proc selected*: NLayer =
    self.image.selected

  proc reflect(layer: NLayer) =
    let
      flags = layer.props.flags
      opacity = layer.props.opacity
    # Reflect Flags
    self.clipping.peek[] = lpClipping in flags
    self.protect.peek[] = lpProtectAlpha in flags
    self.lock.peek[] = lpLock in flags
    self.wand.peek[] = lpTarget in flags
    # Reflect Opacity
    self.opacity.peek[].lerp opacity

  proc select*(layer: NLayer) =
    self.image.selectLayer(layer)
    self.reflect(layer)
    # React to Selected Changes
    send(self.onselect)

  # --------------------------
  # Layer Control Manipulation
  # --------------------------

  callback cbRender:
    let image = self.image
    # XXX: this is a proof of concept
    # TODO: move this to engine side 
    image.status.clip = mark(0, 0, 0, 0)
    image.status.mark(0, 0, image.ctx.w, image.ctx.h)
    self.canvas.update()

  callback cbUpdateLayer:
    let layer = self.image.selected
    # Create Flags
    var flags = {lpVisible}
    if self.clipping.peek[]: flags.incl(lpClipping)
    if self.protect.peek[]: flags.incl(lpProtectAlpha)
    if self.lock.peek[]: flags.incl(lpLock)
    if self.wand.peek[]: flags.incl(lpTarget)
    # Update Layer Attributes
    layer.props.flags = flags
    layer.props.mode = self.mode.peek[]
    layer.props.opacity = toRaw(self.opacity.peek[])
    # Render Layer
    relax(self.cbRender)

  callback cbCreateLayer:
    let
      image = self.image
      layer = image.createLayer(lkColor)
      selected = image.selected
    # Put Next to Selected
    selected.attachPrev(layer)
    layer.props.flags.incl lpVisible
    layer.props.opacity = 1.0
    # Select New Layer
    self.select(layer)
    send(self.onstructure)
    send(self.cbRender)

  callback cbClearLayer:
    let
      image = self.image
      layer = image.selected
      tiles = addr layer.tiles
    # XXX: this is a proof of concept
    # TODO: move this to engine side 
    tiles[].destroy()
    tiles[] = createTileImage(4)
    # Render Layer
    send(self.cbRender)

  callback cbRemoveLayer:
    let
      image =  self.image
      layer = image.selected
      root = image.root
    # Avoid Delete When is unique
    if root.first == layer and root.last == layer:
      return
    # Change Selected
    if not isNil(layer.next):
      self.select(layer.next)
    else: self.select(layer.prev)
    # Layer Detach and Dealloc
    layer.detach()
    layer.destroy()
    # Render Layer
    send(self.onstructure)
    send(self.cbRender)

  # ----------------------------
  # Layer Control Initialization
  # ----------------------------

  proc bindLayer0proof =
    let
      canvas = self.canvas
      img = canvas.image
      layer = img.createLayer(lkColor)
    # Change Layer Properties
    layer.props.flags.incl(lpVisible)
    layer.props.opacity = 1.0
    # Select Current Layer
    img.root.attachInside(layer)
    img.selectLayer(layer)
    # Update Strcuture
    self.reflect(layer)
    send(self.cbUpdateLayer)
    send(self.onselect)
    send(self.onstructure)

  new cxlayers(canvas: NCanvasImage):
    result.canvas = canvas
    result.image = canvas.image
    result.opacity = linear(0, 100)
    # Configure Attribute Callbacks
    let cb = result.cbUpdateLayer
    result.clipping.cb = cb
    result.protect.cb = cb
    result.lock.cb = cb
    result.wand.cb = cb
    result.opacity.cb = cb
    result.mode.cb = cb
    # Create Initial Layer
    result.bindLayer0proof()
