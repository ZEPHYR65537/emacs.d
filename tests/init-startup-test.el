;;; init-startup-test.el --- Offline startup regressions -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(defconst jdd/startup-test-root
  (file-name-as-directory
   (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name)))))
(add-to-list 'load-path (expand-file-name "lisp" jdd/startup-test-root))
(require 'init-local-packages)
(defvar sanityinc/personal-modules)
(defvar gnus-before-startup-hook)

(ert-deftest jdd/mail-is-autoloaded-without-startup-work ()
  (let ((sanityinc/personal-modules '(init-mail))
        (global-map (copy-keymap global-map))
        (gnus-before-startup-hook nil))
    (define-key global-map (kbd "C-c m") nil)
    (cl-letf (((symbol-function 'maybe-require-package) (lambda (&rest _) nil))
              ((symbol-function 'read-passwd) (lambda (&rest _) (ert-fail "Startup asked for a secret")))
              ((symbol-function 'make-network-process) (lambda (&rest _) (ert-fail "Startup connected"))))
      (load "init-personal" nil t))
    (dolist (feature '(init-mail init-mail-vault gnus nnimap smtpmail))
      (should-not (featurep feature)))
    (should (autoloadp (symbol-function 'jdd/mail)))
    (should (eq (lookup-key global-map (kbd "C-c m")) 'jdd/mail))
    (should (memq 'jdd/mail-setup gnus-before-startup-hook))))

(ert-deftest jdd/zig-without-grammar-uses-regular-mode ()
  (let ((auto-mode-alist '(("\\.zig\\'" . zig-ts-mode))))
    (cl-letf (((symbol-function 'maybe-require-package) (lambda (&rest _) t))
              ((symbol-function 'require-package) (lambda (&rest _) t))
              ((symbol-function 'treesit-ready-p) (lambda (&rest _) nil)))
      (load "init-zig" nil t))
    (should (eq (assoc-default "example.zig" auto-mode-alist #'string-match) 'zig-mode))
    (should (eq (assoc-default "example.zon" auto-mode-alist #'string-match) 'zig-mode))))

;;; init-startup-test.el ends here
