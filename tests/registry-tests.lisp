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
