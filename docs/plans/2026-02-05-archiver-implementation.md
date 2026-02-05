# SQLite Archiver Implementation Plan

**Goal:** Add background archiver that periodically dumps store metrics to SQLite for offline analysis.

**Architecture:** Dedicated thread wakes periodically, iterates all registered stores, copies their metrics to a shared sqlite-backend. Manual archive functions also available.

---

## Task 1: Update System Definition

Add optional archiver subsystem that depends on trivial-rrd/sqlite.

**Files:** `vigil.asd`

---

## Task 2: Archiver Implementation

**Files:**
- Create: `src/archiver.lisp`
- Create: `tests/archiver-tests.lisp`

**Features:**
- `*archiver-thread*` - background thread reference
- `*archiver-running*` - control flag
- `*archiver-backend*` - shared sqlite-backend
- `start-archiver` - start background thread
- `stop-archiver` - stop background thread
- `archive-store` - manual archive one store
- `archive-all-stores` - manual archive all stores

**Archive logic:**
1. Get all metrics from store's memory-backend via `rrd-list-metrics`
2. For each metric, get info via `rrd-info`
3. Create metric in sqlite-backend if not exists
4. Fetch recent data from memory-backend
5. Update sqlite-backend with that data
6. Flush sqlite-backend

---

## Task 3: Tests

- Test manual archive of single store
- Test start/stop archiver thread
- Test archiver doesn't block hot path
