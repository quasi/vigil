(defpackage #:vigil-tests
  (:use #:cl #:vigil #:fiveam #:th.property)
  (:local-nicknames (#:gen #:th.gen)
                    (#:bt #:bordeaux-threads))
  (:export #:run-tests
           #:vigil-tests))
