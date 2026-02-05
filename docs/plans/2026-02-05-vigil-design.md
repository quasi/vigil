# vigil - Internal Process Observability Framework

**Date:** 2026-02-05
**Status:** Design
**Depends on:** trivial-rrd

## Overview

vigil is an observability framework for long-running Common Lisp processes. It enables runtime self-awareness: a Lisp image monitoring its own health and adapting behavior accordingly.

Unlike external observability (Prometheus, Grafana), vigil operates entirely within the process. Metrics flow from agents to supervisor to decisions - no external I/O on the hot path.

## Motivation

Two production scenarios drove this design:

**Thread Health Monitoring:** Multi-threaded application with threads that hang on external input or I/O. Need to detect hung threads for cleanup.

**Adaptive Routing:** Multiple payment gateways with round-robin routing. One gateway slows down. Need to detect degradation and reduce its traffic share until recovery.

Both require:
- Fixed memory budget (can't grow unbounded)
- Recent data primacy (old data decays in value)
- Actionable output (metrics drive decisions)
- Internal introspection (no external dependencies)

## Scoping Model

vigil supports three metric scopes:

### Global Scope

One store for the entire Lisp image.

```
┌─────────────────────────────────────────┐
│           LISP IMAGE                    │
│  ┌─────────────────────────────────┐    │
│  │      GLOBAL METRICS STORE       │    │
│  └─────────────────────────────────┘    │
│        ↑         ↑         ↑            │
│     Thread1   Thread2   Thread3         │
└─────────────────────────────────────────┘
```

**Use cases:**
- Total request throughput
- Image-wide GC statistics
- Shared resource utilization (connection pools)

### Thread-Local Scope

Each thread has its own isolated store.

**Use cases:**
- Per-thread heartbeat (hung thread detection)
- Per-thread error count
- Per-thread work queue depth

### Agent Hierarchy Scope

An agent and all its spawned children share a store. Children can override with their own nested store.

```
┌─────────────────────────────────────────────────────────────┐
│                    LISP IMAGE                               │
│  ┌─────────────────────────────────┐                        │
│  │  BOOKING-GHOST (Agent)          │    ┌────────────────┐  │
│  │  ┌───────────────────────────┐  │    │  OTHER-AGENT   │  │
│  │  │   SHARED METRICS STORE    │  │    │  ┌──────────┐  │  │
│  │  └───────────────────────────┘  │    │  │  STORE   │  │  │
│  │       ↑        ↑        ↑       │    │  └──────────┘  │  │
│  │    Agent    Worker1  Worker2    │    └────────────────┘  │
│  │   (main)   (spawned) (spawned)  │                        │
│  └─────────────────────────────────┘                        │
└─────────────────────────────────────────────────────────────┘
```

**Use cases:**
- Agent tracks its throughput (including workers)
- Agent-level error budget
- Resource accounting per agent

This uses dynamic binding - exactly like special variables in Lisp. Children inherit the parent's `*metrics*` binding unless they explicitly override with `with-store`.

## Architecture

### Layering

```
┌─────────────────────────────────────┐
│  vigil (framework)                  │
│  - registry, scoping, queries       │
│  - spawn, with-store                │
│  - archiver                         │
├─────────────────────────────────────┤
│  trivial-rrd (primitive)            │
│  - rrd-archive, circular buffers    │
│  - memory-backend, sqlite-backend   │
│  - protocol functions               │
└─────────────────────────────────────┘
```

trivial-rrd provides the data structure (circular buffers, RRD protocol). vigil adds policy (scoping, registry, thread safety, queries).

### Store Structure

```lisp
(defclass store ()
  ((name :initarg :name :reader store-name)
   (lock :initform (bt:make-lock) :reader store-lock)
   (parent :initarg :parent :initform nil :reader store-parent)
   (created-at :initform (get-universal-time) :reader store-created-at)
   (backend :initform (make-instance 'rrd:memory-backend) :reader store-backend)))
```

Each store wraps a trivial-rrd memory-backend with:
- **name:** Identifier for registry lookup
- **lock:** Coarse-grained lock for thread safety
- **parent:** Optional parent store (for hierarchy tracking)
- **created-at:** Creation timestamp

### Registry

Global registry maps store names to store objects.

```lisp
(defvar *store-registry* (make-hash-table :test 'equal))
(defvar *registry-lock* (bt:make-lock))
```

Stores register on creation, unregister on cleanup. The registry enables supervisor queries across all active stores.

### Thread Safety

Coarse lock per store. All writes to the same store serialize.

Rationale:
- Writes are O(1) - lock held briefly
- Agent hierarchy scopes reduce writers per store
- Simple to implement and reason about
- Can optimize to fine-grained if profiling shows contention

### Special Variables

```lisp
(defvar *global-metrics* nil
  "Image-wide metrics store. Initialized at load time.")

(defvar *metrics* nil
  "Current scope's metrics store. Dynamically bound per agent.")
```

## API

### Recording

```lisp
;; Explicit store argument
(record store metric value &key timestamp)

;; Implicit - uses *metrics*
(record! metric value &key timestamp)

;; Implicit - uses *global-metrics*
(record-global! metric value &key timestamp)
```

### Querying

```lisp
;; Point queries
(last-value store metric)      ; most recent value
(last-update store metric)     ; most recent timestamp

;; Time window aggregates
(aggregate store metric
           :window seconds     ; seconds back from now
           :function :average) ; :min :max :sum :count

;; Threshold check
(exceeds? store metric threshold
          :window 300
          :function :average)
```

### Supervision

```lisp
;; Registry queries
(list-stores)                  ; all registered store names
(get-store name)               ; store by name, or NIL
(find-stores predicate)        ; filter by condition
(map-stores function)          ; apply across all stores
```

### Lifecycle

```lisp
;; Scoped store binding with automatic cleanup
(with-store (name &key parent)
  body...)

;; Thread spawn with binding inheritance
(spawn function &key name)

;; Initialize global store (call once at startup)
(initialize-global-metrics &key step retention)
```

### Archiving

```lisp
;; Start background archiver (SQLite dump)
(start-archiver &key backend interval)

;; Manual snapshot
(archive-store name &key backend)
```

## Usage Examples

### Thread Health Monitoring

```lisp
;; Each worker heartbeats periodically
(defun worker-loop ()
  (loop
    (record! "heartbeat" (get-universal-time))
    (process-next-job)
    (sleep 1)))

;; Supervisor detects hung workers
(defun find-hung-workers (timeout-seconds)
  (let ((cutoff (- (get-universal-time) timeout-seconds)))
    (find-stores
      (lambda (store)
        (let ((last-hb (last-value store "heartbeat")))
          (or (null last-hb)
              (< last-hb cutoff)))))))
```

### Payment Gateway Adaptive Routing

```lisp
;; Record response times
(defun call-gateway (gateway-id request)
  (let ((start (get-internal-real-time)))
    (prog1 (send-to-gateway gateway-id request)
      (let ((elapsed-ms (/ (- (get-internal-real-time) start)
                           (/ internal-time-units-per-second 1000))))
        (record! (format nil "gateway.~a.response-time" gateway-id)
                 elapsed-ms)))))

;; Compute routing weights (inverse of avg response time)
(defun compute-weights (gateway-ids)
  (let ((scores (mapcar
                  (lambda (gw)
                    (or (aggregate *metrics*
                                   (format nil "gateway.~a.response-time" gw)
                                   :window 600
                                   :function :average)
                        1000.0)) ; default for no data
                  gateway-ids)))
    (normalize-weights (mapcar #'/ (make-list (length scores) :initial-element 1.0)
                                   scores))))
```

### Agent with Workers

```lisp
(defun start-booking-ghost ()
  (with-store ("booking-ghost")
    (record! "started" 1)

    ;; Spawn workers - they inherit *metrics*
    (dotimes (i 4)
      (spawn #'booking-worker :name (format nil "worker-~d" i)))

    ;; Main agent loop
    (supervisor-loop)))

(defun booking-worker ()
  ;; Writes go to booking-ghost's store
  (loop
    (record! "heartbeat" (get-universal-time))
    (let ((booking (get-next-booking)))
      (process-booking booking)
      (record! "bookings.processed" 1))))
```

## SQLite Archiver

SQLite is not on the hot path. It serves as a background dump for:
- Post-mortem analysis after incidents
- Historical trending beyond memory retention
- Export for external tools

```
memory store → periodic dump → SQLite → offline analysis
                    ↑
              (async, background)
```

Agents never wait on disk I/O. The archiver runs in a dedicated thread, periodically snapshotting stores.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Lock granularity | Per-store (coarse) | Simple, writes are O(1), optimize later if needed |
| Scope inheritance | Dynamic binding | Natural Lisp idiom, matches `let` semantics |
| Query model | Pull-based | Simple foundation, push can be built on top |
| Registry | Flat with naming convention | Hierarchy via names like "agent/worker-1" |
| SQLite role | Background archiver only | Hot path stays in-memory |

## Future Considerations

Not in scope for v1, but potential extensions:
- Fine-grained locking if contention becomes an issue
- Lock-free circular buffers (SBCL-specific)
- Push-based alerts (threshold callbacks)
- Multi-image aggregation (external coordinator)

## Dependencies

- **trivial-rrd:** RRD data structures and protocol
- **bordeaux-threads:** Portable threading primitives
- **telos:** Intent introspection (optional, for consistency with trivial-rrd)
