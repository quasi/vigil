# vigil

Internal process observability for Common Lisp.

**What it does:** Lets your Lisp process monitor itself. Detect hung threads. Route traffic away from slow backends. Track agent health. All in-memory, no external dependencies.

**Why it exists:** External observability (Prometheus, Grafana) adds I/O to your hot path and requires external infrastructure. vigil operates entirely within your process - metrics flow from producers to consumers to decisions without leaving memory.

## Quick Example

```lisp
;; Worker heartbeats every second
(defun worker-loop ()
  (with-store ("my-worker")
    (loop
      (record! "heartbeat" (get-universal-time))
      (do-work)
      (sleep 1))))

;; Supervisor finds workers that stopped heartbeating
(defun find-hung-workers ()
  (let ((cutoff (- (get-universal-time) 30)))
    (find-stores
      (lambda (store)
        (let ((last-hb (last-value store "heartbeat")))
          (or (null last-hb) (< last-hb cutoff)))))))
```

## Installation

vigil is not yet in Quicklisp. Clone to `~/quicklisp/local-projects/`:

```bash
cd ~/quicklisp/local-projects/
git clone https://github.com/quasilabs/vigil.git
```

Then load:

```lisp
(ql:quickload :vigil)
```

For SQLite archiving (optional):

```lisp
(ql:quickload :vigil/archiver)
```

## Documentation

- **[Quickstart](docs/quickstart.md)** - Working code in 5 minutes
- **[Use Cases](docs/tutorials/use-cases.md)** - Thread health, adaptive routing, agent hierarchies
- **[API Reference](docs/reference.md)** - Complete function reference

## Core Concepts

**Store:** A container for metrics. Each store wraps a fixed-memory circular buffer (via trivial-rrd). Thread-safe.

**Scopes:** Three ways to organize metrics:
- `*global-metrics*` - image-wide (total requests, GC stats)
- `*metrics*` via `with-store` - per-agent or per-component
- Hierarchical - agents share stores with spawned workers

**Recording:** Write values with timestamps. Metrics auto-create on first write.

**Querying:** Pull current values, compute aggregates over time windows, check thresholds.

## Requirements

- SBCL (tested), should work on other implementations
- trivial-rrd
- bordeaux-threads

## License

MIT
