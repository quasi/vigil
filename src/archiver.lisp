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
          (error (e)
            ;; Log and continue - don't let one metric break entire archive
            (format *error-output* "~&Archiver: Error copying ~a/~a: ~a~%"
                    (store-name store) metric-name e)))))))

;;; Background thread

(defun/i %archiver-loop ()
  "Main loop for background archiver thread."
  (:feature vigil-archiver)
  (:role "Background archive scheduler")
  (:purpose "Periodically archive all stores while running flag is set")
  (loop while *archiver-running*
        do (handler-case
               (progn
                 (archive-all-stores :backend *archiver-backend*)
                 (rrd:rrd-flush *archiver-backend*))
             (error (e)
               (format *error-output* "~&Archiver: Error in archive loop: ~a~%" e)))
           (sleep *archiver-interval*)))

;;; Public API

(defun/i start-archiver (&key (db-path "/tmp/vigil-archive.db")
                              (interval 60))
  "Start the background archiver thread.
   DB-PATH is the SQLite database file path.
   INTERVAL is seconds between archive runs."
  (:feature vigil-archiver)
  (:role "Archiver lifecycle start")
  (:purpose "Initialize SQLite backend and start background thread")
  (bt:with-lock-held (*archiver-lock*)
    (when *archiver-running*
      (error "Archiver already running"))
    ;; Create and open SQLite backend
    (setf *archiver-backend* (make-instance 'rrd:sqlite-backend :db-path db-path))
    (rrd:rrd-open *archiver-backend*)
    ;; Set interval and start thread
    (setf *archiver-interval* interval)
    (setf *archiver-running* t)
    (setf *archiver-thread*
          (bt:make-thread #'%archiver-loop :name "vigil-archiver")))
  t)

(defun/i stop-archiver (&key (wait t))
  "Stop the background archiver thread.
   If WAIT is true, blocks until thread exits."
  (:feature vigil-archiver)
  (:role "Archiver lifecycle stop")
  (:purpose "Signal thread to stop, optionally wait, close backend")
  (bt:with-lock-held (*archiver-lock*)
    (unless *archiver-running*
      (return-from stop-archiver nil))
    ;; Signal thread to stop
    (setf *archiver-running* nil))
  ;; Wait for thread outside lock
  (when (and wait *archiver-thread*)
    (bt:join-thread *archiver-thread*))
  ;; Close backend
  (bt:with-lock-held (*archiver-lock*)
    (when *archiver-backend*
      (handler-case
          (progn
            (rrd:rrd-flush *archiver-backend*)
            (rrd:rrd-close *archiver-backend*))
        (error (e)
          (format *error-output* "~&Archiver: Error closing backend: ~a~%" e))))
    (setf *archiver-backend* nil)
    (setf *archiver-thread* nil))
  t)

(defun/i archiver-running-p ()
  "Return T if archiver is currently running."
  (:feature vigil-archiver)
  (:role "Status check")
  (:purpose "Allow callers to check archiver state")
  *archiver-running*)

(defun/i archive-store (store &key backend)
  "Archive a single store to SQLite.
   If BACKEND is not provided, uses *archiver-backend* (archiver must be running)."
  (:feature vigil-archiver)
  (:role "Manual single-store archive")
  (:purpose "On-demand archive of specific store")
  (let ((target-backend (or backend *archiver-backend*)))
    (unless target-backend
      (error "No backend provided and archiver not running"))
    (%archive-store-to-backend store target-backend)
    (rrd:rrd-flush target-backend))
  t)

(defun/i archive-all-stores (&key backend)
  "Archive all registered stores to SQLite.
   If BACKEND is not provided, uses *archiver-backend* (archiver must be running)."
  (:feature vigil-archiver)
  (:role "Manual full archive")
  (:purpose "On-demand archive of all stores")
  (let ((target-backend (or backend *archiver-backend*)))
    (unless target-backend
      (error "No backend provided and archiver not running"))
    (dolist (store (find-stores (constantly t)))
      (handler-case
          (%archive-store-to-backend store target-backend)
        (error (e)
          (format *error-output* "~&Archiver: Error archiving store ~a: ~a~%"
                  (store-name store) e)))))
  t)
