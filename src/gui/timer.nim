# Posix Simple Timer for GUI Needes
from posix import 
  CLOCK_MONOTONIC, Time, Timespec,
  clock_gettime, nanosleep

# Defined as this way for other platforms in a future
type GUITimer* = Timespec

# ----------------------
# SIMPLE MONOTONIC TIMER
# ----------------------

# in posix systems, time_t is a clong
proc `+=`(a: var Time, b: Time) {.borrow.}
proc `==`(a, b: Time): bool {.borrow.}
proc `<`(a, b: Time): bool {.borrow.}

proc newTimer*(milsecs: int = 0): GUITimer {.tags: [TimeEffect].} =
  discard clock_gettime(CLOCK_MONOTONIC, result)
  if milsecs > 0:
    let s = result.tv_nsec + (milsecs mod 1000) * 1000_000
    result.tv_sec += Time(milsecs div 1000 + s div 1000_000_000)
    result.tv_nsec = s mod 1000_000_000

proc checkTimer*(a: GUITimer): bool {.tags: [TimeEffect].} =
  let current = newTimer()
  return 
    current.tv_sec > a.tv_sec or 
    (current.tv_sec == a.tv_sec and 
    current.tv_nsec >= a.tv_nsec)

# ------------------
# SYSTEM REIMPLEMENT
# ------------------

proc sleep*(milsecs: int) {.tags: [TimeEffect].} =
  var a, b: Timespec
  a.tv_sec = Time(milsecs div 1000)
  a.tv_nsec = (milsecs mod 1000) * 1000_000
  discard nanosleep(a, b)
