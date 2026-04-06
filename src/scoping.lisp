(in-package #:vigil)

;;; Special variables

(defvar *global-metrics* nil
  "Image-wide metrics store. Initialized via initialize-global-metrics.")

(defvar *metrics* nil
  "Current scope's metrics store. Dynamically bound by with-store.")

;;; Initialization

(defun/i initialize-global-metrics (&key (step 10) (retention 3600))
  "Initialize the global metrics store. Call once at startup.
   STEP and RETENTION become the image-wide defaults for auto-created metrics
   (sets *default-step* and *default-retention*)."
  (:feature vigil-scoping)
  (:role "Global store initialization")
  (:purpose "Set up image-wide metrics before any recording")
  (setf *default-step* step
        *default-retention* retention
        *global-metrics* (make-store "global"))
  (register-store *global-metrics*)
  *global-metrics*)

;;; with-store macro

(defmacro with-store ((name &key parent) &body body)
  "Bind *metrics* to a new store for the duration of BODY.
   The store is registered on entry and unregistered on exit.
   If parent is not specified and *metrics* is bound, uses current *metrics* as parent."
  (let ((store-var (gensym "STORE")))
    `(let* ((,store-var (make-store ,name
                                    :parent (or ,parent *metrics*)))
            (*metrics* ,store-var))
       (register-store ,store-var)
       (unwind-protect
           (progn ,@body)
         (unregister-store ,store-var)))))

(defintent with-store
  :feature vigil-scoping
  :role "Scoped store binding"
  :purpose "Create store with automatic registration and cleanup"
  :assumptions ((:name-string "NAME evaluates to a string")
                (:body-forms "BODY is a sequence of forms"))
  :failure-modes ((:unwind "Non-local exit still triggers cleanup")))

;;; spawn function

(defun/i spawn (function &key name)
  "Spawn a thread that inherits the current *metrics* binding."
  (:feature vigil-scoping)
  (:role "Thread creation with binding inheritance")
  (:purpose "Ensure child threads share parent's metrics store")
  (:assumptions ((:function "FUNCTION is a zero-argument callable")))
  (let ((parent-metrics *metrics*)
        (parent-global *global-metrics*))
    (bt:make-thread
     (lambda ()
       (let ((*metrics* parent-metrics)
             (*global-metrics* parent-global))
         (funcall function)))
     :name (or name "vigil-worker"))))
