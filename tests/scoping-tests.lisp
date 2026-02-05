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
