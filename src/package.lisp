(defpackage #:vigil
  (:use #:cl #:telos)
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

   ;; Conditions
   #:store-not-found
   #:no-active-store
   #:condition-store-name

   ;; Archiver (loaded via vigil/archiver)
   #:start-archiver
   #:stop-archiver
   #:archive-store
   #:archive-all-stores
   #:archiver-running-p))
