# Posix Simple Timer for GUI Needes
from posix import 
  CLOCK_MONOTONIC, Time, Timespec,
  clock_gettime, nanosleep
from event import GUITarget
from widget import GUIWidget

type
  GUITimer = object
    target: GUITarget
    stamp: Timespec
    milsecs: int
  GUITimers = seq[GUITimer]
var # Global Timers
  timers: GUITimers

# ----------------------
# SIMPLE MONOTONIC TIMER
# ----------------------

# in posix systems, time_t is a clong
proc `+=`(a: var Time, b: Time) {.borrow.}
proc `==`(a, b: Time): bool {.borrow.}
proc `<`(a, b: Time): bool {.borrow.}
# borrow widget pointer comparing
proc `==`(a, b: GUITarget): bool {.borrow.}

# -- Create Timers
proc current(milsecs: int): Timespec =
  if clock_gettime(CLOCK_MONOTONIC, result) == 0 and milsecs > 0:
    let s = result.tv_nsec + (milsecs mod 1000) * 1000_000
    result.tv_sec += Time(milsecs div 1000 + s div 1000_000_000)
    result.tv_nsec = s mod 1000_000_000

proc check(a: Timespec): bool =
  let b = current(0)
  return # Check Timer
    b.tv_sec > a.tv_sec or 
    (b.tv_sec == a.tv_sec and 
    b.tv_nsec >= a.tv_nsec)

# -- Add a Timer
proc pushTimer*(target: GUITarget, milsecs = 0) =
  var found = false
  block: # Check
    var i: int32
    # Find Timers
    while i < len(timers):
      if timers[i].target == target:
        found = true; break
      inc(i) # Next Timer
  if not found:
    var timer: GUITimer
    timer.target = target
    timer.milsecs = milsecs
    timer.stamp = current(milsecs)
    # Add Timer to Global
    timers.add(timer)

# -- Delete a Timer
proc stopTimer*(target: GUITarget) =
  var i: int32
  # Find Timer and Delete
  while i < len(timers):
    if timers[i].target == target:
      timers.delete(i); break
    inc(i) # Next Timer

# -- Walk Timers
iterator walkTimers*(): GUIWidget =
  var # Iterator
    i, L: int32
    timer: ptr GUITimer
  # Get Current Len
  L = len(timers).int32
  while i < L:
    # Handle Timer
    timer = addr timers[i]
    if check(timer.stamp):
      yield cast[GUIWidget](timer.target)
      # Check if was not deleted
      if L == len(timers):
        timer.stamp = 
          current(timer.milsecs)
      else: # Deleted Timer
        dec(L); continue
    inc(i) # Next Timer

# ------------------
# SYSTEM REIMPLEMENT
# ------------------

proc sleep*(milsecs: int) {.tags: [TimeEffect].} =
  var a, b: Timespec
  a.tv_sec = Time(milsecs div 1000)
  a.tv_nsec = (milsecs mod 1000) * 1000_000
  discard nanosleep(a, b)
