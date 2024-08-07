(in-package #:org.shirakumo.com-on)

(defvar *initialized* NIL)

(defun create (class instance)
  (init)
  (with-deref (com :pointer)
    (cffi:foreign-funcall "CoCreateInstance" guid class :pointer (cffi:null-pointer) com:dword com:CLSCTX-ALL
                          guid instance :pointer com com:hresult)))

(defun release (pointer)
  (cffi:foreign-funcall-pointer
   (cffi:mem-aref (com:vtbl pointer) :pointer 2)
   ()
   :pointer pointer
   :unsigned-long))

(defmacro with-com ((var init) &body body)
  `(let ((,var ,init))
     (unwind-protect
          (progn ,@body)
       (release ,var))))

(defmacro define-comfun ((struct method &key options (conc-name NIL cnp)) return-type &body args)
  (let* ((*print-case* (readtable-case *readtable*))
         (structg (make-symbol (symbol-name struct)))
         (std-name (intern (format NIL "~a-~a" struct method)))
         (name (cond ((not cnp)
                      std-name)
                     ((null conc-name)
                      method)
                     (T
                      (intern (format NIL "~a~a" conc-name method)))))
         (documentation (when (stringp (car args))
                          (pop args))))
    `(progn
       (declaim (inline ,name))
       (defun ,name (,structg ,@(mapcar #'first args))
         ,@(when documentation `(,documentation))
         (cffi:foreign-funcall-pointer
          (,(intern (format NIL "%~a" std-name))
           (com:vtbl ,structg))
          ,options
          :pointer ,structg
          ,@(loop for (name type) in args
                  collect type collect name)
          ,return-type)))))

(defmacro define-comstruct (name &body methods)
  (destructuring-bind (name &key bare (conc-name NIL cnp)) (if (listp name) name (list name))
    (let* ((documentation (when (stringp (car methods))
                            (pop methods)))
           (methods (if bare
                        methods
                        (list* `(query-interface (uid guid) (out :pointer))
                               `(add-ref :unsigned-long)
                               `(release :unsigned-long)
                               methods)))
           (conc-name (if cnp conc-name (format NIL "~a-" name))))
      `(progn
         (cffi:defcstruct (,name :conc-name ,(format NIL "%~a-" name))
           ,@(when documentation `(,documentation))
           ,@(loop for method in methods
                   collect (list (first method) :pointer)))

         ,@(loop for (method return . args) in methods
                 ;; Default to hresult return
                 do (etypecase return
                      ((cons keyword))
                      (cons
                       (push return args)
                       (setf return 'com:hresult))
                      (null
                       (setf return 'com:hresult))
                      (symbol))
                 collect `(define-comfun (,name ,method :conc-name ,conc-name) ,return
                            ,@args))))))

(defun init ()
  (unless *initialized*
    (cffi:load-foreign-library 'com:ole32)
    (check-hresult
     (com:initialize (cffi:null-pointer) :multi-threaded)
     :ok :false :changed-thread-mode)
    (setf *initialized* T)))

(defun shutdown ()
  (when *initialized*
    (com:uninitialize)
    (setf *initialized* NIL)))

(define-comstruct iunknown)

(defun query-interface (object riid)
  (cffi:with-foreign-objects ((out '(:pointer :pointer)))
    (check-hresult (iunknown-query-interface object riid out))
    (cffi:mem-ref out :pointer)))

(declaim (inline add-ref))
(defun add-ref (object)
  (iunknown-add-ref object))
