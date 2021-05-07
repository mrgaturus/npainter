from typetraits import
  supportsCopyMem
# Thread Sync
import locks

type
  Semaphore = object
    lck: Lock
    cnd: Cond
    # Boolean
    v: int
  # -- Thread Task
  NThread = 
    Thread[NThreadPool]
  NThreadProc = # Guaranted To Be Safe by Macro
    proc (data: pointer) {.nimcall, gcsafe.}
  NThreadGenericProc[T] =
    proc (data: ptr T) {.nimcall.}
  ThreadTask = object
    prev: NThreadTask
    # Thread Task Data
    fn: NThreadProc
    data, dummy: pointer
  NThreadTask = ptr ThreadTask
  # -- Thread Pool
  ThreadPool = object
    threads: seq[NThread]
    taskSem: Semaphore
    # Count and Brake
    tasking: int
    working: int
    running: bool
    # Syncronization
    lockQueue: Lock
    lockCount: Lock
    waitCount: Cond
    # Singly Linked List
    front, back: NThreadTask
  NThreadPool* = ptr ThreadPool

# --------------------------
# Mutex/Cond SEMAPHORE PROCS
# --------------------------

proc initSemaphore(sem: var Semaphore, v: int) =
  assert(v >= 0, "negative semaphore")
  # Initialize Semaphore
  initLock(sem.lck)
  initCond(sem.cnd)
  sem.v = v

proc deinitSemaphore(sem: var Semaphore) =
  deinitLock(sem.lck)
  deinitCond(sem.cnd)

proc post(sem: var Semaphore) =
  withLock(sem.lck):
    inc(sem.v)
    signal(sem.cnd)

proc wait(sem: var Semaphore) =
  withLock(sem.lck):
    while sem.v <= 0:
      wait(sem.cnd, sem.lck)
    dec(sem.v) # Decrease

# -------------------------
# Thread Pool Queue/Dequeue
# -------------------------

proc push(pool: NThreadPool, task: NThreadTask) =
  withLock(pool.lockQueue):
    task.prev = nil
    if pool.tasking > 0:
      pool.back.prev = task
      pool.back = task
    else:
      pool.front = task
      pool.back = task
    # Increment Task Count
    inc(pool.tasking)
    # Notify Semaphore
    post(pool.taskSem)

proc push(pool: NThreadPool, fn: NThreadProc, data: pointer) =
  let task = createShared(ThreadTask)
  # Initialize Task Values
  task.fn = fn
  task.data = data
  # Add Task To Queue
  pool.push(task)

proc pull(pool: NThreadPool): NThreadTask =
  withLock(pool.lockQueue):
    result = pool.front
    case pool.tasking:
    of 0: discard
    of 1: # One Task
      pool.front = nil
      pool.back = nil
      pool.tasking = 0
    else: # Many Tasks
      pool.front = result.prev
      dec(pool.tasking)

# ----------------------
# Main Thread Task Procs
# ----------------------

proc threading(pool: NThreadPool) =
  # Decrement Initialization
  withLock(pool.lockCount):
    dec(pool.working)
    if pool.working == 0:
      signal(pool.waitCount)
  # Main Loop
  while true:
    # Wait Semaphore
    wait(pool.taskSem)
    # Check Loop Brake
    if not pool.running: 
      break
    # Increment Working
    withLock(pool.lockCount):
      inc(pool.working)
    # Dequeue Pool
    let task = pool.pull()
    if not isNil(task):
      # Execute Task
      task.fn(task.data)
      deallocShared(task)
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
    while pool.tasking > 0 or pool.working > 0:
      wait(pool.waitCount, pool.lockCount)

# -----------------------
# Thread Pool Constructor
# -----------------------

proc newThreadPool*(n: int): NThreadPool =
  assert(n > 0, "invalid thread number")
  # - Allocate Syncronization
  result = create(ThreadPool)
  # Allocate Idle Semaphore
  initSemaphore(result.taskSem, 0)
  # Allocate Syncronization
  initLock(result.lockQueue)
  initLock(result.lockCount)
  initCond(result.waitCount)
  # - Create Each Thread
  setLen(result.threads, n)
  result.working = n
  result.running = true
  for thr in mitems(result.threads):
    thr.createThread(threading, result)
  # Wait Until Threads Are Idle
  withLock(result.lockCount):
    while result.working > 0:
      wait(result.waitCount, result.lockCount)

# ----------------------
# Thread Pool Destructor
# ----------------------

proc destroy*(pool: NThreadPool) =
  pool.sync()
  # Brake Main Loops
  pool.running = false
  # Wake Up Each Thread
  for i in 0..<len(pool.threads):
    post(pool.taskSem)
  # Join Each Thread
  for thr in mitems(pool.threads):
    thr.joinThread()
  # Deinitialize Idle Semaphore
  deinitSemaphore(pool.taskSem)
  # Deinitialize Syncronization
  deinitLock(pool.lockQueue)
  deinitLock(pool.lockCount)
  deinitCond(pool.waitCount)
  # Deallocate Thread Seq
  `=destroy`(pool.threads)
  # Dealloc Thread Pool
  dealloc(pool)
