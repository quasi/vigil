# CLAUDE.md

This file provides guidance to Claude Code when working with the vigil project.

## Project Overview

vigil is an internal process observability framework for Common Lisp. It enables runtime self-awareness: a Lisp image monitoring its own health and adapting behavior accordingly.

Built on top of trivial-rrd, vigil adds:
- Scoped metrics (global, thread-local, agent hierarchy)
- Thread-safe stores with coarse locking
- Global registry for store discovery
- Convenience API for recording and querying
- Background archiver for SQLite dumps

## Design Document

See `docs/plans/2026-02-05-vigil-design.md` for the full design.

## Dependencies

- **trivial-rrd:** RRD data structures (circular buffers, memory/sqlite backends)
- **bordeaux-threads:** Portable threading
- **telos:** Intent introspection (optional)

## Development

This project follows TDD. See the global CLAUDE.md for workflow details.

```lisp
;; Load system
(ql:quickload :vigil)

;; Run tests
(asdf:test-system :vigil)
```

## Key Concepts

| Concept | Description |
|---------|-------------|
| Store | Named, locked wrapper around trivial-rrd memory-backend |
| Registry | Global map of active stores |
| `*metrics*` | Dynamically bound current-scope store |
| `*global-metrics*` | Image-wide store |
| `with-store` | Scoped binding with auto-cleanup |
| `spawn` | Thread creation with binding inheritance |
