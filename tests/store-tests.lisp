(in-package #:vigil-tests)

(in-suite store-tests)

(test store-creation
  "A store can be created with a name"
  (let ((store (vigil::make-store "test-store")))
    (is (equal "test-store" (store-name store)))
    (is (not (null (vigil::store-lock store))))
    (is (not (null (vigil::store-backend store))))
    (is (null (store-parent store)))
    (is (integerp (store-created-at store)))))

(test store-with-parent
  "A store can have a parent"
  (let* ((parent (vigil::make-store "parent"))
         (child (vigil::make-store "child" :parent parent)))
    (is (eq parent (store-parent child)))))
