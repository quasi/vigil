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
