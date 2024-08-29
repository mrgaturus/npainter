import nogui/core/[value, callback]
import nogui/ux/values/linear
import nogui/builder
import ../../wip/image
import ../../wip/image/[layer, tiles, context]
import ../../wip/canvas
# This is a proof of concept
import nogui/core/shortcut
import nogui/ux/prelude
# Move many parts to engine side
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
      # Manipulation Callbacks
      onselect: GUICallback
      onstructure: GUICallback
      onorder: GUICallbackEX[NLayer]

  proc root*: NLayer =
    self.image.root
    
  proc selected*: NLayer =
    self.image.selected

  proc reflect(layer: NLayer) =
    let
      flags = layer.props.flags
      opacity = layer.props.opacity
    # Reflect Layer Flags
    self.clipping.peek[] = lpClipping in flags
    self.protect.peek[] = lpProtectAlpha in flags
    self.lock.peek[] = lpLock in flags
    self.wand.peek[] = lpTarget in flags
    # Reflect Mode and Opacity
    self.mode.peek[] = layer.props.mode
    self.opacity.peek[].lerp opacity

  proc select*(layer: NLayer) =
    let
      u0 {.cursor.} = cast[GUIWidget](self.selected.user)
      u1 {.cursor.} = cast[GUIWidget](layer.user)
    # Select Current Layer
    self.image.selectLayer(layer)
    self.reflect(layer)
    # Update Widgets
    send(self.onselect)
    u0.send(wsLayout)
    u1.send(wsLayout)

  proc create(kind: NLayerKind) =
    let
      image = self.image
      layer = image.createLayer(kind)
      target = image.selected
    # Put Next to Selected or Inside a Folder
    if target.kind != lkFolder or kind == lkFolder:
      target.attachPrev(layer)
    else: target.attachInside(layer)
    # Default Layer Properties
    layer.props.flags.incl(lpVisible)
    layer.props.opacity = 1.0
    # Select New Layer
    force(self.onstructure)
    self.select(layer)
    # Render Layer
    send(self.cbRender)

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
    let
      layer = self.image.selected
      props = addr layer.props
      user {.cursor.} = cast[GUIWidget](layer.user)
    # Update Layer Properties Flags
    var flags = props.flags - {lpClipping .. lpLock}
    if self.clipping.peek[]: flags.incl(lpClipping)
    if self.protect.peek[]: flags.incl(lpProtectAlpha)
    if self.wand.peek[]: flags.incl(lpTarget)
    if self.lock.peek[]: flags.incl(lpLock)
    # Update Layer Attributes
    props.flags = flags
    props.mode = self.mode.peek[]
    props.opacity = self.opacity.peek[].toRaw
    # Render Layer
    user.send(wsLayout)
    relax(self.cbRender)

  callback cbCreateLayer:
    self.create(lkColor)

  callback cbCreateFolder:
    self.create(lkFolder)

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
    # Avoid Delete When is Unique
    if root.first == layer and root.last == layer:
      return
    # Change Selected
    if not isNil(layer.next):
      self.select(layer.next)
    elif not isNil(layer.prev):
      self.select(layer.prev)
    # Change Selected to Parent Folder
    else: self.select(layer.folder)
    # Layer Detach and Dealloc
    layer.detach()
    layer.destroy()
    # Render Layer
    send(self.onstructure)
    send(self.cbRender)

  callback cbOrderLayer(order: NLayerOrder):
    let
      target = order.target
      layer = order.layer
    # Avoid Unknown Attach
    if order.mode == ltAttachUnknown:
      return
    # Dettach Layer First
    layer.detach()
    # Attach Layer to Target
    case order.mode
    of ltAttachNext: target.attachNext(layer)
    of ltAttachPrev: target.attachPrev(layer)
    of ltAttachFolder: target.attachInside(layer)
    of ltAttachUnknown: discard
    # Render Layer
    force(self.onstructure)
    send(self.cbRender)

  callback cbRaiseLayer:
    let target = self.selected
    if target == self.root.first:
      return
    # Decide Pivot Layer
    var pivot = target.prev
    let escape = isNil(pivot)
    if escape: pivot = target.folder
    # Detach Layer
    target.detach()
    # Attach Layer Inside Folder
    if pivot.kind == lkFolder and not escape:
      if not isNil(pivot.last):
        pivot.last.attachNext(target)
      else: pivot.attachInside(target)
    # Attach Layer Previous Pivot
    else: pivot.attachPrev(target)
    # Render Composition
    force(self.onstructure)
    send(self.cbRender)

  callback cbLowerLayer:
    let target = self.selected
    if target == self.root.last:
      return
    # Decide Pivot Layer
    var pivot = target.next
    let escape = isNil(pivot)
    if escape: pivot = target.folder
    # Detach Layer
    target.detach()
    # Attach Layer Inside Folder or Next
    if pivot.kind == lkFolder and not escape:
      pivot.attachInside(target)
    else: pivot.attachNext(target)
    # Render Composition
    force(self.onstructure)
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
    img.root.attachInside img.createLayer(lkColor)
    img.root.attachInside img.createLayer(lkColor)
    let folder0 = img.createLayer(lkFolder)
    let folder1 = img.createLayer(lkFolder)
    let folder2 = img.createLayer(lkFolder)
    let folder3 = img.createLayer(lkFolder)
    img.root.attachInside(folder0)
    folder0.attachInside img.createLayer(lkColor)
    folder0.attachInside img.createLayer(lkColor)
    folder0.attachInside folder2
    folder0.attachInside folder3
    folder0.attachInside folder1
    folder1.attachInside img.createLayer(lkColor)
    folder1.attachInside img.createLayer(lkColor)
    folder1.attachInside img.createLayer(lkColor)
    folder2.props.flags.incl(lpFolded)
    folder3.props.flags.incl(lpFolded)
    img.selectLayer(layer)
    # Update Strcuture
    self.reflect(layer)
    send(self.cbUpdateLayer)
    send(self.onselect)
    send(self.onstructure)
    # Delete Shortcut for Clear Layer
    getWindow().shorts[].register:
      shortcut(self.cbClearLayer, NK_Delete)

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
