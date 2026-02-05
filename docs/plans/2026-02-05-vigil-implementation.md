# vigil Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement the vigil observability framework for internal Lisp process monitoring.

**Architecture:** vigil wraps trivial-rrd memory-backend with thread-safe stores, a global registry, and dynamic scoping via special variables. Uses telos for intent introspection and cl-test-hardening for property-based tests.

**Tech Stack:** Common Lisp, trivial-rrd, bordeaux-threads, telos, FiveAM, cl-test-hardening

---

## Task 1: Project Setup - ASDF System Definition

**Files:**
- Create: `vigil.asd`
- Create: `src/package.lisp`

**Step 1: Write the system definition**

```lisp
;;; vigil.asd
(defsystem "vigil"
  :description "Internal process observability framework for Common Lisp"
  :author "Abhijit Rao <quasi@quasilabs.in>"
  :license "MIT"
  :version "0.1.0"
  :depends-on ("trivial-rrd" "bordeaux-threads" "telos")
  :serial t
  :components ((:module "src"
                :components ((:file "package")
                             (:file "features")
                             (:file "conditions")
                             (:file "store")
                             (:file "registry")
                             (:file "scoping")
                             (:file "recording")
                             (:file "queries"))))
  :in-order-to ((test-op (test-op "vigil/tests"))))

(defsystem "vigil/tests"
  :description "Tests for vigil"
  :depends-on ("vigil" "fiveam"
               "cl-test-hardening/property"
               "cl-test-hardening/generators")
  :serial t
  :components ((:module "tests"
                :components ((:file "package")
                             (:file "suite")
                             (:file "store-tests")
                             (:file "registry-tests")
                             (:file "scoping-tests")
                             (:file "recording-tests")
                             (:file "queries-tests")
                             (:file "integration-tests"))))
  :perform (test-op (o c)
             (symbol-call :fiveam :run! :vigil-tests)))
```

**Step 2: Write the package definition**

```lisp
;;; src/package.lisp
(defpackage #:vigil
  (:use #:cl #:telos)
  (:local-nicknames (#:rrd #:trivial-rrd)
                    (#:bt #:bordeaux-threads))
  (:export
   ;; Store class and accessors
   #:store
   #:store-name
   #:store-parent
   #:store-created-at

   ;; Registry
   #:list-stores
   #:get-store
   #:find-stores
   #:map-stores

   ;; Scoping
   #:*global-metrics*
   #:*metrics*
   #:with-store
   #:spawn
   #:initialize-global-metrics

   ;; Recording
   #:record
   #:record!
   #:record-global!
   #:ensure-metric

   ;; Queries
   #:last-value
   #:last-update
   #:aggregate
   #:exceeds?

   ;; Conditions
   #:store-not-found
   #:no-active-store
   #:condition-store-name))
```

**Step 3: Commit**

```bash
git add vigil.asd src/package.lisp
git commit -m "Add vigil system definition and package"
```

---

## Task 2: Test Infrastructure

**Files:**
- Create: `tests/package.lisp`
- Create: `tests/suite.lisp`

**Step 1: Write test package**

```lisp
;;; tests/package.lisp
(defpackage #:vigil-tests
  (:use #:cl #:vigil #:fiveam #:th.property)
  (:local-nicknames (#:gen #:th.gen)
                    (#:bt #:bordeaux-threads))
  (:export #:run-tests
           #:vigil-tests))
```

**Step 2: Write test suite**

```lisp
;;; tests/suite.lisp
(in-package #:vigil-tests)

(def-suite vigil-tests
  :description "Main test suite for vigil")

(def-suite store-tests
  :description "Tests for store creation and basic operations"
  :in vigil-tests)

(def-suite registry-tests
  :description "Tests for store registry"
  :in vigil-tests)

(def-suite scoping-tests
  :description "Tests for with-store and dynamic scoping"
  :in vigil-tests)

(def-suite recording-tests
  :description "Tests for record/record!/record-global!"
  :in vigil-tests)

(def-suite queries-tests
  :description "Tests for last-value, aggregate, exceeds?"
  :in vigil-tests)

(def-suite integration-tests
  :description "End-to-end tests with threading"
  :in vigil-tests)

(defun run-tests ()
  "Run all vigil tests."
  (run! 'vigil-tests))
```

**Step 3: Commit**

```bash
git add tests/package.lisp tests/suite.lisp
git commit -m "Add test infrastructure"
```

---

## Task 3: Features and Conditions

**Files:**
- Create: `src/features.lisp`
- Create: `src/conditions.lisp`

**Step 1: Write telos features**

```lisp
;;; src/features.lisp
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
```

**Step 2: Write conditions**

```lisp
;;; src/conditions.lisp
(in-package #:vigil)

(define-condition vigil-error (error)
  ()
  (:documentation "Base condition for vigil errors"))

(define-condition store-not-found (vigil-error)
  ((store-name :initarg :store-name :reader condition-store-name))
  (:report (lambda (c s)
             (format s "Store not found: ~a" (condition-store-name c))))
  (:documentation "Signaled when a store lookup fails"))

(define-condition no-active-store (vigil-error)
  ()
  (:report (lambda (c s)
             (declare (ignore c))
             (format s "No active store: *metrics* is nil")))
  (:documentation "Signaled when record! called without active *metrics*"))

(defintent vigil-error
  :feature vigil-core
  :role "Base condition type"
  :purpose "Enable typed error handling for vigil operations")

(defintent store-not-found
  :feature vigil-registry
  :role "Signal failed store lookup"
  :purpose "Distinguish missing store from other errors")

(defintent no-active-store
  :feature vigil-scoping
  :role "Signal missing dynamic binding"
  :purpose "Catch record! calls outside with-store scope")
```

**Step 3: Commit**

```bash
git add src/features.lisp src/conditions.lisp
git commit -m "Add telos features and conditions"
```

---

## Task 4: Store Class

**Files:**
- Create: `src/store.lisp`
- Create: `tests/store-tests.lisp`

**Step 1: Write failing test for store creation**

```lisp
;;; tests/store-tests.lisp
(in-package #:vigil-tests)

(in-suite store-tests)

(test store-creation
  "A store can be created with a name"
  (let ((store (vigil::make-store "test-store")))
    (is (equal "test-store" (store-name store)))
    (is (not (null (vigil::store-lock store))))
    (is (not (null (vigil::store-backend store))))
    (is (null (store-parent store)))
    (is (integerp (store-created-at store)))))

(test store-with-parent
  "A store can have a parent"
  (let* ((parent (vigil::make-store "parent"))
         (child (vigil::make-store "child" :parent parent)))
    (is (eq parent (store-parent child)))))
```

**Step 2: Run test to verify it fails**

Run: `(asdf:test-system :vigil)`
Expected: FAIL - function make-store not defined

**Step 3: Write store implementation**

```lisp
;;; src/store.lisp
(in-package #:vigil)

(defclass/i store ()
  ((name :initarg :name
         :reader store-name
         :type string
         :documentation "Unique identifier for registry lookup")
   (lock :initform (bt:make-lock "vigil-store")
         :reader store-lock
         :documentation "Coarse-grained lock for thread safety")
   (parent :initarg :parent
           :initform nil
           :reader store-parent
           :type (or null store)
           :documentation "Parent store for hierarchy tracking")
   (created-at :initform (get-universal-time)
               :reader store-created-at
               :type integer
               :documentation "Creation timestamp")
   (backend :initform (make-instance 'rrd:memory-backend)
            :reader store-backend
            :documentation "Underlying trivial-rrd storage"))
  (:feature vigil-store)
  (:role "Thread-safe metrics container")
  (:purpose "Wrap memory-backend with locking and identity"))

(defun/i make-store (name &key parent)
  "Create a new store with the given name."
  (:feature vigil-store)
  (:role "Store constructor")
  (:purpose "Create store instance without registration")
  (make-instance 'store :name name :parent parent))
```

**Step 4: Run test to verify it passes**

Run: `(asdf:test-system :vigil)`
Expected: PASS

**Step 5: Commit**

```bash
git add src/store.lisp tests/store-tests.lisp
git commit -m "Add store class with locking"
```

---

## Task 5: Store Registry

**Files:**
- Create: `src/registry.lisp`
- Create: `tests/registry-tests.lisp`

**Step 1: Write failing tests**

```lisp
;;; tests/registry-tests.lisp
(in-package #:vigil-tests)

(in-suite registry-tests)

(def-fixture clean-registry ()
  (vigil::clear-registry)
  (unwind-protect
      (&body)
    (vigil::clear-registry)))

(test register-and-list
  "Stores can be registered and listed"
  (with-fixture clean-registry ()
    (let ((store (vigil::make-store "test-store")))
      (vigil::register-store store)
      (is (member "test-store" (list-stores) :test #'equal)))))

(test get-store-by-name
  "A registered store can be retrieved by name"
  (with-fixture clean-registry ()
    (let ((store (vigil::make-store "my-store")))
      (vigil::register-store store)
      (is (eq store (get-store "my-store")))
      (is (null (get-store "nonexistent"))))))

(test unregister-store
  "Stores can be unregistered"
  (with-fixture clean-registry ()
    (let ((store (vigil::make-store "temp-store")))
      (vigil::register-store store)
      (is (not (null (get-store "temp-store"))))
      (vigil::unregister-store store)
      (is (null (get-store "temp-store"))))))

(test find-stores-predicate
  "find-stores filters by predicate"
  (with-fixture clean-registry ()
    (vigil::register-store (vigil::make-store "agent-a"))
    (vigil::register-store (vigil::make-store "agent-b"))
    (vigil::register-store (vigil::make-store "worker-1"))
    (let ((agents (find-stores (lambda (s)
                                 (search "agent" (store-name s))))))
      (is (= 2 (length agents))))))

(test map-stores-function
  "map-stores applies function to all stores"
  (with-fixture clean-registry ()
    (vigil::register-store (vigil::make-store "s1"))
    (vigil::register-store (vigil::make-store "s2"))
    (let ((names (map-stores #'store-name)))
      (is (= 2 (length names)))
      (is (member "s1" names :test #'equal))
      (is (member "s2" names :test #'equal)))))
```

**Step 2: Run test to verify it fails**

Run: `(asdf:test-system :vigil)`
Expected: FAIL - functions not defined

**Step 3: Write registry implementation**

```lisp
;;; src/registry.lisp
(in-package #:vigil)

;;; Global registry state

(defvar *store-registry* (make-hash-table :test 'equal)
  "Maps store names to store objects.")

(defvar *registry-lock* (bt:make-lock "vigil-registry")
  "Lock for registry modifications.")

;;; Internal functions

(defun/i clear-registry ()
  "Clear all stores from registry. For testing only."
  (:feature vigil-registry)
  (:role "Test helper")
  (:purpose "Reset registry state between tests")
  (bt:with-lock-held (*registry-lock*)
    (clrhash *store-registry*)))

(defun/i register-store (store)
  "Add store to the global registry."
  (:feature vigil-registry)
  (:role "Store registration")
  (:purpose "Make store discoverable by supervisor")
  (bt:with-lock-held (*registry-lock*)
    (setf (gethash (store-name store) *store-registry*) store))
  store)

(defun/i unregister-store (store)
  "Remove store from the global registry."
  (:feature vigil-registry)
  (:role "Store cleanup")
  (:purpose "Remove store when scope exits")
  (bt:with-lock-held (*registry-lock*)
    (remhash (store-name store) *store-registry*))
  store)

;;; Public API

(defun/i list-stores ()
  "Return list of all registered store names."
  (:feature vigil-registry)
  (:role "Store enumeration")
  (:purpose "Enable supervisor to discover all active stores")
  (bt:with-lock-held (*registry-lock*)
    (loop for name being the hash-keys of *store-registry*
          collect name)))

(defun/i get-store (name)
  "Get store by name, or NIL if not found."
  (:feature vigil-registry)
  (:role "Store lookup")
  (:purpose "Retrieve specific store for querying")
  (bt:with-lock-held (*registry-lock*)
    (gethash name *store-registry*)))

(defun/i find-stores (predicate)
  "Return list of stores matching predicate."
  (:feature vigil-registry)
  (:role "Filtered store query")
  (:purpose "Find stores by arbitrary condition")
  (bt:with-lock-held (*registry-lock*)
    (loop for store being the hash-values of *store-registry*
          when (funcall predicate store)
          collect store)))

(defun/i map-stores (function)
  "Apply function to each store, return results."
  (:feature vigil-registry)
  (:role "Store iteration")
  (:purpose "Apply operation across all stores")
  (bt:with-lock-held (*registry-lock*)
    (loop for store being the hash-values of *store-registry*
          collect (funcall function store))))
```

**Step 4: Run test to verify it passes**

Run: `(asdf:test-system :vigil)`
Expected: PASS

**Step 5: Commit**

```bash
git add src/registry.lisp tests/registry-tests.lisp
git commit -m "Add thread-safe store registry"
```

---

## Task 6: Scoping (with-store and spawn)

**Files:**
- Create: `src/scoping.lisp`
- Create: `tests/scoping-tests.lisp`

**Step 1: Write failing tests**

```lisp
;;; tests/scoping-tests.lisp
(in-package #:vigil-tests)

(in-suite scoping-tests)

(def-fixture clean-registry ()
  (vigil::clear-registry)
  (setf vigil:*metrics* nil)
  (unwind-protect
      (&body)
    (vigil::clear-registry)
    (setf vigil:*metrics* nil)))

(test with-store-binds-metrics
  "with-store binds *metrics* to a new store"
  (with-fixture clean-registry ()
    (is (null *metrics*))
    (with-store ("test-scope")
      (is (not (null *metrics*)))
      (is (equal "test-scope" (store-name *metrics*))))
    (is (null *metrics*))))

(test with-store-registers
  "with-store registers the store"
  (with-fixture clean-registry ()
    (with-store ("registered-store")
      (is (not (null (get-store "registered-store")))))
    ;; After exit, store is unregistered
    (is (null (get-store "registered-store")))))

(test with-store-nesting
  "Nested with-store creates child scope"
  (with-fixture clean-registry ()
    (with-store ("parent")
      (let ((parent-store *metrics*))
        (with-store ("child")
          (is (not (eq parent-store *metrics*)))
          (is (eq parent-store (store-parent *metrics*))))
        (is (eq parent-store *metrics*))))))

(test spawn-inherits-binding
  "spawn creates thread that inherits *metrics*"
  (with-fixture clean-registry ()
    (with-store ("main-agent")
      (let ((result nil)
            (latch (bt:make-condition-variable))
            (lock (bt:make-lock)))
        (spawn (lambda ()
                 (bt:with-lock-held (lock)
                   (setf result (store-name *metrics*))
                   (bt:condition-notify latch)))
               :name "worker")
        (bt:with-lock-held (lock)
          (bt:condition-wait latch lock :timeout 2))
        (is (equal "main-agent" result))))))

(test spawn-without-metrics-ok
  "spawn works when *metrics* is nil"
  (with-fixture clean-registry ()
    (let ((result :not-run)
          (latch (bt:make-condition-variable))
          (lock (bt:make-lock)))
      (spawn (lambda ()
               (bt:with-lock-held (lock)
                 (setf result *metrics*)
                 (bt:condition-notify latch)))
             :name "orphan")
      (bt:with-lock-held (lock)
        (bt:condition-wait latch lock :timeout 2))
      (is (null result)))))
```

**Step 2: Run test to verify it fails**

Run: `(asdf:test-system :vigil)`
Expected: FAIL

**Step 3: Write scoping implementation**

```lisp
;;; src/scoping.lisp
(in-package #:vigil)

;;; Special variables

(defvar *global-metrics* nil
  "Image-wide metrics store. Initialized via initialize-global-metrics.")

(defvar *metrics* nil
  "Current scope's metrics store. Dynamically bound by with-store.")

;;; Initialization

(defun/i initialize-global-metrics (&key (step 10) (retention 3600))
  "Initialize the global metrics store. Call once at startup."
  (:feature vigil-scoping)
  (:role "Global store initialization")
  (:purpose "Set up image-wide metrics before any recording")
  (setf *global-metrics* (make-store "global" ))
  (register-store *global-metrics*)
  *global-metrics*)

;;; with-store macro

(defmacro with-store ((name &key parent) &body body)
  "Bind *metrics* to a new store for the duration of BODY.
   The store is registered on entry and unregistered on exit.
   If parent is not specified and *metrics* is bound, uses current *metrics* as parent."
  (let ((store-var (gensym "STORE")))
    `(let* ((,store-var (make-store ,name
                                    :parent (or ,parent *metrics*)))
            (*metrics* ,store-var))
       (register-store ,store-var)
       (unwind-protect
           (progn ,@body)
         (unregister-store ,store-var)))))

(defintent with-store
  :feature vigil-scoping
  :role "Scoped store binding"
  :purpose "Create store with automatic registration and cleanup"
  :assumptions ((:name-string "NAME evaluates to a string")
                (:body-forms "BODY is a sequence of forms"))
  :failure-modes ((:unwind "Non-local exit still triggers cleanup")))

;;; spawn function

(defun/i spawn (function &key name)
  "Spawn a thread that inherits the current *metrics* binding."
  (:feature vigil-scoping)
  (:role "Thread creation with binding inheritance")
  (:purpose "Ensure child threads share parent's metrics store")
  (:assumptions ((:function "FUNCTION is a zero-argument callable")))
  (let ((parent-metrics *metrics*)
        (parent-global *global-metrics*))
    (bt:make-thread
     (lambda ()
       (let ((*metrics* parent-metrics)
             (*global-metrics* parent-global))
         (funcall function)))
     :name (or name "vigil-worker"))))
```

**Step 4: Run test to verify it passes**

Run: `(asdf:test-system :vigil)`
Expected: PASS

**Step 5: Commit**

```bash
git add src/scoping.lisp tests/scoping-tests.lisp
git commit -m "Add with-store macro and spawn with binding inheritance"
```

---

## Task 7: Recording API

**Files:**
- Create: `src/recording.lisp`
- Create: `tests/recording-tests.lisp`

**Step 1: Write failing tests**

```lisp
;;; tests/recording-tests.lisp
(in-package #:vigil-tests)

(in-suite recording-tests)

(def-fixture clean-registry ()
  (vigil::clear-registry)
  (setf vigil:*metrics* nil)
  (setf vigil:*global-metrics* nil)
  (unwind-protect
      (&body)
    (vigil::clear-registry)
    (setf vigil:*metrics* nil)
    (setf vigil:*global-metrics* nil)))

(test record-explicit-store
  "record writes to explicit store"
  (with-fixture clean-registry ()
    (let ((store (vigil::make-store "test")))
      (record store "counter" 42 :step 1 :retention 60)
      (record store "counter" 43)
      (let ((info (rrd:rrd-info (vigil::store-backend store) "counter")))
        (is (not (null info)))))))

(test record!-uses-metrics
  "record! uses current *metrics* binding"
  (with-fixture clean-registry ()
    (with-store ("my-store")
      (record! "value" 100 :step 1 :retention 60)
      (let ((info (rrd:rrd-info (vigil::store-backend *metrics*) "value")))
        (is (not (null info)))))))

(test record!-signals-without-metrics
  "record! signals no-active-store when *metrics* is nil"
  (with-fixture clean-registry ()
    (signals no-active-store
      (record! "orphan" 1))))

(test record-global!-uses-global
  "record-global! uses *global-metrics*"
  (with-fixture clean-registry ()
    (initialize-global-metrics :step 1 :retention 60)
    (record-global! "image.total" 999)
    (let ((info (rrd:rrd-info (vigil::store-backend *global-metrics*) "image.total")))
      (is (not (null info))))))

(test ensure-metric-creates-if-missing
  "ensure-metric creates metric only if not exists"
  (with-fixture clean-registry ()
    (let ((store (vigil::make-store "test")))
      (ensure-metric store "new-metric" :step 5 :retention 300)
      (ensure-metric store "new-metric" :step 10 :retention 600) ; should not change
      (let ((info (rrd:rrd-info (vigil::store-backend store) "new-metric")))
        (is (= 5 (getf info :step)))))))

(test record-auto-creates-metric
  "record creates metric with defaults if not exists"
  (with-fixture clean-registry ()
    (let ((store (vigil::make-store "test")))
      (record store "auto-created" 1.0)
      (let ((info (rrd:rrd-info (vigil::store-backend store) "auto-created")))
        (is (not (null info)))))))
```

**Step 2: Run test to verify it fails**

Run: `(asdf:test-system :vigil)`
Expected: FAIL

**Step 3: Write recording implementation**

```lisp
;;; src/recording.lisp
(in-package #:vigil)

;;; Default parameters for auto-created metrics
(defparameter *default-step* 10
  "Default step in seconds for auto-created metrics.")

(defparameter *default-retention* 3600
  "Default retention in seconds for auto-created metrics.")

;;; Helper: ensure metric exists

(defun/i ensure-metric (store metric-name &key (step *default-step*)
                                               (retention *default-retention*)
                                               (cf :average))
  "Ensure metric exists in store, creating with given params if not."
  (:feature vigil-core)
  (:role "Metric auto-creation")
  (:purpose "Lazily create metrics on first write")
  (bt:with-lock-held ((store-lock store))
    (let ((backend (store-backend store)))
      (handler-case
          (rrd:rrd-info backend metric-name)
        (rrd:metric-not-found ()
          (rrd:rrd-create backend metric-name
                          :step step :retention retention :cf cf))))))

;;; Core recording function

(defun/i record (store metric-name value &key (timestamp (get-universal-time))
                                              (step *default-step*)
                                              (retention *default-retention*)
                                              (cf :average))
  "Record a value to a metric in the given store. Thread-safe.
   Creates metric if it doesn't exist."
  (:feature vigil-core)
  (:role "Primary write path")
  (:purpose "Thread-safe metric update with auto-creation")
  (ensure-metric store metric-name :step step :retention retention :cf cf)
  (bt:with-lock-held ((store-lock store))
    (rrd:rrd-update (store-backend store) metric-name value :timestamp timestamp)))

;;; Convenience macros

(defun/i record! (metric-name value &key (timestamp (get-universal-time))
                                         (step *default-step*)
                                         (retention *default-retention*)
                                         (cf :average))
  "Record to current *metrics*. Signals no-active-store if unbound."
  (:feature vigil-scoping)
  (:role "Implicit-scope recording")
  (:purpose "Convenient recording using dynamic binding")
  (unless *metrics*
    (error 'no-active-store))
  (record *metrics* metric-name value
          :timestamp timestamp :step step :retention retention :cf cf))

(defun/i record-global! (metric-name value &key (timestamp (get-universal-time))
                                                (step *default-step*)
                                                (retention *default-retention*)
                                                (cf :average))
  "Record to *global-metrics*."
  (:feature vigil-scoping)
  (:role "Global-scope recording")
  (:purpose "Record image-wide metrics")
  (unless *global-metrics*
    (error 'no-active-store))
  (record *global-metrics* metric-name value
          :timestamp timestamp :step step :retention retention :cf cf))
```

**Step 4: Run test to verify it passes**

Run: `(asdf:test-system :vigil)`
Expected: PASS

**Step 5: Commit**

```bash
git add src/recording.lisp tests/recording-tests.lisp
git commit -m "Add thread-safe recording API with auto-creation"
```

---

## Task 8: Query API

**Files:**
- Create: `src/queries.lisp`
- Create: `tests/queries-tests.lisp`

**Step 1: Write failing tests**

```lisp
;;; tests/queries-tests.lisp
(in-package #:vigil-tests)

(in-suite queries-tests)

(def-fixture clean-registry ()
  (vigil::clear-registry)
  (setf vigil:*metrics* nil)
  (unwind-protect
      (&body)
    (vigil::clear-registry)
    (setf vigil:*metrics* nil)))

(test last-value-returns-most-recent
  "last-value returns the most recently recorded value"
  (with-fixture clean-registry ()
    (let ((store (vigil::make-store "test"))
          (now (get-universal-time)))
      (record store "metric" 10.0 :timestamp now :step 1 :retention 60)
      (record store "metric" 20.0 :timestamp (+ now 1))
      (record store "metric" 30.0 :timestamp (+ now 2))
      (is (= 30.0d0 (last-value store "metric"))))))

(test last-value-nil-for-missing
  "last-value returns NIL for non-existent metric"
  (with-fixture clean-registry ()
    (let ((store (vigil::make-store "test")))
      (is (null (last-value store "nonexistent"))))))

(test last-update-returns-timestamp
  "last-update returns most recent timestamp"
  (with-fixture clean-registry ()
    (let ((store (vigil::make-store "test"))
          (now (get-universal-time)))
      (record store "metric" 1.0 :timestamp now :step 1 :retention 60)
      (record store "metric" 2.0 :timestamp (+ now 5))
      (is (= (+ now 5) (last-update store "metric"))))))

(test aggregate-average
  "aggregate computes average over window"
  (with-fixture clean-registry ()
    (let ((store (vigil::make-store "test"))
          (now (get-universal-time)))
      (record store "latency" 100.0 :timestamp (- now 5) :step 1 :retention 60)
      (record store "latency" 200.0 :timestamp (- now 4))
      (record store "latency" 300.0 :timestamp (- now 3))
      (let ((avg (aggregate store "latency" :window 10 :function :average)))
        (is (= 200.0d0 avg))))))

(test aggregate-min-max
  "aggregate computes min and max"
  (with-fixture clean-registry ()
    (let ((store (vigil::make-store "test"))
          (now (get-universal-time)))
      (record store "val" 5.0 :timestamp (- now 3) :step 1 :retention 60)
      (record store "val" 15.0 :timestamp (- now 2))
      (record store "val" 10.0 :timestamp (- now 1))
      (is (= 5.0d0 (aggregate store "val" :window 10 :function :min)))
      (is (= 15.0d0 (aggregate store "val" :window 10 :function :max))))))

(test aggregate-sum-count
  "aggregate computes sum and count"
  (with-fixture clean-registry ()
    (let ((store (vigil::make-store "test"))
          (now (get-universal-time)))
      (record store "events" 1.0 :timestamp (- now 3) :step 1 :retention 60)
      (record store "events" 2.0 :timestamp (- now 2))
      (record store "events" 3.0 :timestamp (- now 1))
      (is (= 6.0d0 (aggregate store "events" :window 10 :function :sum)))
      (is (= 3 (aggregate store "events" :window 10 :function :count))))))

(test exceeds-threshold
  "exceeds? checks if aggregate exceeds threshold"
  (with-fixture clean-registry ()
    (let ((store (vigil::make-store "test"))
          (now (get-universal-time)))
      (record store "error-rate" 0.1 :timestamp (- now 2) :step 1 :retention 60)
      (record store "error-rate" 0.2 :timestamp (- now 1))
      (is (exceeds? store "error-rate" 0.05 :window 10 :function :average))
      (is (not (exceeds? store "error-rate" 0.5 :window 10 :function :average))))))
```

**Step 2: Run test to verify it fails**

Run: `(asdf:test-system :vigil)`
Expected: FAIL

**Step 3: Write queries implementation**

```lisp
;;; src/queries.lisp
(in-package #:vigil)

;;; Point queries

(defun/i last-value (store metric-name)
  "Return the most recently recorded value for metric, or NIL."
  (:feature vigil-core)
  (:role "Point query")
  (:purpose "Get current metric value for threshold checks")
  (bt:with-lock-held ((store-lock store))
    (let ((backend (store-backend store)))
      (handler-case
          (let* ((info (rrd:rrd-info backend metric-name))
                 (last-ts (getf info :last-update)))
            (when last-ts
              (let ((data (rrd:rrd-fetch backend metric-name
                                         :start last-ts :end last-ts)))
                (cdr (first data)))))
        (rrd:metric-not-found () nil)))))

(defun/i last-update (store metric-name)
  "Return the timestamp of most recent update, or NIL."
  (:feature vigil-core)
  (:role "Timestamp query")
  (:purpose "Check when metric was last updated (heartbeat detection)")
  (bt:with-lock-held ((store-lock store))
    (let ((backend (store-backend store)))
      (handler-case
          (getf (rrd:rrd-info backend metric-name) :last-update)
        (rrd:metric-not-found () nil)))))

;;; Aggregate queries

(defun/i aggregate (store metric-name &key (window 300) (function :average))
  "Compute aggregate of metric over time window.
   WINDOW is seconds back from now.
   FUNCTION is :average, :min, :max, :sum, or :count."
  (:feature vigil-core)
  (:role "Time-window aggregation")
  (:purpose "Compute statistics for adaptive decisions")
  (bt:with-lock-held ((store-lock store))
    (let ((backend (store-backend store)))
      (handler-case
          (let* ((now (get-universal-time))
                 (start (- now window))
                 (data (rrd:rrd-fetch backend metric-name :start start :end now))
                 (values (remove nil (mapcar #'cdr data))))
            (when values
              (ecase function
                (:average (/ (reduce #'+ values) (length values)))
                (:min (reduce #'min values))
                (:max (reduce #'max values))
                (:sum (reduce #'+ values))
                (:count (length values)))))
        (rrd:metric-not-found () nil)))))

;;; Threshold detection

(defun/i exceeds? (store metric-name threshold &key (window 300) (function :average))
  "Return T if aggregate of metric exceeds threshold."
  (:feature vigil-core)
  (:role "Threshold check")
  (:purpose "Simple predicate for health checks")
  (let ((value (aggregate store metric-name :window window :function function)))
    (and value (> value threshold))))
```

**Step 4: Run test to verify it passes**

Run: `(asdf:test-system :vigil)`
Expected: PASS

**Step 5: Commit**

```bash
git add src/queries.lisp tests/queries-tests.lisp
git commit -m "Add query API with aggregates and threshold detection"
```

---

## Task 9: Integration Tests

**Files:**
- Create: `tests/integration-tests.lisp`

**Step 1: Write integration tests**

```lisp
;;; tests/integration-tests.lisp
(in-package #:vigil-tests)

(in-suite integration-tests)

(def-fixture clean-state ()
  (vigil::clear-registry)
  (setf vigil:*metrics* nil)
  (setf vigil:*global-metrics* nil)
  (unwind-protect
      (&body)
    (vigil::clear-registry)
    (setf vigil:*metrics* nil)
    (setf vigil:*global-metrics* nil)))

(test end-to-end-agent-workflow
  "Complete agent workflow: create store, record, query"
  (with-fixture clean-state ()
    (with-store ("booking-agent")
      (let ((now (get-universal-time)))
        ;; Record some metrics
        (record! "heartbeat" now :step 1 :retention 60)
        (record! "bookings" 1.0 :step 1 :retention 60)
        (record! "bookings" 2.0 :timestamp (+ now 1))
        (record! "bookings" 3.0 :timestamp (+ now 2))

        ;; Query them back
        (is (= now (last-update *metrics* "heartbeat")))
        (is (= 3.0d0 (last-value *metrics* "bookings")))
        (is (= 6.0d0 (aggregate *metrics* "bookings" :window 10 :function :sum)))))))

(test supervisor-finds-agents
  "Supervisor can discover and query all agents"
  (with-fixture clean-state ()
    (let ((threads nil)
          (barrier (bt:make-condition-variable))
          (barrier-lock (bt:make-lock))
          (started 0))
      ;; Start two agents
      (dolist (name '("agent-1" "agent-2"))
        (push (bt:make-thread
               (lambda ()
                 (with-store (name)
                   (record! "heartbeat" (get-universal-time) :step 1 :retention 60)
                   ;; Signal started
                   (bt:with-lock-held (barrier-lock)
                     (incf started)
                     (bt:condition-notify barrier))
                   ;; Wait a bit
                   (sleep 0.5)))
               :name name)
              threads))

      ;; Wait for both to start
      (loop while (< started 2)
            do (bt:with-lock-held (barrier-lock)
                 (bt:condition-wait barrier barrier-lock :timeout 2)))

      ;; Supervisor queries
      (is (= 2 (length (list-stores))))
      (is (not (null (get-store "agent-1"))))
      (is (not (null (get-store "agent-2"))))

      ;; Wait for threads
      (mapc #'bt:join-thread threads)

      ;; After exit, stores are gone
      (is (= 0 (length (list-stores)))))))

(test nested-agent-hierarchy
  "Child agents can override parent store"
  (with-fixture clean-state ()
    (with-store ("parent-agent")
      (record! "parent-metric" 1.0 :step 1 :retention 60)
      (let ((parent-store *metrics*))
        (with-store ("child-agent")
          (record! "child-metric" 2.0 :step 1 :retention 60)
          ;; Child has its own store
          (is (not (eq parent-store *metrics*)))
          ;; Parent is set
          (is (eq parent-store (store-parent *metrics*)))
          ;; Child metric exists in child
          (is (= 2.0d0 (last-value *metrics* "child-metric")))
          ;; Parent metric doesn't exist in child
          (is (null (last-value *metrics* "parent-metric"))))
        ;; Back to parent
        (is (eq parent-store *metrics*))
        (is (= 1.0d0 (last-value *metrics* "parent-metric")))))))

(test concurrent-writes-to-same-store
  "Multiple threads can write to same store safely"
  (with-fixture clean-state ()
    (let* ((store (vigil::make-store "shared"))
           (iterations 100)
           (threads nil))
      (vigil::register-store store)
      (record store "counter" 0.0 :step 1 :retention 3600)

      ;; Spawn threads that increment
      (dotimes (i 4)
        (push (bt:make-thread
               (lambda ()
                 (dotimes (j iterations)
                   (let* ((current (or (last-value store "counter") 0.0d0))
                          (next (+ current 1.0d0)))
                     (record store "counter" next))))
               :name (format nil "writer-~d" i))
              threads))

      ;; Wait for all
      (mapc #'bt:join-thread threads)

      ;; Note: Due to race conditions in read-modify-write,
      ;; final value may be less than (* 4 iterations).
      ;; But no crashes should occur.
      (is (not (null (last-value store "counter"))))
      (vigil::unregister-store store))))
```

**Step 2: Run all tests**

Run: `(asdf:test-system :vigil)`
Expected: PASS

**Step 3: Commit**

```bash
git add tests/integration-tests.lisp
git commit -m "Add integration tests for threading and agent hierarchy"
```

---

## Task 10: Create Source Directories and Finalize

**Step 1: Ensure directories exist**

```bash
mkdir -p src tests
```

**Step 2: Run full test suite**

```lisp
(ql:quickload :vigil/tests)
(asdf:test-system :vigil)
```

**Step 3: Final commit**

```bash
git add -A
git status  # verify no secrets
git commit -m "Complete vigil v0.1.0 implementation"
```

---

## Summary

| Task | Component | Tests |
|------|-----------|-------|
| 1 | System definition | - |
| 2 | Test infrastructure | - |
| 3 | Features + conditions | - |
| 4 | Store class | 2 |
| 5 | Registry | 5 |
| 6 | Scoping | 5 |
| 7 | Recording | 6 |
| 8 | Queries | 7 |
| 9 | Integration | 4 |

**Total: ~29 tests covering core functionality**
