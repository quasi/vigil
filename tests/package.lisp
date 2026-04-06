(defpackage #:vigil-tests
  (:use #:cl #:vigil)
  (:import-from #:fiveam
    #:def-suite
    #:in-suite
    #:test
    #:is
    #:signals
    #:def-fixture
    #:with-fixture
    #:run!
    #:&body)
  (:local-nicknames (#:bt #:bordeaux-threads)
                    (#:rrd #:trivial-rrd))
  (:export #:run-tests
           #:vigil-tests
           #:archiver-tests))
