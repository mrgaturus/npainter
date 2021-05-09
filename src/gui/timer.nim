from posix import
  Time, Timespec, nanosleep
# GUI Monotimic Timer Updates
from std/monotimes import
  getMonoTime, ticks
from signal import GUITarget
from widget import GUIWidget

type
  GUITimer = object
    target: GUITarget
    ticks, nano_ms: int64
  GUITimers = seq[GUITimer]
var # Global Timers
  timers: GUITimers

# --------------------------
# SIMPLE MONOTONIC GUI TIMER
# --------------------------
proc `==`(a, b: GUITarget): bool {.borrow.}

proc current(offset: int64): int64 =
  result = # Get Current Time Plus Offset
    getMonoTime().ticks() + offset

proc check(a: int64): bool =
  let b = # Get Current Monotonic
    getMonoTime().ticks()
  result = b > a

# -- Add a Timer
proc pushTimer*(target: GUITarget, ms = 0) =
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
    # Convert miliseconds to nanoseconds
    let nano_ms = ms * 1000000
    # Create New Timer
    timer.target = target
    timer.ticks = current(nano_ms)
    timer.nano_ms = nano_ms
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
    if check(timer.ticks):
      yield cast[GUIWidget](timer.target)
      # Check if was not deleted
      if L == len(timers):
        timer.ticks = # Renew
          current(timer.nano_ms)
      else: # Deleted Timer
        dec(L); continue
    inc(i) # Next Timer

# --------------------------------
# INFINITE LOOP WITH FRAME LIMITER
# --------------------------------

proc sleep(ns: int64) {.tags: [TimeEffect].} =
  var a, b: Timespec
  a.tv_sec = cast[Time](ns div 1_000_000_000)
  a.tv_nsec = cast[clong](ns mod 1_000_000_000)
  discard nanosleep(a, b)

template loop*(ms: int, body: untyped) =
  let nano_ms = ms * 1000000
  # Procedure Duration
  var a, b, ss: int64
  while true:
    a = current(0)
    body # Execute Body
    b = current(0)
    # Calculate Sleep Time
    ss = max(nano_ms - b + a, 0)
    # Sleep Loop
    sleep(ss)
