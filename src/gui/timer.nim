# Posix Simple Timer for GUI Needes
from posix import 
  CLOCK_MONOTONIC, Time, Timespec,
  clock_gettime, nanosleep
from event import GUITarget
from widget import GUIWidget

type
  GUITimer = object
    target: GUITarget
    secs: Timespec
    # Ignore Secs
    now: bool
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

# -- Push Timers
proc pushTimer*(target: GUITarget, milsecs: int) =
  var timer: GUITimer
  timer.target = target
  timer.secs = current(milsecs)
  # Add Timer to Global
  timers.add(timer)

proc pushTimer*(target: GUITarget) =
  var timer: GUITimer
  timer.target = target
  timer.now = true
  # Add Timer to Global
  timers.add(timer)

# -- Delete a Timer
proc stopTimer*(target: GUITarget) =
  var i: int32
  # Find Timer and Delete
  while i < len(timers):
    if timers[i].target == target:
      timers.delete(i)
      break # Stop Loop
    inc(i) # Next Timer

# -- Walk Timers
iterator walkTimers*(): GUIWidget =
  var timer: ptr GUITimer
  var i, L: int32
  # Get Current Len
  L = len(timers).int32
  while i < L:
    # Handle Timer
    timer = addr timers[i]
    if timer.now or check(timer.secs):
      yield cast[GUIWidget](timer.target)
    # Handle Deleted Timer
    if L != len(timers):
      dec(L) # Dec Len
    else: inc(i)

# ------------------
# SYSTEM REIMPLEMENT
# ------------------

proc sleep*(milsecs: int) {.tags: [TimeEffect].} =
  var a, b: Timespec
  a.tv_sec = Time(milsecs div 1000)
  a.tv_nsec = (milsecs mod 1000) * 1000_000
  discard nanosleep(a, b)
