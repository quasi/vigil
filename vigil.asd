(defsystem "vigil"
  :description "Internal process observability framework for Common Lisp"
  :author "Abhijit Rao <quasi@quasilabs.in>"
  :license "MIT"
  :version "0.1.0"
  :depends-on ("trivial-rrd" "bordeaux-threads" "telos")
  ;; :serial t — load order is significant: package → features → conditions → store
  ;;             → registry → scoping → recording → queries.  Explicit depends-on
  ;;             would be equivalent but :serial t is clearer for this linear chain.
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

(defsystem "vigil/archiver"
  :description "SQLite archiver for vigil metrics"
  :depends-on ("vigil" "trivial-rrd/sqlite")
  :serial t
  :components ((:module "src"
                :components ((:file "archiver"))))
  :in-order-to ((test-op (test-op "vigil/archiver-tests"))))

(defsystem "vigil/archiver-tests"
  :description "Tests for vigil archiver"
  :depends-on ("vigil/archiver" "fiveam")
  :serial t
  :components ((:module "tests"
                :components ((:file "archiver-tests"))))
  :perform (test-op (o c)
             (symbol-call :fiveam :run!
                          (uiop:find-symbol* :archiver-tests :vigil-tests))))
