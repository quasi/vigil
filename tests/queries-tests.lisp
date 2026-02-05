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
