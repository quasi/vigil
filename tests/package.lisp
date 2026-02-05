(defpackage #:vigil-tests
  (:use #:cl #:vigil #:fiveam #:th.property)
  (:local-nicknames (#:gen #:th.gen)
                    (#:bt #:bordeaux-threads)
                    (#:rrd #:trivial-rrd))
  (:export #:run-tests
           #:vigil-tests
           #:archiver-tests))
