(in-package #:vigil)

;;; Point queries

(defun/i last-value (store metric-name)
  "Return the most recently recorded value for metric, or NIL."
  (:feature vigil-core)
  (:role "Point query")
  (:purpose "Get current metric value for threshold checks")
  (bt:with-lock-held ((store-lock store))
    (let ((backend (store-backend store)))
      (handler-case
          (let* ((info (rrd:rrd-info backend metric-name))
                 (last-ts (getf info :last-update)))
            (when last-ts
              (let ((data (rrd:rrd-fetch backend metric-name
                                         :start last-ts :end last-ts)))
                (cdr (first data)))))
        (rrd:metric-not-found () nil)))))

(defun/i last-update (store metric-name)
  "Return the timestamp of most recent update, or NIL."
  (:feature vigil-core)
  (:role "Timestamp query")
  (:purpose "Check when metric was last updated (heartbeat detection)")
  (bt:with-lock-held ((store-lock store))
    (let ((backend (store-backend store)))
      (handler-case
          (getf (rrd:rrd-info backend metric-name) :last-update)
        (rrd:metric-not-found () nil)))))

;;; Aggregate queries

(defun/i aggregate (store metric-name &key (window 300) (function :average))
  "Compute aggregate of metric over time window.
   WINDOW is seconds back from now.
   FUNCTION is :average, :min, :max, :sum, or :count."
  (:feature vigil-core)
  (:role "Time-window aggregation")
  (:purpose "Compute statistics for adaptive decisions")
  (bt:with-lock-held ((store-lock store))
    (let ((backend (store-backend store)))
      (handler-case
          (let* ((now (get-universal-time))
                 (start (- now window))
                 (data (rrd:rrd-fetch backend metric-name :start start :end now))
                 (values (remove nil (mapcar #'cdr data))))
            (when values
              (ecase function
                (:average (/ (reduce #'+ values) (length values)))
                (:min (reduce #'min values))
                (:max (reduce #'max values))
                (:sum (reduce #'+ values))
                (:count (length values)))))
        (rrd:metric-not-found () nil)))))

;;; Threshold detection

(defun/i exceeds? (store metric-name threshold &key (window 300) (function :average))
  "Return T if aggregate of metric exceeds threshold."
  (:feature vigil-core)
  (:role "Threshold check")
  (:purpose "Simple predicate for health checks")
  (let ((value (aggregate store metric-name :window window :function function)))
    (and value (> value threshold))))
