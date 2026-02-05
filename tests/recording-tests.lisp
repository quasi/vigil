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
