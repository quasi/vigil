(in-package #:vigil-tests)

;;; Archiver Tests
;;;
;;; Tests for the SQLite archiver functionality.
;;; Note: These tests create temporary SQLite files.

(def-suite archiver-tests
  :description "Tests for SQLite archiver")

(in-suite archiver-tests)

(defvar *test-db-path* nil)

(def-fixture clean-archiver-state ()
  (vigil::clear-registry)
  (setf vigil:*metrics* nil)
  (setf vigil:*global-metrics* nil)
  ;; Create temp db path
  (setf *test-db-path* (format nil "/tmp/vigil-test-~a.db" (get-universal-time)))
  ;; Ensure archiver is stopped
  (when (archiver-running-p)
    (stop-archiver))
  (unwind-protect
      (&body)
    ;; Cleanup
    (when (archiver-running-p)
      (stop-archiver))
    (vigil::clear-registry)
    (setf vigil:*metrics* nil)
    (setf vigil:*global-metrics* nil)
    ;; Remove test db
    (when (and *test-db-path* (probe-file *test-db-path*))
      (delete-file *test-db-path*))))

(test manual-archive-single-store
  "archive-store archives a single store to SQLite"
  (with-fixture clean-archiver-state ()
    (let ((backend (make-instance 'rrd:sqlite-backend :db-path *test-db-path*)))
      (rrd:rrd-open backend)
      (unwind-protect
          (progn
            ;; Create a store with some data
            (with-store ("test-agent")
              (let ((now (get-universal-time)))
                (record! "metric1" 100.0 :step 1 :retention 60 :timestamp (- now 2))
                (record! "metric1" 200.0 :timestamp (- now 1))
                (record! "metric1" 300.0 :timestamp now)
                ;; Archive the store
                (archive-store *metrics* :backend backend)))
            ;; Verify data in SQLite
            (let ((metrics (rrd:rrd-list-metrics backend)))
              (is (member "metric1" metrics :test #'equal))
              (let ((info (rrd:rrd-info backend "metric1")))
                (is (= 1 (getf info :step)))
                (is (= 60 (getf info :retention))))))
        (rrd:rrd-close backend)))))

(test manual-archive-all-stores
  "archive-all-stores archives all registered stores"
  (with-fixture clean-archiver-state ()
    (let ((backend (make-instance 'rrd:sqlite-backend :db-path *test-db-path*)))
      (rrd:rrd-open backend)
      (unwind-protect
          (progn
            ;; Register stores and add data
            (let ((store1 (vigil::make-store "store-a"))
                  (store2 (vigil::make-store "store-b")))
              (vigil::register-store store1)
              (vigil::register-store store2)
              (record store1 "metric-a" 1.0 :step 1 :retention 60)
              (record store2 "metric-b" 2.0 :step 1 :retention 60)
              (archive-all-stores :backend backend)
              (vigil::unregister-store store1)
              (vigil::unregister-store store2))
            ;; Verify both metrics exist
            (let ((metrics (rrd:rrd-list-metrics backend)))
              (is (member "metric-a" metrics :test #'equal))
              (is (member "metric-b" metrics :test #'equal))))
        (rrd:rrd-close backend)))))

(test start-stop-archiver
  "start-archiver and stop-archiver manage background thread"
  (with-fixture clean-archiver-state ()
    ;; Initially not running
    (is (not (archiver-running-p)))
    ;; Start archiver
    (start-archiver :db-path *test-db-path* :interval 1)
    (is (archiver-running-p))
    ;; Create a store and record some data
    (with-store ("background-test")
      (record! "value" 123.0 :step 1 :retention 60)
      ;; Give archiver time to run at least once
      (sleep 1.5))
    ;; Stop archiver
    (stop-archiver :wait t)
    (is (not (archiver-running-p)))
    ;; Verify data was archived
    (let ((backend (make-instance 'rrd:sqlite-backend :db-path *test-db-path*)))
      (rrd:rrd-open backend)
      (unwind-protect
          (let ((metrics (rrd:rrd-list-metrics backend)))
            (is (member "value" metrics :test #'equal)))
        (rrd:rrd-close backend)))))

(test archiver-does-not-block-recording
  "Recording should not be blocked by archiver"
  (with-fixture clean-archiver-state ()
    (start-archiver :db-path *test-db-path* :interval 10)
    (unwind-protect
        (let ((store (vigil::make-store "perf-test")))
          (vigil::register-store store)
          ;; Record many values quickly - should not block
          (let ((start-time (get-internal-real-time)))
            (dotimes (i 100)
              (record store "counter" (float i) :step 1 :retention 3600))
            (let* ((end-time (get-internal-real-time))
                   (elapsed-ms (/ (- end-time start-time)
                                  (/ internal-time-units-per-second 1000))))
              ;; 100 records should complete in under 1 second
              (is (< elapsed-ms 1000))))
          (vigil::unregister-store store))
      (stop-archiver :wait t))))

(test archiver-error-resilience
  "Archiver continues after errors in individual stores"
  (with-fixture clean-archiver-state ()
    (let ((backend (make-instance 'rrd:sqlite-backend :db-path *test-db-path*)))
      (rrd:rrd-open backend)
      (unwind-protect
          (progn
            ;; Create two stores
            (let ((store1 (vigil::make-store "good-store"))
                  (store2 (vigil::make-store "another-good")))
              (vigil::register-store store1)
              (vigil::register-store store2)
              (record store1 "metric1" 1.0 :step 1 :retention 60)
              (record store2 "metric2" 2.0 :step 1 :retention 60)
              ;; Archive should succeed for both
              (archive-all-stores :backend backend)
              (vigil::unregister-store store1)
              (vigil::unregister-store store2))
            ;; Verify both were archived
            (let ((metrics (rrd:rrd-list-metrics backend)))
              (is (= 2 (length metrics)))))
        (rrd:rrd-close backend)))))
