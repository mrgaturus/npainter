import nogui/gui/value
import nogui/builder
# Import Values
import nogui/values

# ----------------------
# Bucket Tool Controller
# ----------------------

type
  CKBucketMode* = enum
    bcmAlphaMin
    bcmAlphaDiff
    bcmColorDiff
    bcmColorSimilar
  CKBucketTarget* = enum
    bctCanvas
    bctLayer
    bctWandTarget

controller CXBucket:
  attributes: {.public.}:
    mode: @ int32
    target: @ int32
    # Bucket Fill Parameters
    threshold: @ Lerp
    gap: @ Lerp
    antialiasing: @ bool

  new cxbucket():
    let lerpBasic = lerp(0, 100)
    result.threshold = lerpBasic.value
    result.gap = lerpBasic.value
