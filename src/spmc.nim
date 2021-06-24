from typetraits import
  supportsCopyMem
# Thread Sync
import locks

type
  NThread = 
    Thread[NThreadPool]
  NThreadProc = # Guaranted To Be Safe by Macro
    proc (data: pointer) {.nimcall, gcsafe.}
  NThreadGenericProc[T] =
    proc (data: ptr T) {.nimcall.}
  NThreadTask = object
    fn: NThreadProc
    data: pointer
  # -- Thread Pool
  ThreadPool = object
    threads: seq[NThread]
    # Count and Brake
    working: int
    running: bool
    # Thread Mutexes
    lockQueue: Lock
    lockCount: Lock
    # Thread Conditions
    waitQueue: Cond
    waitCount: Cond
    # Task Ring Index
    tail, head: uint
    # Task Ring Buffer
    ring: array[256, NThreadTask]
  NThreadPool* = ptr ThreadPool

# -------------------------
# Thread Pool Queue/Dequeue
# -------------------------

proc push(pool: NThreadPool, fn: NThreadProc, data: pointer) =
  var task: NThreadTask
  # Initialize Task Values
  task.fn = fn
  task.data = data
  # Add Task To Queue
  withLock(pool.lockQueue):
    # Wait for free space
    while (pool.tail - pool.head) >= 256:
      wait(pool.waitQueue, pool.lockQueue)
    # Enqueue New Task To Ring Buffer
    pool.ring[pool.tail and 255] = task
    # Increment Tail
    inc(pool.tail)
    # Increment Working
    withLock(pool.lockCount):
      inc(pool.working)
    # Send Wait Signal
    signal(pool.waitQueue)

proc pull(pool: NThreadPool): NThreadTask =
  withLock(pool.lockQueue):
    # Wait if Ring is Empty
    while pool.head == pool.tail:
      wait(pool.waitQueue, pool.lockQueue)
    # Dequeue Task from Ring Buffer
    result = pool.ring[pool.head and 255]
    # Increment Head
    inc(pool.head)
    # Send Wait Signal
    signal(pool.waitQueue)

# ----------------------
# Main Thread Task Procs
# ----------------------

proc threading(pool: NThreadPool) =
  # Main Loop
  while true:
    # Lookup Task
    let task = pool.pull()
    # Check Loop Brake
    if not pool.running: 
      break
    # Execute Task
    task.fn(task.data)
    # Decrement Working
    withLock(pool.lockCount):
      dec(pool.working)
      if pool.working == 0:
        signal(pool.waitCount)

# ------------------------------------
# Thread Pool Fundamental Manipulation
# ------------------------------------

proc spawn*[T: object](pool: NThreadPool, fn: NThreadGenericProc[T], data: ptr T) {.inline.} =
  when supportsCopyMem(T):
    # Bypass GC Safe Check
    var p: NThreadProc
    cast[ptr uint](unsafeAddr p)[] = 
      cast[uint](fn)
    push(pool, p, data)
  else: {.error: "attempted spawn proc with a gc'd type".}

proc sync*(pool: NThreadPool) =
  withLock(pool.lockCount):
    while pool.working > 0:
      wait(pool.waitCount, pool.lockCount)

# -----------------------
# Thread Pool Constructor
# -----------------------

proc newThreadPool*(n: int): NThreadPool =
  assert(n > 0, "invalid thread number")
  # - Allocate Syncronization
  result = create(ThreadPool)
  # Allocate Syncronization
  initLock(result.lockQueue)
  initLock(result.lockCount)
  initCond(result.waitQueue)
  initCond(result.waitCount)
  # Initialize Brake
  result.running = true
  # - Create Each Thread
  setLen(result.threads, n)
  for thr in mitems(result.threads):
    thr.createThread(threading, result)

# ----------------------
# Thread Pool Destructor
# ----------------------

proc destroy*(pool: NThreadPool) =
  pool.sync()
  # Brake Main Loops
  pool.running = false
  # Wake Up Each Thread
  withLock(pool.lockQueue):
    pool.tail = 256
    pool.head = 0
    # Send Wait Signal
    signal(pool.waitQueue)
  # Join Each Thread
  for thr in mitems(pool.threads):
    thr.joinThread()
  # Deinitialize Syncronization
  deinitLock(pool.lockQueue)
  deinitLock(pool.lockCount)
  deinitCond(pool.waitQueue)
  deinitCond(pool.waitCount)
  # Deallocate Thread Seq
  `=destroy`(pool.threads)
  # Dealloc Thread Pool
  dealloc(pool)
