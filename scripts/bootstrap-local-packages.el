;;; bootstrap-local-packages.el --- Explicit dependency restoration -*- lexical-binding: t; -*-
;;; Commentary:
;; emacs -Q --batch -l scripts/bootstrap-local-packages.el -f sanityinc/bootstrap-local-packages
;; Never reset, update or delete an existing checkout.
;;; Code:

(require 'subr-x)
(setq user-emacs-directory
      (file-name-as-directory
       (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name)))))
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))
(require 'init-local-package-manifest)

(defun sanityinc/bootstrap--git (directory &rest arguments)
  "Run Git ARGUMENTS in DIRECTORY, returning (STATUS . OUTPUT)."
  (let ((default-directory (file-name-as-directory directory))
        (process-environment (copy-sequence process-environment)))
    (setenv "GIT_TERMINAL_PROMPT" "0")
    (with-temp-buffer
      (let ((status (apply #'call-process "git" nil t nil arguments)))
        (cons status (string-trim (buffer-string)))))))

(defun sanityinc/bootstrap--git! (directory &rest arguments)
  "Run Git ARGUMENTS in DIRECTORY, signaling an error on failure."
  (let ((result (apply #'sanityinc/bootstrap--git directory arguments)))
    (unless (equal (car result) 0)
      (error "Git %s failed: %s" (car arguments) (cdr result)))
    (cdr result)))

(defun sanityinc/bootstrap--package (entry)
  "Restore manifest ENTRY without replacing existing work."
  (let* ((name (car entry)) (spec (cdr entry))
         (directory (expand-file-name (concat "pkg/" (plist-get spec :directory))
                                      user-emacs-directory))
         (revision (plist-get spec :revision))
         (patch (when-let* ((path (plist-get spec :patch)))
                  (expand-file-name path user-emacs-directory))))
    (unless (file-exists-p directory)
      (make-directory (file-name-directory directory) t)
      (sanityinc/bootstrap--git! user-emacs-directory "clone" "--no-checkout" "--"
                                (plist-get spec :url) directory)
      (sanityinc/bootstrap--git! directory "checkout" "--detach" revision))
    (unless (file-exists-p (expand-file-name ".git" directory))
      (error "%s exists without its own Git repository; left untouched" directory))
    (unless (equal revision (sanityinc/bootstrap--git! directory "rev-parse" "HEAD"))
      (error "%s is at another revision; left untouched. Review against %s" name revision))
    (when patch
      (unless (file-readable-p patch) (error "Missing patch: %s" patch))
      ;; Already applied is success, including on repeated restores.
      (unless (equal 0 (car (sanityinc/bootstrap--git
                            directory "apply" "--reverse" "--check" patch)))
        (unless (string-empty-p (sanityinc/bootstrap--git! directory "status" "--porcelain"))
          (error "%s has local edits and needs its patch; left untouched" name))
        (sanityinc/bootstrap--git! directory "apply" "--check" patch)
        (sanityinc/bootstrap--git! directory "apply" patch)))
    (unless (file-readable-p (expand-file-name (plist-get spec :library) directory))
      (error "%s is missing its entry library; inspect the checkout" name))
    (message "%s: ready at %s" name (substring revision 0 12))))

(defun sanityinc/bootstrap-local-packages ()
  "Restore missing checkouts; verify existing ones without updating them.
Apply the recorded patch only to a clean checkout at its recorded revision.
Keep all existing local edits.  Restart Emacs after restoring skipped packages."
  (interactive)
  (unless (executable-find "git") (user-error "Install Git and put it on PATH first"))
  (let (errors)
    (dolist (entry sanityinc/local-package-specs)
      (condition-case err
          (sanityinc/bootstrap--package entry)
        (error (push (format "%s: %s" (car entry) (error-message-string err)) errors))))
    (if errors
        (error "Restore incomplete:\n%s" (string-join (nreverse errors) "\n"))
      (message "Local packages restored. Restart Emacs to enable them."))))

(provide 'bootstrap-local-packages)
;;; bootstrap-local-packages.el ends here
