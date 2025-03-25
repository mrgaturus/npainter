import nogui/ux/prelude
import nogui/builder
# Import A Dock
import nogui/pack
import nogui/ux/widgets/
  [label, slider, check, radio]
import nogui/ux/layouts/[form, misc]
import nogui/ux/containers/[dock, scroll]
# Import Bucket Data
import ../../state/bucket

proc separator(): UXLabel =
  label("", hoLeft, veMiddle)

# ----------------
# Bucket Tool Dock
# ----------------

icons "tools", 16:
  bucket := "fill.svg"

controller CXBucketDock:
  attributes:
    bucket: CXBucket
    # Usable Dock
    {.public.}:
      dock: UXDockContent

  proc createWidget: GUIWidget =
    let bucket {.cursor.} = self.bucket
    # Create Layout Form
    margin(4): form().child:
      # Bucket Fill Mode
      radio("Transparent Minimum", ord bcmAlphaMin, bucket.mode)
      radio("Transparent Difference", ord bcmAlphaDiff, bucket.mode)
      radio("Color Difference", ord bcmColorDiff, bucket.mode)
      radio("Color Similar", ord bcmColorSimilar, bucket.mode)
      separator() # Bucket Fill Parameters
      field("Threshold"): slider(bucket.threshold)
      field("Gap Closing"): slider(bucket.gap)
      field(): checkbox("Anti-Aliasing", bucket.antialiasing)
      separator() # Bucket Fill Target
      radio("Canvas", ord bctCanvas, bucket.target)
      radio("Layer", ord bctLayer, bucket.target)
      radio("Wand Target", ord bctWandTarget, bucket.target)

  proc createDock() =
    let
      w = scrollview self.createWidget()
      dock = dockcontent("Bucket Tool", iconBucket, w)
    # Define Dock Attribute
    self.dock = dock

  new cxbucketdock(bucket: CXBucket):
    result.bucket = bucket
    result.createDock()
