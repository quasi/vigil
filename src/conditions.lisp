(in-package #:vigil)

;;; Error hierarchy

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
  (:documentation "Signaled when record! is called outside a with-store scope"))

(define-condition global-metrics-not-initialized (vigil-error)
  ()
  (:report (lambda (c s)
             (declare (ignore c))
             (format s "Global metrics not initialized; call initialize-global-metrics first")))
  (:documentation "Signaled when record-global! is called before initialize-global-metrics"))

;;; Archiver errors

(define-condition archiver-already-running (vigil-error)
  ()
  (:report (lambda (c s)
             (declare (ignore c))
             (format s "Archiver already running; call stop-archiver first")))
  (:documentation "Signaled when start-archiver is called while the archiver is active"))

(define-condition no-archiver-backend (vigil-error)
  ()
  (:report (lambda (c s)
             (declare (ignore c))
             (format s "No backend provided and archiver not running; supply :backend or start the archiver")))
  (:documentation "Signaled when archive-store or archive-all-stores has no backend available"))

;;; Warning hierarchy

(define-condition vigil-warning (warning)
  ()
  (:documentation "Base warning type for vigil"))

(define-condition archiver-metric-copy-failed (vigil-warning)
  ((store-name  :initarg :store-name  :reader amcf-store-name)
   (metric-name :initarg :metric-name :reader amcf-metric-name)
   (cause       :initarg :cause       :reader amcf-cause))
  (:report (lambda (c s)
             (format s "Archiver: failed to copy ~a/~a: ~a"
                     (amcf-store-name c) (amcf-metric-name c) (amcf-cause c))))
  (:documentation "Signaled (as warning) when copying a single metric to SQLite fails"))

(define-condition archiver-store-failed (vigil-warning)
  ((store-name :initarg :store-name :reader asf-store-name)
   (cause      :initarg :cause      :reader asf-cause))
  (:report (lambda (c s)
             (format s "Archiver: failed to archive store ~a: ~a"
                     (asf-store-name c) (asf-cause c))))
  (:documentation "Signaled (as warning) when archiving an entire store fails"))

(define-condition archiver-loop-error (vigil-warning)
  ((cause :initarg :cause :reader ale-cause))
  (:report (lambda (c s)
             (format s "Archiver: error in archive loop: ~a" (ale-cause c))))
  (:documentation "Signaled (as warning) when an archive-loop iteration fails"))

;;; Telos intent declarations

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
