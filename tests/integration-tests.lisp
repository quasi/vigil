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
        ;; Use past timestamps so they're in the aggregate window
        ;; (aggregate uses current time as the end of window)
        (record! "bookings" 1.0 :step 1 :retention 60 :timestamp (- now 2))
        (record! "bookings" 2.0 :timestamp (- now 1))
        (record! "bookings" 3.0 :timestamp now)

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
