(defpackage #:vigil
  (:use #:cl)
  (:import-from #:telos
    #:deffeature
    #:defun/i
    #:defclass/i
    #:defintent)
  (:local-nicknames (#:rrd #:trivial-rrd)
                    (#:bt #:bordeaux-threads))
  (:export
   ;; Store class and accessors
   #:store
   #:store-name
   #:store-parent
   #:store-created-at

   ;; Registry
   #:list-stores
   #:get-store
   #:find-stores
   #:map-stores

   ;; Scoping
   #:*global-metrics*
   #:*metrics*
   #:with-store
   #:spawn
   #:initialize-global-metrics

   ;; Recording
   #:record
   #:record!
   #:record-global!
   #:ensure-metric

   ;; Queries
   #:last-value
   #:last-update
   #:aggregate
   #:exceeds?

   ;; Conditions — errors
   #:vigil-error
   #:store-not-found
   #:no-active-store
   #:global-metrics-not-initialized
   #:condition-store-name
   #:archiver-already-running
   #:no-archiver-backend

   ;; Conditions — warnings
   #:vigil-warning
   #:archiver-metric-copy-failed
   #:archiver-store-failed
   #:archiver-loop-error

   ;; Archiver (loaded via vigil/archiver)
   #:start-archiver
   #:stop-archiver
   #:archive-store
   #:archive-all-stores
   #:archiver-running-p))
