# ---------------
# BITFLAGS EXTRAS
# ---------------

proc testMask*[T: SomeInteger](v: T, mask: T): bool {.inline.} =
  ## Returns true if the ``mask`` in ``v`` is set to 1
  return (v and mask) == mask

proc anyMask*[T: SomeInteger](v: T, mask: T): bool {.inline.} =
  ## Returns true if at least one bit of the ``mask`` in ``v`` is set to 1
  return (v and mask) != 0

# ----------
# SEQ EXTRAS
# ----------

iterator pitems*[T](a: var seq[T]): ptr T {.inline.} =
  ## Iterates over each item of `a` and yields it's pointer.
  var i = 0
  let L = len(a)
  while i < L:
    yield addr a[i]
    inc(i)