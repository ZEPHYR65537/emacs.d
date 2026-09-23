;;; init-portability-test.el --- Offline migration regressions -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
;; These bindings must remain dynamic on Emacs 28, which predates treesit.
(defvar treesit-extra-load-path)
(defvar treesit-load-name-override-list)
(defvar major-mode-remap-alist)
(defvar sanityinc/mmix-bin-directory)
(defconst sanityinc/portability-test-root
  (file-name-as-directory
   (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name)))))
(add-to-list 'load-path (expand-file-name "lisp" sanityinc/portability-test-root))
(require 'init-local-packages)
(load (expand-file-name "scripts/bootstrap-local-packages.el" sanityinc/portability-test-root) nil t)

(defmacro sanityinc/with-portability-fixture (&rest body)
  "Run BODY under a disposable configuration directory, including spaces."
  (declare (indent 0) (debug t))
  `(let* ((fixture (file-name-as-directory (make-temp-file "emacs-portability-test- " t)))
          (user-emacs-directory fixture)
          (load-path (copy-sequence load-path))
          (auto-mode-alist (copy-tree auto-mode-alist))
          (after-load-alist (copy-tree after-load-alist))
          (exec-path (copy-sequence exec-path))
          (process-environment (copy-sequence process-environment)))
     (unwind-protect (progn ,@body)
       ;; Only remove the unique directory created by this fixture.
       (when (and (file-in-directory-p fixture temporary-file-directory)
                  (string-prefix-p "emacs-portability-test- "
                                   (file-name-nondirectory (directory-file-name fixture))))
         (delete-directory fixture t)))))

(defun sanityinc/test-local-entry-files ()
  "Create entry files that fail if a module eagerly evaluates them."
  (dolist (entry sanityinc/local-package-specs)
    (let ((directory (sanityinc/local-package-directory (car entry))))
      (make-directory directory t)
      (with-temp-file (expand-file-name (plist-get (cdr entry) :library) directory)
        (insert "(error \"Package eagerly loaded\")\n")))))

(ert-deftest sanityinc/portability-missing-packages-dont-break-startup ()
  (sanityinc/with-portability-fixture
    (let ((initial-modes (copy-tree auto-mode-alist))
          (initial-path (getenv "PATH")))
      (cl-letf (((symbol-function 'maybe-require-package)
                 (lambda (&rest _) (ert-fail "Missing NOV should not install dependencies"))))
        (dolist (module '(init-comb-grid init-mmix init-nov init-static-site))
          (load (symbol-name module) nil t)))
      (should (equal initial-modes auto-mode-alist))
      (should (equal initial-path (getenv "PATH"))))))

(ert-deftest sanityinc/portability-packages-load-on-demand ()
  (sanityinc/with-portability-fixture
    (sanityinc/test-local-entry-files)
    (let ((emacs-version "31.1"))
      (cl-letf (((symbol-function 'maybe-require-package) (lambda (&rest _) t))
                ((symbol-function 'call-process)
                 (lambda (&rest _) (ert-fail "Startup must not invoke Git or native tools")))
                ((symbol-function 'make-network-process)
                 (lambda (&rest _) (ert-fail "Local adapters must not open connections"))))
        (dolist (module '(init-comb-grid init-mmix init-nov init-static-site))
          (load (symbol-name module) nil t))))
    (dolist (entry '((comb-grid-new . "comb-grid-mode") (nov-mode . "nov")
                     (mmix-mode . "mmix-mode") (static-site-build . "static-site")))
      (should (autoloadp (symbol-function (car entry))))
      (should (equal (nth 1 (symbol-function (car entry))) (cdr entry))))))

(ert-deftest sanityinc/portability-minimum-version-is-enforced ()
  (sanityinc/with-portability-fixture
    (sanityinc/test-local-entry-files)
    (let ((emacs-version "28.1"))
      (should-not (sanityinc/enable-local-package 'comb-grid))
      (should (sanityinc/enable-local-package 'static-site)))
    (should-not (member (sanityinc/local-package-directory 'comb-grid) load-path))))

(ert-deftest sanityinc/portability-mmix-path-is-idempotent ()
  (sanityinc/with-portability-fixture
    (sanityinc/test-local-entry-files)
    (let ((sanityinc/mmix-bin-directory (expand-file-name "tools with spaces" fixture)))
      (make-directory sanityinc/mmix-bin-directory)
      (load "init-mmix" nil t)
      (let ((first-path (getenv "PATH")) (first-exec (copy-sequence exec-path)))
        (load "init-mmix" nil t)
        (should (equal first-path (getenv "PATH")))
        (should (equal first-exec exec-path))))))

(ert-deftest sanityinc/portability-unloadable-grammar-never-remaps ()
  (sanityinc/with-portability-fixture
    (let ((treesit-extra-load-path nil)
          (treesit-load-name-override-list nil)
          (major-mode-remap-alist nil))
      (make-directory (expand-file-name "tree-sitter" fixture))
      (with-temp-file (expand-file-name "tree-sitter/libtree-sitter-zig.dll" fixture)
        (insert "incompatible native library"))
      (cl-letf (((symbol-function 'zig-ts-mode) #'ignore)
                ((symbol-function 'treesit-ready-p) (lambda (&rest _) nil)))
        (load "init-treesitter" nil t)
        (should-not (assq 'zig-mode major-mode-remap-alist))))))

(ert-deftest sanityinc/portability-loadable-grammar-keeps-remapping ()
  (sanityinc/with-portability-fixture
    (let ((treesit-extra-load-path nil)
          (treesit-load-name-override-list nil)
          (major-mode-remap-alist nil))
      (make-directory (expand-file-name "tree-sitter" fixture))
      (with-temp-file (expand-file-name "tree-sitter/libtree-sitter-zig.so" fixture))
      (cl-letf (((symbol-function 'zig-ts-mode) #'ignore)
                ((symbol-function 'treesit-ready-p) (lambda (lang &rest _) (eq lang 'zig))))
        (load "init-treesitter" nil t)
        (should (eq (cdr (assq 'zig-mode major-mode-remap-alist)) 'zig-ts-mode))))))

(defun sanityinc/test-upstream-entry ()
  "Create a real local Git source and return its pinned manifest entry."
  (let ((source (expand-file-name "upstream source" user-emacs-directory)))
    (make-directory source)
    (sanityinc/bootstrap--git! source "init")
    (with-temp-file (expand-file-name "demo.el" source) (insert ";;; original\n"))
    (sanityinc/bootstrap--git! source "add" "demo.el")
    (sanityinc/bootstrap--git! source "-c" "user.name=Migration Test"
                              "-c" "user.email=test@example.invalid" "commit" "-m" "fixture")
    (list 'demo :directory "demo" :library "demo.el" :emacs "28.1" :url source
          :revision (sanityinc/bootstrap--git! source "rev-parse" "HEAD"))))

(ert-deftest sanityinc/portability-restore-preserves-dirty-checkout ()
  (skip-unless (executable-find "git"))
  (sanityinc/with-portability-fixture
    (let* ((entry (sanityinc/test-upstream-entry))
           (target (expand-file-name "pkg/demo/demo.el" fixture)))
      (sanityinc/bootstrap--package entry)
      (with-temp-file target (insert ";;; personal edit\n"))
      (sanityinc/bootstrap--package entry)
      (with-temp-buffer
        (insert-file-contents target)
        (should (equal (buffer-string) ";;; personal edit\n"))))))

(ert-deftest sanityinc/portability-restore-refuses-unmanaged-directory ()
  (sanityinc/with-portability-fixture
    (make-directory (expand-file-name "pkg/demo" fixture) t)
    (should-error (sanityinc/bootstrap--package
                   '(demo :directory "demo" :library "demo.el" :revision "unused")))
    (should (file-directory-p (expand-file-name "pkg/demo" fixture)))))

(ert-deftest sanityinc/portability-restore-refuses-different-revision ()
  (skip-unless (executable-find "git"))
  (sanityinc/with-portability-fixture
    (let* ((entry (sanityinc/test-upstream-entry))
           (directory (expand-file-name "pkg/demo" fixture)))
      (sanityinc/bootstrap--package entry)
      (let ((original (sanityinc/bootstrap--git! directory "rev-parse" "HEAD")))
        (setf (plist-get (cdr entry) :revision) (make-string 40 ?0))
        (should-error (sanityinc/bootstrap--package entry))
        (should (equal original (sanityinc/bootstrap--git! directory "rev-parse" "HEAD")))))))

(ert-deftest sanityinc/portability-maintained-patch-is-repeatable ()
  (skip-unless (executable-find "git"))
  (sanityinc/with-portability-fixture
    (let* ((entry (sanityinc/test-upstream-entry))
           (source (plist-get (cdr entry) :url))
           (patch (expand-file-name "fix.patch" fixture))
           (target (expand-file-name "pkg/demo" fixture)))
      (with-temp-file (expand-file-name "demo.el" source) (insert ";;; corrected\n"))
      (with-temp-file patch (insert (sanityinc/bootstrap--git! source "diff") "\n"))
      (setf (plist-get (cdr entry) :patch) "fix.patch")
      (sanityinc/bootstrap--package entry)
      (sanityinc/bootstrap--package entry)
      (should (equal 0 (car (sanityinc/bootstrap--git target "apply" "--reverse" "--check" patch)))))))

(ert-deftest sanityinc/portability-patch-refuses-unrelated-local-edits ()
  (skip-unless (executable-find "git"))
  (sanityinc/with-portability-fixture
    (let* ((entry (sanityinc/test-upstream-entry))
           (source (plist-get (cdr entry) :url))
           (patch (expand-file-name "fix.patch" fixture))
           (target (expand-file-name "pkg/demo" fixture)))
      (sanityinc/bootstrap--package entry)
      (with-temp-file (expand-file-name "demo.el" source) (insert ";;; corrected\n"))
      (with-temp-file patch (insert (sanityinc/bootstrap--git! source "diff") "\n"))
      (with-temp-file (expand-file-name "personal.txt" target) (insert "keep me"))
      (setf (plist-get (cdr entry) :patch) "fix.patch")
      (should-error (sanityinc/bootstrap--package entry))
      (should (file-exists-p (expand-file-name "personal.txt" target)))
      (with-temp-buffer
        (insert-file-contents (expand-file-name "demo.el" target))
        (should (equal (buffer-string) ";;; original\n"))))))
