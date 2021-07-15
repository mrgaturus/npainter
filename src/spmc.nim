from typetraits import
  supportsCopyMem
# Thread Sync
import locks, atomics

type
  NThread = 
    Thread[ptr NThreadLane]
  NThreadProc = # Guaranted To Be Safe by Macro
    proc (data: pointer) {.nimcall, gcsafe.}
  NThreadGenericProc[T] =
    proc (data: ptr T) {.nimcall.}
  NThreadTask = object
    fn: NThreadProc
    data: pointer
  # -- Thread Lanes
  ThreadRing = object
    prev: NThreadRing
    # Buffer Size
    size, m: int
    # Buffer Unchecked Array
    buffer: UncheckedArray[NThreadTask]
  NThreadRing = ptr ThreadRing
  NThreadLane = object
    pool: NThreadPool
    # Queue Mutex
    mtx: Lock
    # Ring Buffer
    top, bottom: int
    ring: NThreadRing
  # -- Thread Pool
  NThreadStatus = enum
    ntSleep
    ntWorking
    ntTerminate
  ThreadPool = object
    status: NThreadStatus
    # Number of Threads
    current, n: int
    # Atomic Working
    working: Atomic[int]
    # Thread Mutex
    lockQueue: Lock
    # Thread Conditions
    waitQueue: Cond
    waitCount: Cond
    # Task Ring Index
    threads: seq[NThread]
    lanes: seq[NThreadLane]
  NThreadPool* = ptr ThreadPool

# -------------------------------
# Thread Pool Buffer Manipulation
# -------------------------------

proc `[]`(list: NThreadRing, i: int): NThreadTask =
  result = list.buffer[i and list.m]

proc `[]=`(list: var NThreadRing, i: int, data: NThreadTask) =
  list.buffer[i and list.m] = data

proc create(list: var NThreadRing) =
  let result = cast[NThreadRing](
    allocShared(ThreadRing.sizeof + 32 * NThreadTask.sizeof))
  # No Previous
  result.prev = nil
  # Set List Size
  result.size = 32
  result.m = 32 - 1
  # Replace Atomic
  list = result

proc expand(list: NThreadRing, top, bottom: int): NThreadRing =
  let size = list.size * 2
  # Allocate New Thread List
  result = cast[NThreadRing](
    allocShared(ThreadRing.sizeof + size * NThreadTask.sizeof))
  # Set New Size
  result.size = size
  result.m = size - 1
  # Dealloc Previous of Previous
  if not isNil(list.prev):
    deallocShared(list.prev)
  # Set Previous List
  result.prev = list
  # Copy Buffer Elements
  for i in top ..< bottom:
    result[i] = list[i]

proc destroy(list: NThreadRing) =
  # Check if Has Previous
  if not isNil(list.prev):
    deallocShared(list.prev)
  # Dealloc List
  deallocShared(list)

# -------------------------
# Thread Pool Queue/Dequeue
# -------------------------

proc push(lane: var NThreadLane, task: NThreadTask) =
  withLock(lane.mtx):
    let 
      top = lane.top
      bottom = lane.bottom
    var ring = lane.ring
    # Expand Lane Ring Buffer
    if (bottom - top) >= ring.size:
      ring = ring.expand(top, bottom)
      lane.ring = ring
    # Enqueue New Task
    ring[bottom] = task
    # Increment Bottom
    inc(lane.bottom)

proc push(pool: NThreadPool, fn: NThreadProc, data: pointer) =
  var task: NThreadTask
  # Initialize Task Values
  task.fn = fn
  task.data = data
  # Get Current Thread ID
  let 
    core = pool.current
    count = pool.n
  # Increment Work Count
  atomicInc(pool.working)
  # Push Current Lane
  pool.lanes[core].push(task)
  # Step Current Core
  pool.current = (core + 1) mod count

proc pull(lane: ptr NThreadLane, task: var NThreadTask): bool =
  withLock(lane.mtx):
    let 
      top = lane.top - 1
      bottom = lane.bottom - 1
    # Try Get Task
    if bottom != top:
      task = lane.ring[bottom]
      # Decrement Bottom
      lane.bottom = bottom
      # Return True
      result = true

proc steal(lane: var NThreadLane, task: var NThreadTask): bool =
  withLock(lane.mtx):
    let 
      top = lane.top
      bottom = lane.bottom
    # Try Get Task
    if top != bottom:
      task = lane.ring[top]
      # Increment Head
      inc(lane.top)
      # Return True
      result = true

proc steal(pool: NThreadPool, task: var NThreadTask): bool =
  # Try Steal One Task from Other Lanes
  for lane in mitems(pool.lanes):
      result = lane.steal(task)
      # Task Found
      if result: break

# ----------------------
# Main Thread Task Procs
# ----------------------

proc threading(lane: ptr NThreadLane) =
  let pool = lane.pool
  var task: NThreadTask
  # Main Loop
  while true:
    case pool.status
    of ntWorking:
      if lane.pull(task) or pool.steal(task):
        task.fn(task.data)
        # Decrement One Task
        atomicDec(pool.working)
      else: cpuRelax()
    of ntSleep:
      withLock(pool.lockQueue):
        # Ensure We Need Sleep
        if pool.status == ntSleep:
          wait(pool.waitQueue, pool.lockQueue)
    of ntTerminate: break

# ------------------------------------
# Thread Pool Fundamental Manipulation
# ------------------------------------

proc start*(pool: NThreadPool) =
  pool.status = ntWorking
  # Wake up each thread
  withLock(pool.lockQueue):
    for core in 0 ..< pool.n:
      signal(pool.waitQueue)

proc spawn*[T: object](pool: NThreadPool, fn: NThreadGenericProc[T], data: ptr T) {.inline.} =
  when supportsCopyMem(T):
    # Bypass GC Safe Check
    var p: NThreadProc
    cast[ptr uint](unsafeAddr p)[] = 
      cast[uint](fn)
    push(pool, p, data)
  else: {.error: "attempted spawn proc with a gc'd type".}

proc sync*(pool: NThreadPool) =
  while pool.working.load() > 0:
    cpuRelax() # Yield Processor

proc stop*(pool: NThreadPool) =
  pool.status = ntSleep

# -----------------------
# Thread Pool Constructor
# -----------------------

proc newThreadPool*(n: int): NThreadPool =
  assert(n > 0, "invalid thread number")
  # - Allocate Syncronization
  result = create(ThreadPool)
  # Allocate Syncronization
  initLock(result.lockQueue)
  initCond(result.waitQueue)
  initCond(result.waitCount)
  # Initialize Status
  result.status = ntSleep
  # - Thread Count
  result.n = n
  # - Create Each Thread
  setLen(result.lanes, n)
  setLen(result.threads, n)
  for core, thr in mpairs(result.threads):
    let lane = addr result.lanes[core]
    # Set Lane Current Pool
    lane.pool = result
    # Initialize Lane Buffers
    lane.ring.create()
    lane.mtx.initLock()
    # Create Thread and Pin to Core
    thr.createThread(threading, lane)
    thr.pinToCpu(core)

# ----------------------
# Thread Pool Destructor
# ----------------------

proc destroy*(pool: NThreadPool) =
  if pool.status == ntWorking:
    pool.sync() # Wait
  elif pool.status == ntSleep:
    withLock(pool.lockQueue):
      pool.working.store(pool.n)
      # Send Wait Signal
      for n in 0 ..< pool.n:
        signal(pool.waitQueue)
  # Brake Main Loops
  pool.status = ntTerminate
  # Join Each Thread
  for thr in mitems(pool.threads):
    thr.joinThread()
  # Destroy Lane Data
  for lane in mitems(pool.lanes):
    lane.ring.destroy()
    lane.mtx.deinitLock()
  # Deinitialize Syncronization
  deinitLock(pool.lockQueue)
  deinitCond(pool.waitQueue)
  deinitCond(pool.waitCount)
  # Deallocate Thread Seq
  `=destroy`(pool.threads)
  `=destroy`(pool.lanes)
  # Dealloc Thread Pool
  dealloc(pool)
