# Use Cases

Real-world patterns for internal process observability.

## Use Case 1: Thread Health Monitoring

**Problem:** You have worker threads that process jobs. Sometimes a thread hangs on I/O or gets stuck in an infinite loop. You need to detect this and take action (kill the thread, alert, spawn replacement).

**Solution:** Each worker writes a heartbeat timestamp. A supervisor periodically scans for stale heartbeats.

### The Worker

```lisp
(defun worker-main (worker-id)
  "Main loop for a worker thread."
  (with-store ((format nil "worker-~d" worker-id))
    (loop
      ;; Write heartbeat before doing work
      (record! "heartbeat" (get-universal-time))

      ;; Do actual work (might hang!)
      (let ((job (get-next-job)))
        (when job
          (process-job job)
          (record! "jobs-completed" 1)))

      ;; Brief pause
      (sleep 0.1))))
```

**Why this works:**

- Each worker has its own store (`worker-0`, `worker-1`, etc.)
- The heartbeat timestamp updates every iteration
- If a worker hangs in `process-job`, its heartbeat stops updating
- The store persists even while the worker is blocked

### The Supervisor

```lisp
(defun find-hung-workers (timeout-seconds)
  "Return stores of workers that haven't heartbeated recently."
  (let ((cutoff (- (get-universal-time) timeout-seconds)))
    (find-stores
      (lambda (store)
        ;; Only check worker stores
        (when (search "worker-" (store-name store))
          (let ((last-hb (last-value store "heartbeat")))
            ;; Hung if no heartbeat or stale heartbeat
            (or (null last-hb)
                (< last-hb cutoff))))))))

(defun health-check-loop ()
  "Periodically check for hung workers and handle them."
  (loop
    (let ((hung (find-hung-workers 30)))
      (dolist (store hung)
        (format t "~&WARNING: ~a appears hung~%" (store-name store))
        ;; Take action: kill thread, send alert, spawn replacement
        (handle-hung-worker store)))
    (sleep 10)))
```

**How the supervisor works:**

1. `find-stores` iterates all registered stores
2. Filter to stores with "worker-" in the name
3. For each, check if heartbeat is older than cutoff
4. Return list of problem stores

### Starting the System

```lisp
(defun start-worker-pool (n)
  "Start N worker threads with health monitoring."
  ;; Start workers
  (dotimes (i n)
    (bt:make-thread
      (lambda () (worker-main i))
      :name (format nil "worker-~d" i)))

  ;; Start supervisor
  (bt:make-thread #'health-check-loop :name "supervisor"))
```

---

## Use Case 2: Payment Gateway Adaptive Routing

**Problem:** You integrate with multiple payment gateways (Stripe, PayPal, etc.). Traffic is round-robin, but one gateway might be slow or degraded. You want to automatically route less traffic to slow gateways.

**Solution:** Record response times per gateway. Compute weighted routing based on recent performance.

### Recording Response Times

```lisp
(defun call-gateway (gateway-id request)
  "Call a payment gateway and record its response time."
  (let ((start (get-internal-real-time)))
    ;; Make the actual call
    (multiple-value-prog1
        (send-request gateway-id request)
      ;; Record elapsed time in milliseconds
      (let ((elapsed-ms (/ (- (get-internal-real-time) start)
                           (/ internal-time-units-per-second 1000))))
        (record! (format nil "gateway.~a.response-ms" gateway-id)
                 (float elapsed-ms))))))
```

**Key points:**

- Metric name includes gateway ID: `gateway.stripe.response-ms`
- Use `float` to ensure numeric values (not ratios)
- Time measurement wraps the actual call

### Computing Routing Weights

```lisp
(defun gateway-avg-response (gateway-id &key (window 300))
  "Average response time for gateway over last WINDOW seconds."
  (or (aggregate *metrics*
                 (format nil "gateway.~a.response-ms" gateway-id)
                 :window window
                 :function :average)
      ;; Default if no data yet
      500.0))

(defun compute-gateway-weights (gateway-ids)
  "Return alist of (gateway-id . weight) based on response times.
   Faster gateways get higher weights."
  (let* ((times (mapcar #'gateway-avg-response gateway-ids))
         ;; Invert: slower = lower weight
         (inv-times (mapcar (lambda (t) (/ 1.0 (max t 1.0))) times))
         ;; Normalize to sum to 1.0
         (total (reduce #'+ inv-times)))
    (mapcar (lambda (gw inv-t)
              (cons gw (/ inv-t total)))
            gateway-ids inv-times)))
```

**How the math works:**

1. Get average response time for each gateway (last 5 minutes)
2. Invert: 100ms → 0.01, 500ms → 0.002 (faster = higher score)
3. Normalize so weights sum to 1.0
4. A gateway with 100ms gets 5x the weight of one with 500ms

### Weighted Selection

```lisp
(defun select-gateway (weights)
  "Randomly select a gateway based on weights.
   WEIGHTS is alist of (gateway-id . probability)."
  (let ((roll (random 1.0))
        (cumulative 0.0))
    (dolist (pair weights)
      (incf cumulative (cdr pair))
      (when (< roll cumulative)
        (return (car pair))))
    ;; Fallback to first
    (caar weights)))

(defun route-payment (request)
  "Route payment to best available gateway."
  (let* ((gateways '("stripe" "paypal" "braintree"))
         (weights (compute-gateway-weights gateways))
         (chosen (select-gateway weights)))
    (format t "~&Routing to ~a (weights: ~a)~%" chosen weights)
    (call-gateway chosen request)))
```

### Putting It Together

```lisp
(defun payment-processor ()
  "Payment processing with adaptive routing."
  (with-store ("payments")
    ;; Process payments
    (loop
      (let ((request (get-next-payment)))
        (route-payment request))
      (sleep 0.1))))
```

**What happens over time:**

- Initially, all gateways get equal traffic (no data)
- As data accumulates, weights adjust
- If Stripe degrades to 800ms while others are 200ms, Stripe gets ~1/4 the traffic
- When Stripe recovers, its weight automatically increases

---

## Use Case 3: Agent Hierarchies

**Problem:** You have logical "agents" that spawn worker threads. You want to track metrics at the agent level (total work done) while allowing workers to share the same store.

**Solution:** Use `with-store` for the agent, `spawn` for workers. Workers inherit the agent's store.

### The Agent

```lisp
(defun booking-agent ()
  "Agent that processes booking requests with worker pool."
  (with-store ("booking-agent")
    ;; Record agent startup
    (record! "started-at" (get-universal-time))
    (record! "status" 1)

    ;; Spawn worker threads - they inherit *metrics*
    (let ((workers (loop for i below 4
                         collect (spawn (lambda ()
                                          (booking-worker i))
                                        :name (format nil "booking-worker-~d" i)))))

      ;; Agent main loop: coordinate and monitor
      (loop
        (record! "heartbeat" (get-universal-time))

        ;; Log aggregate stats
        (let ((processed (aggregate *metrics* "bookings-processed"
                                    :window 60 :function :sum)))
          (when processed
            (format t "~&Bookings processed last minute: ~a~%" processed)))

        (sleep 5)))))
```

**Why `spawn` matters:**

- `spawn` captures the current `*metrics*` binding
- Workers inherit the agent's store, not their own
- All workers write to "booking-agent" store
- Agent can aggregate across all workers

### The Workers

```lisp
(defun booking-worker (worker-id)
  "Worker that processes individual bookings."
  ;; Note: *metrics* is already bound to agent's store via spawn
  (loop
    (record! "heartbeat" (get-universal-time))

    (let ((booking (get-next-booking)))
      (when booking
        ;; All workers contribute to same counter
        (process-booking booking)
        (record! "bookings-processed" 1)

        ;; Track individual worker's contribution (optional)
        (record! (format nil "worker-~d-processed" worker-id) 1)))

    (sleep 0.1)))
```

**Shared vs. individual metrics:**

- `"bookings-processed"` - all workers increment, agent sees total
- `"worker-0-processed"` - only worker 0 increments, useful for balance checking

### Nested Override

Sometimes a worker needs its own private store:

```lisp
(defun special-worker ()
  "Worker with both shared and private metrics."
  ;; Inherited *metrics* from agent
  (record! "heartbeat" (get-universal-time))

  ;; Create nested store for private data
  (with-store ("special-worker-private")
    ;; This goes to private store
    (record! "sensitive-metric" 123)

    ;; But we can still write to parent explicitly
    (record (store-parent *metrics*) "heartbeat" (get-universal-time))))
```

---

## Use Case 4: Global Metrics

**Problem:** Some metrics apply to the entire Lisp image, not any specific component. Examples: total requests, GC statistics, connection pool utilization.

**Solution:** Use `*global-metrics*` for image-wide data.

### Initialization

```lisp
(defun start-application ()
  "Initialize application with global metrics."
  ;; Initialize global store first
  (initialize-global-metrics)

  ;; Record startup
  (record-global! "started-at" (get-universal-time))
  (record-global! "version" 1.0)

  ;; Start components...
  (start-web-server)
  (start-workers))
```

### Recording Global Metrics

```lisp
(defun handle-http-request (request)
  "Handle web request with global tracking."
  ;; Increment global request counter
  (record-global! "http-requests-total" 1)

  (let ((start (get-internal-real-time)))
    (prog1
        (process-request request)
      (let ((elapsed (/ (- (get-internal-real-time) start)
                        (/ internal-time-units-per-second 1000))))
        (record-global! "http-response-ms" elapsed)))))
```

### Querying Global State

```lisp
(defun system-health-check ()
  "Check overall system health."
  (let ((requests-per-min (aggregate *global-metrics*
                                     "http-requests-total"
                                     :window 60
                                     :function :count))
        (avg-latency (aggregate *global-metrics*
                               "http-response-ms"
                               :window 60
                               :function :average)))
    (format t "~&System: ~a req/min, ~,1fms avg latency~%"
            (or requests-per-min 0)
            (or avg-latency 0.0))))
```

---

## Use Case 5: Background Archival

**Problem:** vigil stores are in-memory. Data is lost on restart. You want to preserve historical data for post-mortem analysis or trending.

**Solution:** The SQLite archiver periodically dumps all stores to disk in the background.

### Starting the Archiver

```lisp
;; Load archiver module
(ql:quickload :vigil/archiver)

(defun start-with-archival ()
  "Start application with background archiving."
  (initialize-global-metrics)

  ;; Start archiver: dump every 5 minutes to /var/log/metrics.db
  (start-archiver :db-path "/var/log/metrics.db"
                  :interval 300)

  ;; Start rest of application
  (start-application))
```

### Graceful Shutdown

```lisp
(defun shutdown ()
  "Clean shutdown with final archive."
  ;; Stop archiver (waits for current dump to finish)
  (stop-archiver :wait t)

  ;; Stop other components
  (stop-application))
```

### Manual Snapshot

```lisp
(defun emergency-dump ()
  "Immediate snapshot of all metrics."
  (archive-all-stores
    :backend (make-instance 'rrd:sqlite-backend
               :db-path "/tmp/emergency-dump.db")))
```

**Important notes:**

- The archiver runs in a dedicated background thread
- Hot path (recording) never blocks on disk I/O
- Archives are eventually consistent, not real-time
- Use for offline analysis, not real-time queries

---

## Summary

| Use Case | Key Functions | Pattern |
|----------|---------------|---------|
| Thread health | `with-store`, `find-stores`, `last-value` | Worker heartbeats, supervisor scans |
| Adaptive routing | `record!`, `aggregate`, weighted selection | Track response times, compute weights |
| Agent hierarchy | `spawn`, shared `*metrics*` | Agent creates store, workers inherit |
| Global metrics | `record-global!`, `*global-metrics*` | Image-wide counters and gauges |
| Background archival | `start-archiver`, `stop-archiver` | Periodic SQLite dump |
