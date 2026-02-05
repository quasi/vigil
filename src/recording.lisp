(in-package #:vigil)

;;; Default parameters for auto-created metrics
(defparameter *default-step* 10
  "Default step in seconds for auto-created metrics.")

(defparameter *default-retention* 3600
  "Default retention in seconds for auto-created metrics.")

;;; Helper: ensure metric exists

(defun/i ensure-metric (store metric-name &key (step *default-step*)
                                               (retention *default-retention*)
                                               (cf :average))
  "Ensure metric exists in store, creating with given params if not."
  (:feature vigil-core)
  (:role "Metric auto-creation")
  (:purpose "Lazily create metrics on first write")
  (bt:with-lock-held ((store-lock store))
    (let ((backend (store-backend store)))
      (handler-case
          (rrd:rrd-info backend metric-name)
        (rrd:metric-not-found ()
          (rrd:rrd-create backend metric-name
                          :step step :retention retention :cf cf))))))

;;; Core recording function

(defun/i record (store metric-name value &key (timestamp (get-universal-time))
                                              (step *default-step*)
                                              (retention *default-retention*)
                                              (cf :average))
  "Record a value to a metric in the given store. Thread-safe.
   Creates metric if it doesn't exist."
  (:feature vigil-core)
  (:role "Primary write path")
  (:purpose "Thread-safe metric update with auto-creation")
  (ensure-metric store metric-name :step step :retention retention :cf cf)
  (bt:with-lock-held ((store-lock store))
    (rrd:rrd-update (store-backend store) metric-name value :timestamp timestamp)))

;;; Convenience functions

(defun/i record! (metric-name value &key (timestamp (get-universal-time))
                                         (step *default-step*)
                                         (retention *default-retention*)
                                         (cf :average))
  "Record to current *metrics*. Signals no-active-store if unbound."
  (:feature vigil-scoping)
  (:role "Implicit-scope recording")
  (:purpose "Convenient recording using dynamic binding")
  (unless *metrics*
    (error 'no-active-store))
  (record *metrics* metric-name value
          :timestamp timestamp :step step :retention retention :cf cf))

(defun/i record-global! (metric-name value &key (timestamp (get-universal-time))
                                                (step *default-step*)
                                                (retention *default-retention*)
                                                (cf :average))
  "Record to *global-metrics*."
  (:feature vigil-scoping)
  (:role "Global-scope recording")
  (:purpose "Record image-wide metrics")
  (unless *global-metrics*
    (error 'no-active-store))
  (record *global-metrics* metric-name value
          :timestamp timestamp :step step :retention retention :cf cf))
