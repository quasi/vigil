(in-package #:vigil)

(defclass/i store ()
  ((name :initarg :name
         :reader store-name
         :type string
         :documentation "Unique identifier for registry lookup")
   (lock :initform (bt:make-lock "vigil-store")
         :reader store-lock
         :documentation "Coarse-grained lock for thread safety")
   (parent :initarg :parent
           :initform nil
           :reader store-parent
           :type (or null store)
           :documentation "Parent store for hierarchy tracking")
   (created-at :initform (get-universal-time)
               :reader store-created-at
               :type integer
               :documentation "Creation timestamp")
   (backend :initform (make-instance 'rrd:memory-backend)
            :reader store-backend
            :documentation "Underlying trivial-rrd storage"))
  (:feature vigil-store)
  (:role "Thread-safe metrics container")
  (:purpose "Wrap memory-backend with locking and identity"))

(defun/i make-store (name &key parent)
  "Create a new store named NAME. NAME must be a non-empty string; it is used as the registry key.
   PARENT, if supplied, must be a store instance; used for hierarchy tracking only.
   Does not register the store — call register-store explicitly, or use with-store."
  (:feature vigil-store)
  (:role "Store constructor")
  (:purpose "Create store instance without registration")
  (make-instance 'store :name name :parent parent))
