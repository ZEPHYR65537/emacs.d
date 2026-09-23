;;; init-local-packages.el --- Lightweight local package loading -*- lexical-binding: t; -*-
;;; Commentary:
;; Only check versions and files at startup.  Restore and diagnostics are manual.
;;; Code:

(require 'init-local-package-manifest)

(defun sanityinc/local-package-directory (name)
  "Return the directory for manifest package NAME."
  (let ((spec (cdr (assq name sanityinc/local-package-specs))))
    (unless spec (error "Unknown local package: %s" name))
    (expand-file-name (concat "pkg/" (plist-get spec :directory)) user-emacs-directory)))

(defun sanityinc/enable-local-package (name)
  "Add NAME to `load-path' when usable, or explain why it was skipped."
  (let* ((spec (cdr (assq name sanityinc/local-package-specs)))
         (directory (sanityinc/local-package-directory name))
         (minimum (plist-get spec :emacs)))
    (cond
     ((version< emacs-version minimum)
      (message "Skipping %s: requires Emacs %s" name minimum) nil)
     ((not (file-readable-p (expand-file-name (plist-get spec :library) directory)))
      (message "Skipping %s: run M-x sanityinc/bootstrap-local-packages" name) nil)
     (t (add-to-list 'load-path directory) t))))

(autoload 'sanityinc/bootstrap-local-packages
  (expand-file-name "scripts/bootstrap-local-packages.el" user-emacs-directory) nil t)
(autoload 'sanityinc/config-doctor
  (expand-file-name "scripts/config-doctor.el" user-emacs-directory) nil t)

(provide 'init-local-packages)
;;; init-local-packages.el ends here
