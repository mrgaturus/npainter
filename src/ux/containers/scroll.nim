# TODO: make own nogui/value lerp for scrollbar
import nogui/values
import nogui/gui/value
# Import Scroll Widget
import nogui/ux/widgets/scroll
import nogui/ux/prelude

widget UXScrollView:
  attributes: 
    {.cursor.}:
      view: GUIWidget
    # Scroller
    scroll: UXScroll
    offset: float32
    value: @ Lerp

  callback cbScroll:
    self.vtable.layout(self)
    self.view.arrange()

  new scrollview(view: GUIWidget):
    var v = lerp(0, 0); v.lerp(0)
    # Create Scrollbar and Bind Value
    let scroll = scrollbar(result.value, true)
    result.value = v.value(result.cbScroll)
    # Add Widgets to Result
    result.add view
    result.add scroll
    # Store View and Scroll
    result.view = view
    result.scroll = scroll

  method update =
    let
      m = addr self.metrics
      m0 = addr self.view.metrics
      ms = addr self.scroll.metrics
      # TODO: allow customize margin
      margin = getApp().font.size shr 1
      v = peek(self.value)
    # Horizontal Min Size
    m.minW = m0.minW + margin + ms.minW
    m.minH = ms.minH
    # Update Interval
    var t: float32
    let factor = m0.minH - m.h
    if factor > 0:
      t = self.offset / float32 factor
    # Apply Current Position
    v[].interval(float32 m0.minH)
    v[].lerp(t)
    # Offset Was Consumed
    self.offset = 0.0

  method layout =
    let 
      m = self.metrics
      m0 = addr self.view.metrics
      ms = addr self.scroll.metrics
      # TODO: allow customize margin
      margin = getApp().font.size shr 1
    # Scroll Size
    var msw = ms.minW
    # Adjust Vertical
    block layoutH:
      let 
        v = peek(self.value)
        factor = m0.minH - m.h
      # Set Current Factor Value
      if factor > 0:
        let raw = # Calculate Moved Distance
          v[].toRaw * factor.toFloat
        # Set Current Layout
        self.offset = raw
        m0.y = - int16(raw + 0.5)
      else: # Hide Scroll
        v[].lerp(0)
        msw = -msw
        m0.y = 0
      # Set Size
      m0.h = m0.minH
    # Adjust Horizontal
    block layoutW:
      m0.x = 0
      ms.x = 0
      m0.w = m.w
      ms.w = msw
      # Adjust Margin & Scroller
      if msw > 0:
        m0.w -= msw + margin
        ms.x = m.w - msw
        ms.h = m.h
