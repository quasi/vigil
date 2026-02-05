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
