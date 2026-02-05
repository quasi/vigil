# API Reference

Complete reference for vigil functions and macros.

## Store Class

### `store`

Container for metrics. Wraps a trivial-rrd memory-backend with thread-safe access.

**Slots:**

| Slot | Accessor | Type | Description |
|------|----------|------|-------------|
| name | `store-name` | string | Unique identifier |
| lock | `store-lock` | lock | Coarse-grained mutex |
| parent | `store-parent` | store or nil | Parent in hierarchy |
| created-at | `store-created-at` | integer | Universal time of creation |
| backend | `store-backend` | rrd:memory-backend | Underlying storage |

### `make-store`

```lisp
(make-store name &key parent) => store
```

Create a new store. Does not register it - use `with-store` for automatic registration.

**Arguments:**
- `name` - String identifier for the store
- `parent` - Optional parent store for hierarchy tracking

**Example:**
```lisp
(let ((store (make-store "manual-store")))
  (record store "metric" 42))
```

---

## Special Variables

### `*global-metrics*`

```lisp
*global-metrics* => store or nil
```

Image-wide metrics store. Initialize with `initialize-global-metrics` before use.

### `*metrics*`

```lisp
*metrics* => store or nil
```

Current scope's metrics store. Dynamically bound by `with-store`.

---

## Scoping

### `initialize-global-metrics`

```lisp
(initialize-global-metrics &key (step 10) (retention 3600)) => store
```

Initialize the global metrics store. Call once at application startup.

**Arguments:**
- `step` - Default step in seconds for metrics (default: 10)
- `retention` - Default retention in seconds (default: 3600 = 1 hour)

**Example:**
```lisp
(initialize-global-metrics :step 1 :retention 7200)
```

### `with-store`

```lisp
(with-store (name &key parent) &body body) => result
```

Bind `*metrics*` to a new store for the duration of body. The store is automatically registered on entry and unregistered on exit.

**Arguments:**
- `name` - String identifier for the store
- `parent` - Optional parent store. If not specified and `*metrics*` is bound, uses current `*metrics*` as parent.

**Example:**
```lisp
(with-store ("my-component")
  (record! "started" 1)
  (do-work)
  (record! "completed" 1))
```

**Nesting:**
```lisp
(with-store ("outer")
  (record! "outer-metric" 1)
  (with-store ("inner" :parent *metrics*)
    (record! "inner-metric" 2)))
```

### `spawn`

```lisp
(spawn function &key name) => thread
```

Spawn a thread that inherits the current `*metrics*` and `*global-metrics*` bindings.

**Arguments:**
- `function` - Zero-argument function to run in the thread
- `name` - Optional thread name (default: "vigil-worker")

**Example:**
```lisp
(with-store ("agent")
  ;; Workers inherit agent's store
  (spawn #'worker-function :name "worker-1")
  (spawn #'worker-function :name "worker-2"))
```

---

## Recording

### `record`

```lisp
(record store metric-name value
        &key (timestamp (get-universal-time))
             (step *default-step*)
             (retention *default-retention*)
             (cf :average))
  => value
```

Record a value to a metric in the given store. Thread-safe. Creates the metric if it doesn't exist.

**Arguments:**
- `store` - Target store
- `metric-name` - String name of the metric
- `value` - Numeric value to record
- `timestamp` - Unix timestamp (default: current time)
- `step` - Data point interval in seconds (default: 10)
- `retention` - How long to keep data in seconds (default: 3600)
- `cf` - Consolidation function: `:average`, `:min`, `:max`, `:last`

**Example:**
```lisp
(record my-store "response-time" 150.0)
(record my-store "temperature" 22.5 :step 60 :retention 86400)
```

### `record!`

```lisp
(record! metric-name value
         &key timestamp step retention cf)
  => value
```

Record to current `*metrics*`. Signals `no-active-store` if `*metrics*` is nil.

**Example:**
```lisp
(with-store ("my-agent")
  (record! "heartbeat" (get-universal-time))
  (record! "jobs-done" 1))
```

### `record-global!`

```lisp
(record-global! metric-name value
                &key timestamp step retention cf)
  => value
```

Record to `*global-metrics*`. Signals `no-active-store` if `*global-metrics*` is nil.

**Example:**
```lisp
(record-global! "total-requests" 1)
(record-global! "gc-time-ms" 45.2)
```

### `ensure-metric`

```lisp
(ensure-metric store metric-name
               &key (step *default-step*)
                    (retention *default-retention*)
                    (cf :average))
  => nil
```

Ensure a metric exists in the store, creating it if necessary. Called automatically by `record`.

---

## Querying

### `last-value`

```lisp
(last-value store metric-name) => value or nil
```

Return the most recently recorded value for the metric, or nil if no data exists.

**Example:**
```lisp
(last-value my-store "temperature")
;; => 22.5
```

### `last-update`

```lisp
(last-update store metric-name) => timestamp or nil
```

Return the timestamp of the most recent update, or nil if no data exists.

**Example:**
```lisp
(last-update my-store "heartbeat")
;; => 3948271234
```

### `aggregate`

```lisp
(aggregate store metric-name
           &key (window 300) (function :average))
  => value or nil
```

Compute an aggregate over a time window.

**Arguments:**
- `store` - Store to query
- `metric-name` - Metric to aggregate
- `window` - Seconds back from now (default: 300 = 5 minutes)
- `function` - Aggregation function:
  - `:average` - Mean of values
  - `:min` - Minimum value
  - `:max` - Maximum value
  - `:sum` - Sum of values
  - `:count` - Number of values

**Example:**
```lisp
;; Average response time over last 5 minutes
(aggregate my-store "response-ms" :window 300 :function :average)

;; Max temperature over last hour
(aggregate my-store "temperature" :window 3600 :function :max)

;; Total requests in last minute
(aggregate my-store "requests" :window 60 :function :count)
```

### `exceeds?`

```lisp
(exceeds? store metric-name threshold
          &key (window 300) (function :average))
  => boolean
```

Return T if the aggregate exceeds the threshold.

**Example:**
```lisp
;; Check if average response time exceeds 500ms
(exceeds? my-store "response-ms" 500 :window 60 :function :average)

;; Check if error count exceeds 10 in last minute
(exceeds? my-store "errors" 10 :window 60 :function :count)
```

---

## Registry

### `list-stores`

```lisp
(list-stores) => list of store names
```

Return names of all registered stores.

**Example:**
```lisp
(list-stores)
;; => ("global" "worker-0" "worker-1" "agent-1")
```

### `get-store`

```lisp
(get-store name) => store or nil
```

Return the store with the given name, or nil if not found.

**Example:**
```lisp
(get-store "worker-0")
;; => #<STORE "worker-0">
```

### `find-stores`

```lisp
(find-stores predicate) => list of stores
```

Return all stores for which predicate returns true.

**Arguments:**
- `predicate` - Function taking a store, returning generalized boolean

**Example:**
```lisp
;; Find all worker stores
(find-stores (lambda (s) (search "worker" (store-name s))))

;; Find stores with stale heartbeats
(find-stores
  (lambda (s)
    (let ((hb (last-value s "heartbeat")))
      (and hb (< hb (- (get-universal-time) 30))))))
```

### `map-stores`

```lisp
(map-stores function) => list of results
```

Apply function to each registered store and collect results.

**Example:**
```lisp
;; Get heartbeat status for all stores
(map-stores
  (lambda (s)
    (list (store-name s)
          (last-value s "heartbeat"))))
```

---

## Archiver

Available after loading `vigil/archiver`.

### `start-archiver`

```lisp
(start-archiver &key (db-path "/tmp/vigil-archive.db")
                     (interval 60))
  => t
```

Start the background archiver thread.

**Arguments:**
- `db-path` - SQLite database file path
- `interval` - Seconds between archive runs (default: 60)

**Example:**
```lisp
(start-archiver :db-path "/var/log/app-metrics.db"
                :interval 300)
```

### `stop-archiver`

```lisp
(stop-archiver &key (wait t)) => t or nil
```

Stop the background archiver thread.

**Arguments:**
- `wait` - If true, block until thread exits (default: t)

**Example:**
```lisp
(stop-archiver :wait t)
```

### `archiver-running-p`

```lisp
(archiver-running-p) => boolean
```

Return T if the archiver is currently running.

### `archive-store`

```lisp
(archive-store store &key backend) => t
```

Archive a single store to SQLite. If backend is not provided, uses the running archiver's backend.

**Arguments:**
- `store` - Store to archive
- `backend` - Optional SQLite backend

### `archive-all-stores`

```lisp
(archive-all-stores &key backend) => t
```

Archive all registered stores to SQLite.

---

## Conditions

### `vigil-error`

Base condition for all vigil errors.

### `store-not-found`

Signaled when a requested store doesn't exist in the registry.

**Slots:**
- `store-name` - Name of the missing store

### `no-active-store`

Signaled when `record!` or `record-global!` is called with unbound `*metrics*` or `*global-metrics*`.

---

## Parameters

### `*default-step*`

```lisp
*default-step* => 10
```

Default step (data point interval) in seconds for auto-created metrics.

### `*default-retention*`

```lisp
*default-retention* => 3600
```

Default retention period in seconds for auto-created metrics (1 hour).
