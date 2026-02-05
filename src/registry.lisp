(in-package #:vigil)

;;; Global registry state

(defvar *store-registry* (make-hash-table :test 'equal)
  "Maps store names to store objects.")

(defvar *registry-lock* (bt:make-lock "vigil-registry")
  "Lock for registry modifications.")

;;; Internal functions

(defun/i clear-registry ()
  "Clear all stores from registry. For testing only."
  (:feature vigil-registry)
  (:role "Test helper")
  (:purpose "Reset registry state between tests")
  (bt:with-lock-held (*registry-lock*)
    (clrhash *store-registry*)))

(defun/i register-store (store)
  "Add store to the global registry."
  (:feature vigil-registry)
  (:role "Store registration")
  (:purpose "Make store discoverable by supervisor")
  (bt:with-lock-held (*registry-lock*)
    (setf (gethash (store-name store) *store-registry*) store))
  store)

(defun/i unregister-store (store)
  "Remove store from the global registry."
  (:feature vigil-registry)
  (:role "Store cleanup")
  (:purpose "Remove store when scope exits")
  (bt:with-lock-held (*registry-lock*)
    (remhash (store-name store) *store-registry*))
  store)

;;; Public API

(defun/i list-stores ()
  "Return list of all registered store names."
  (:feature vigil-registry)
  (:role "Store enumeration")
  (:purpose "Enable supervisor to discover all active stores")
  (bt:with-lock-held (*registry-lock*)
    (loop for name being the hash-keys of *store-registry*
          collect name)))

(defun/i get-store (name)
  "Get store by name, or NIL if not found."
  (:feature vigil-registry)
  (:role "Store lookup")
  (:purpose "Retrieve specific store for querying")
  (bt:with-lock-held (*registry-lock*)
    (gethash name *store-registry*)))

(defun/i find-stores (predicate)
  "Return list of stores matching predicate."
  (:feature vigil-registry)
  (:role "Filtered store query")
  (:purpose "Find stores by arbitrary condition")
  (bt:with-lock-held (*registry-lock*)
    (loop for store being the hash-values of *store-registry*
          when (funcall predicate store)
          collect store)))

(defun/i map-stores (function)
  "Apply function to each store, return results."
  (:feature vigil-registry)
  (:role "Store iteration")
  (:purpose "Apply operation across all stores")
  (bt:with-lock-held (*registry-lock*)
    (loop for store being the hash-values of *store-registry*
          collect (funcall function store))))
