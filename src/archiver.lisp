(in-package #:vigil)

;;; SQLite Archiver
;;;
;;; Background thread that periodically dumps store metrics to SQLite
;;; for offline analysis. Not on the hot path - agents never wait on disk I/O.

;;; Telos feature

(deffeature vigil-archiver
  :purpose "Background archival of metrics to SQLite for offline analysis"
  :goals ((:persistence "Durable storage beyond memory retention")
          (:non-blocking "Archive runs in background, never blocks hot path")
          (:manual-trigger "Can archive on-demand for immediate dumps"))
  :constraints ((:sqlite-only "Uses trivial-rrd sqlite-backend")
                (:eventual "Archive is eventually consistent, not real-time"))
  :failure-modes ((:disk-full "SQLite write fails if disk is full")
                  (:corruption "Crash during write may corrupt archive")))

;;; State variables

(defvar *archiver-backend* nil
  "The sqlite-backend used for archiving. Created by start-archiver.")

(defvar *archiver-thread* nil
  "The background archiver thread.")

(defvar *archiver-running* nil
  "Flag to control archiver thread loop.")

(defvar *archiver-lock* (bt:make-lock "vigil-archiver")
  "Lock for archiver state coordination.")

(defvar *archiver-interval* 60
  "Seconds between automatic archive runs.")

;;; Internal helpers

(defun/i %archiver-running-p ()
  "Read *archiver-running* under lock. Safe to call from any thread."
  (bt:with-lock-held (*archiver-lock*) *archiver-running*))

(defun/i %copy-metric-to-backend (memory-backend sqlite-backend metric-name)
  "Copy a single metric from memory to SQLite backend."
  (:feature vigil-archiver)
  (:role "Per-metric data transfer")
  (:purpose "Copy metric config and data from memory to SQLite")
  (let ((info (rrd:rrd-info memory-backend metric-name)))
    ;; Ensure metric exists in SQLite with same config
    (handler-case
        (rrd:rrd-info sqlite-backend metric-name)
      (rrd:metric-not-found ()
        (rrd:rrd-create sqlite-backend metric-name
                        :step (getf info :step)
                        :retention (getf info :retention)
                        :cf (getf info :cf))))
    ;; Fetch all data from memory and write to SQLite
    (let* ((oldest (getf info :oldest))
           (last-update (getf info :last-update)))
      (when (and oldest last-update)
        (let ((data (rrd:rrd-fetch memory-backend metric-name
                                   :start oldest :end last-update)))
          (dolist (point data)
            (when (cdr point)  ; skip NIL values
              (rrd:rrd-update sqlite-backend metric-name (cdr point)
                              :timestamp (car point)))))))))

(defun/i %archive-store-to-backend (store backend)
  "Archive all metrics from a store to the given SQLite backend."
  (:feature vigil-archiver)
  (:role "Per-store archival")
  (:purpose "Copy all metrics from one store to SQLite")
  (bt:with-lock-held ((store-lock store))
    (let ((memory-backend (store-backend store)))
      (dolist (metric-name (rrd:rrd-list-metrics memory-backend))
        (handler-case
            (%copy-metric-to-backend memory-backend backend metric-name)
          ;; Intentional resilience: one metric copy failure must not abort the others.
          ;; Signal a muffleable warning so callers can intercept if needed.
          (error (e)
            (warn 'archiver-metric-copy-failed
                  :store-name (store-name store)
                  :metric-name metric-name
                  :cause e)))))))

;;; Background thread

(defun/i %archiver-loop (interval)
  "Main loop for background archiver thread.
   INTERVAL (seconds) is captured at thread-start and not re-read from the global."
  (:feature vigil-archiver)
  (:role "Background archive scheduler")
  (:purpose "Periodically archive all stores while running flag is set")
  ;; Check the flag under lock at the top of each iteration so stop-archiver's
  ;; write is always visible (eliminates the data-race on *archiver-running*).
  (loop while (%archiver-running-p)
        do (handler-case
               (progn
                 (archive-all-stores :backend *archiver-backend*)
                 (rrd:rrd-flush *archiver-backend*))
             ;; Intentional resilience: a single failed iteration must not kill
             ;; the background thread.  Signal a muffleable warning.
             (error (e)
               (warn 'archiver-loop-error :cause e)))
           (sleep interval)))

;;; Public API

(defun/i start-archiver (&key (db-path "/tmp/vigil-archive.db")
                              (interval 60))
  "Start the background archiver thread.
   DB-PATH is the SQLite database file path.
   INTERVAL is seconds between archive runs (captured at start; live changes to
   *archiver-interval* after this point have no effect on the running thread).
   Signals: archiver-already-running if the archiver is already active."
  (:feature vigil-archiver)
  (:role "Archiver lifecycle start")
  (:purpose "Initialize SQLite backend and start background thread")
  (bt:with-lock-held (*archiver-lock*)
    (when *archiver-running*
      (error 'archiver-already-running))
    ;; Create and open SQLite backend.  Protect against thread-creation failure:
    ;; if bt:make-thread errors after rrd-open, we close the backend and unwind
    ;; cleanly rather than leaking a file descriptor.
    (let* ((backend (make-instance 'rrd:sqlite-backend :db-path db-path))
           (thread nil))
      (rrd:rrd-open backend)
      (unwind-protect
          (progn
            (setf *archiver-interval* interval
                  *archiver-running* t
                  thread (bt:make-thread
                          ;; Capture interval in a closure so the thread is
                          ;; unaffected by future changes to *archiver-interval*.
                          (let ((captured-interval interval))
                            (lambda () (%archiver-loop captured-interval)))
                          :name "vigil-archiver")
                  *archiver-backend* backend
                  *archiver-thread* thread))
        (unless thread
          (setf *archiver-running* nil)
          (rrd:rrd-close backend)))))
  t)

(defun/i stop-archiver (&key (wait t))
  "Stop the background archiver thread.
   If WAIT is true, blocks until the thread exits."
  (:feature vigil-archiver)
  (:role "Archiver lifecycle stop")
  (:purpose "Signal thread to stop, optionally wait, close backend")
  (bt:with-lock-held (*archiver-lock*)
    (unless *archiver-running*
      (return-from stop-archiver nil))
    ;; Clear the flag under lock; %archiver-loop checks it under the same lock.
    (setf *archiver-running* nil))
  ;; Wait for thread outside lock so the loop can acquire the lock to check the flag.
  (when (and wait *archiver-thread*)
    (bt:join-thread *archiver-thread*))
  ;; Close backend under lock.
  (bt:with-lock-held (*archiver-lock*)
    (when *archiver-backend*
      (handler-case
          (progn
            (rrd:rrd-flush *archiver-backend*)
            (rrd:rrd-close *archiver-backend*))
        (error (e)
          (warn 'archiver-loop-error :cause e))))
    (setf *archiver-backend* nil
          *archiver-thread* nil))
  t)

(defun/i archiver-running-p ()
  "Return T if the archiver is currently running."
  (:feature vigil-archiver)
  (:role "Status check")
  (:purpose "Allow callers to check archiver state")
  (%archiver-running-p))

(defun/i archive-store (store &key backend)
  "Archive a single STORE to SQLite.
   If BACKEND is not provided, uses *archiver-backend* (archiver must be running).
   Signals: no-archiver-backend if no backend is available."
  (:feature vigil-archiver)
  (:role "Manual single-store archive")
  (:purpose "On-demand archive of specific store")
  (let ((target-backend (or backend *archiver-backend*)))
    (unless target-backend
      (error 'no-archiver-backend))
    (%archive-store-to-backend store target-backend)
    (rrd:rrd-flush target-backend))
  t)

(defun/i archive-all-stores (&key backend)
  "Archive all registered stores to SQLite.
   If BACKEND is not provided, uses *archiver-backend* (archiver must be running).
   Per-store failures are signaled as archiver-store-failed warnings and do not
   abort the remaining stores.
   Signals: no-archiver-backend if no backend is available."
  (:feature vigil-archiver)
  (:role "Manual full archive")
  (:purpose "On-demand archive of all stores")
  (let ((target-backend (or backend *archiver-backend*)))
    (unless target-backend
      (error 'no-archiver-backend))
    (dolist (store (find-stores (constantly t)))
      (handler-case
          (%archive-store-to-backend store target-backend)
        ;; Intentional resilience: one store's failure must not abort the others.
        (error (e)
          (warn 'archiver-store-failed
                :store-name (store-name store)
                :cause e)))))
  t)
