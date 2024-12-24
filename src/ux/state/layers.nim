# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
import nogui/core/[value, callback]
import nogui/ux/values/linear
import nogui/builder
import ../../wip/[image, undo]
import ../../wip/image/[layer, tiles, context]
import ../../wip/canvas
# TODO: Move many parts to engine side
import nogui/ux/prelude
export layer

controller CXLayers:
  attributes:
    canvas: NCanvasImage
    image: NImage
    step: NUndoStep
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

  proc reflect*(layer: NLayer) =
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
    send(self.onselect)

  # ----------------------------
  # Layer Rendering Manipulation
  # ----------------------------

  proc select*(layer: NLayer) =
    let
      u0 {.cursor.} = cast[GUIWidget](self.selected.user)
      u1 {.cursor.} = cast[GUIWidget](layer.user)
    # Select Current Layer
    self.image.selectLayer(layer)
    self.reflect(layer)
    # Update Widgets
    u0.send(wsLayout)
    u1.send(wsLayout)

  proc create(kind: NLayerKind) =
    let
      image = self.image
      layer = image.createLayer(kind)
      target = image.selected
      # Undo Step Capture
      undo = self.canvas.undo
      step = undo.push(ucLayerCreate)
    # Put Next to Selected or Inside a Folder
    if target.kind != lkFolder or kind >= lkMask:
      target.attachPrev(layer)
    else: target.attachInside(layer)
    # Default Layer Properties
    var flags = {lpVisible}
    if kind == lkMask:
      flags.incl(lpClipping)
      layer.props.mode = bmMask
    layer.props.opacity = 1.0
    layer.props.flags = flags
    # Select New Layer
    force(self.onstructure)
    self.select(layer)
    # Capture Undo Step
    step.capture(layer)
    undo.flush()

  # ----------------------------
  # Layer Rendering Manipulation
  # ----------------------------

  callback cbRender:
    self.canvas.update()

  proc render*(layer: NLayer) =
    let image {.cursor.} = self.image
    # TODO: Calculate AABB of Layer
    complete(image.status.clip)
    image.markLayer(layer)
    # Send Rendering Callback
    relax(self.cbRender)

  # --------------------------
  # Layer Control Manipulation
  # --------------------------

  callback cbUpdateLayer:
    var layer = self.image.selected
    let props = addr layer.props
    let user {.cursor.} = cast[GUIWidget](layer.user)
    # Update Layer Properties Flags
    let flags0 = props.flags
    var flags = flags0 - {lpClipping .. lpLock}
    if self.clipping.peek[]: flags.incl(lpClipping)
    if self.protect.peek[]: flags.incl(lpProtectAlpha)
    if self.wand.peek[]: flags.incl(lpTarget)
    if self.lock.peek[]: flags.incl(lpLock)
    # Update Layer Attributes
    props.flags = flags
    props.mode = self.mode.peek[]
    props.opacity = self.opacity.peek[].toRaw
    if (lpClipping in flags0) != (lpClipping in flags):
      layer = layer.folder
    # Update Layer Widget
    user.send(wsLayout)
    self.render(layer)

  callback cbPropLayer:
    let undo = self.canvas.undo
    let layer = self.image.selected
    let step = undo.push(ucLayerProps)
    step.capture(layer)
    # Dispatch Layer Update
    force(self.cbUpdateLayer)
    # Capture Undo Step
    step.capture(layer)
    undo.flush()

  callback cbSliderLayer:
    let event = getApp().state.kind
    let undo = self.canvas.undo
    let layer = self.image.selected
    # Prepare Undo Step
    if event == evCursorClick:
      self.step = undo.push(ucLayerProps)
      capture(self.step, layer)
    # Dispatch Layer Update
    force(self.cbUpdateLayer)
    # Capture Undo Step
    if event == evCursorRelease:
      capture(self.step, layer)
      undo.flush()

  proc cbVisibleLayer*(layer: NLayer) =
    let event = getApp().state.kind
    let undo = self.canvas.undo
    # Flush Undo Steps
    if event == evCursorRelease:
      undo.flush()
      return
    # Capture Toggle Visible
    let step = undo.chain(ucLayerProps)
    step.capture(layer)
    var flags = cast[uint32](layer.props.flags)
    flags = flags xor cast[uint32]({lpVisible})
    layer.props.flags = cast[set[NLayerFlag]](flags)
    step.capture(layer)
    self.render(layer)

  # ----------------------
  # Layer Control Creating
  # ----------------------

  callback cbCreateLayer:
    self.create(lkColor16)

  callback cbCreateFolder:
    self.create(lkFolder)

  callback cbCreateMask:
    self.create(lkMask)

  callback cbDuplicateLayer:
    let
      undo = self.canvas.undo
      image {.cursor.} = self.image
      layer = image.selected
    # Copy Layer And Attach Prev
    let la = image.copyLayer(layer)
    layer.attachPrev(la)
    # Capture Layer Undo
    let step = undo.push(ucLayerCreate)
    step.capture(la)
    undo.flush()
    # Select and Render Layer
    force(self.onstructure)
    self.select(la)
    self.render(layer)

  callback cbMergeLayer:
    let
      image {.cursor.} = self.image
      undo = self.canvas.undo
      layer = image.selected
      target = layer.next
    # Avoid Merge Invalid Layer
    if isNil(target) or
        target.kind == lkFolder or
        layer.kind == lkFolder:
      return
    # Create Undo Steps
    let
      la = image.mergeLayer(layer, target)
      step0 = undo.chain(ucLayerCreate)
      step1 = undo.chain(ucLayerDelete)
      step2 = undo.chain(ucLayerDelete)
    # Dispatch Layer Merge
    layer.attachPrev(la)
    step1.capture(layer); layer.detach(); layer.destroy()
    step2.capture(target); target.detach(); target.destroy()
    step0.capture(la)
    # Update Layer Structure
    force(self.onstructure)
    self.select(la)
    self.render(la)
    undo.flush()

  callback cbClearLayer:
    let
      image = self.image
      undo = self.canvas.undo
      # Current Layer Selected
      layer = image.selected
      tiles = addr layer.tiles
    # Capture Before Tiles
    if layer.kind == lkFolder: return
    let step = undo.push(ucLayerTiles)
    step.capture(layer)
    self.render(layer)
    # Clear Layer Tiles
    tiles[].clear()
    step.capture(layer)
    undo.flush()

  callback cbRemoveLayer:
    let
      image = self.image
      undo = self.canvas.undo
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
    # Prepare Rendering
    self.render(layer)
    # Capture Undo Command
    let step = undo.push(ucLayerDelete)
    step.capture(layer)
    undo.flush()
    # Destroy Layer
    layer.detach()
    layer.destroy()
    # Update Layer Structure
    send(self.onstructure)

  callback cbOrderLayer(order: NLayerOrder):
    let
      undo = self.canvas.undo
      target = order.target
      layer = order.layer
    # Avoid Unknown Attach
    if order.mode == ltAttachUnknown:
      return
    # Dettach Layer First
    let step = undo.push(ucLayerReorder)
    step.capture(layer)
    layer.detach()
    # Attach Layer to Target
    case order.mode
    of ltAttachNext: target.attachNext(layer)
    of ltAttachPrev: target.attachPrev(layer)
    of ltAttachFolder: target.attachInside(layer)
    of ltAttachUnknown: discard
    step.capture(layer)
    undo.flush()
    # Render Layer
    force(self.onstructure)
    self.render(layer)

  callback cbRaiseLayer:
    let undo = self.canvas.undo
    let target = self.selected
    if target == self.root.first:
      return
    # Decide Pivot Layer
    var pivot = target.prev
    let escape = isNil(pivot)
    if escape: pivot = target.folder
    # Detach Layer
    let step = undo.push(ucLayerReorder)
    step.capture(target)
    target.detach()
    # Attach Layer Inside Folder
    if pivot.kind == lkFolder and not escape:
      if not isNil(pivot.last):
        pivot.last.attachNext(target)
      else: pivot.attachInside(target)
    # Attach Layer Previous Pivot
    else: pivot.attachPrev(target)
    # Capture Undo
    step.capture(target)
    undo.flush()
    # Render Composition
    force(self.onstructure)
    self.render(target)

  callback cbLowerLayer:
    let undo = self.canvas.undo
    let target = self.selected
    if target == self.root.last:
      return
    # Decide Pivot Layer
    var pivot = target.next
    let escape = isNil(pivot)
    if escape: pivot = target.folder
    # Detach Layer
    let step = undo.push(ucLayerReorder)
    step.capture(target)
    target.detach()
    # Attach Layer Inside Folder or Next
    if pivot.kind == lkFolder and not escape:
      pivot.attachInside(target)
    else: pivot.attachNext(target)
    # Capture Undo
    step.capture(target)
    undo.flush()
    # Render Composition
    force(self.onstructure)
    self.render(target)

  # ----------------------------
  # Layer Control Initialization
  # ----------------------------

  new cxlayers(canvas: NCanvasImage):
    result.canvas = canvas
    result.image = canvas.image
    result.opacity = linear(0, 100)
    # Configure Attribute Callbacks
    let cb0 = result.cbPropLayer
    let cb1 = result.cbSliderLayer
    result.clipping.cb = cb0
    result.protect.cb = cb0
    result.lock.cb = cb0
    result.wand.cb = cb0
    result.opacity.cb = cb1
    result.mode.cb = cb0

  proc proof0default*() =
    let
      canvas = self.canvas
      img = canvas.image
    # Create Default Layer
    let layer = img.createLayer(lkColor16)
    layer.props.flags.incl(lpVisible)
    layer.props.opacity = 1.0
    img.root.attachInside(layer)
    # Select Current Layer
    img.selectLayer(layer)
    self.reflect(layer)
    # Update Structure
    force(self.onstructure)
    force(self.cbUpdateLayer)
    force(self.onselect)
