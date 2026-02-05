(in-package #:vigil)

(deffeature vigil-core
  :purpose "Internal process observability for Lisp images"
  :goals ((:runtime-awareness "Enable processes to monitor their own health")
          (:fixed-memory "Bounded memory via RRD circular buffers")
          (:thread-safe "Safe concurrent access from multiple threads")
          (:actionable "Metrics drive runtime decisions"))
  :constraints ((:in-process "No external I/O on hot path")
                (:pull-based "Supervisor polls, no push callbacks"))
  :failure-modes ((:lock-contention "High writer count may cause contention")
                  (:stale-data "Infrequent queries may miss transient spikes")))

(deffeature vigil-store
  :purpose "Thread-safe wrapper around trivial-rrd memory-backend"
  :goals ((:isolation "Each store has independent metrics")
          (:locking "Coarse lock serializes all writes to a store"))
  :constraints ((:single-backend "One memory-backend per store")))

(deffeature vigil-registry
  :purpose "Global registry of active stores for supervisor queries"
  :goals ((:discovery "Find all active stores")
          (:cleanup "Automatic unregistration on scope exit"))
  :constraints ((:global-lock "Registry modifications serialize")))

(deffeature vigil-scoping
  :purpose "Dynamic binding of metrics stores to threads"
  :goals ((:inheritance "Spawned threads inherit parent's store")
          (:override "Children can create nested scopes"))
  :constraints ((:special-variables "Uses CL dynamic binding")))
