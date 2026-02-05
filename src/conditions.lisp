(in-package #:vigil)

(define-condition vigil-error (error)
  ()
  (:documentation "Base condition for vigil errors"))

(define-condition store-not-found (vigil-error)
  ((store-name :initarg :store-name :reader condition-store-name))
  (:report (lambda (c s)
             (format s "Store not found: ~a" (condition-store-name c))))
  (:documentation "Signaled when a store lookup fails"))

(define-condition no-active-store (vigil-error)
  ()
  (:report (lambda (c s)
             (declare (ignore c))
             (format s "No active store: *metrics* is nil")))
  (:documentation "Signaled when record! called without active *metrics*"))

(defintent vigil-error
  :feature vigil-core
  :role "Base condition type"
  :purpose "Enable typed error handling for vigil operations")

(defintent store-not-found
  :feature vigil-registry
  :role "Signal failed store lookup"
  :purpose "Distinguish missing store from other errors")

(defintent no-active-store
  :feature vigil-scoping
  :role "Signal missing dynamic binding"
  :purpose "Catch record! calls outside with-store scope")
