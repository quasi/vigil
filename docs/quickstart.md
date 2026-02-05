# Quickstart

Get vigil working in 5 minutes.

## Setup

```lisp
(ql:quickload :vigil)
(use-package :vigil)
```

## Record and Query a Metric

```lisp
;; Create a store and record values
(with-store ("demo")
  (record! "temperature" 22.5)
  (record! "temperature" 23.1)
  (record! "temperature" 22.8)

  ;; Query the most recent value
  (last-value *metrics* "temperature"))
;; => 22.8
```

## Check a Threshold

```lisp
(with-store ("demo")
  ;; Record some response times
  (dotimes (i 10)
    (record! "response-ms" (+ 100 (random 50))))

  ;; Is average response time over 120ms?
  (exceeds? *metrics* "response-ms" 120
            :window 60
            :function :average))
;; => T or NIL
```

## Find Stores by Condition

```lisp
;; Start some workers
(dotimes (i 3)
  (bt:make-thread
    (lambda ()
      (with-store ((format nil "worker-~d" i))
        (loop
          (record! "heartbeat" (get-universal-time))
          (sleep 1))))
    :name (format nil "worker-~d" i)))

;; Give them time to register
(sleep 2)

;; Find all worker stores
(find-stores (lambda (s) (search "worker" (store-name s))))
;; => (#<STORE "worker-0"> #<STORE "worker-1"> #<STORE "worker-2">)
```

## What's Next

- [Use Cases](tutorials/use-cases.md) - Real-world patterns with full explanations
- [API Reference](reference.md) - All functions documented
