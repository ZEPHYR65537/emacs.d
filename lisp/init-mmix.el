;;; init-mmix.el --- Local MMIX tools and debugger -*- lexical-binding: t -*-
;;; Commentary:
;; Follow the local Git-package convention used by init-comb-grid.
;; Package checkout: ~/.emacs.d/pkg/mmix-mode
;; Native tools:     ~/.emacs.d/pkg/mmix
;; See docs/migration.md for native tools on each platform.
;; The manifest preserves the shell-free mmotype patch.
;;; Code:

(require 'cl-lib)
(require 'init-local-packages)

(defcustom sanityinc/mmix-bin-directory
  (file-name-as-directory (expand-file-name "pkg/mmix" user-emacs-directory))
  "Optional directory containing native MMIX tools for this machine."
  :type 'directory
  :group 'environment)

(when (sanityinc/enable-local-package 'mmix-mode)
  (when (file-directory-p sanityinc/mmix-bin-directory)
    (let ((directory (file-name-as-directory (expand-file-name sanityinc/mmix-bin-directory))))
      (add-to-list 'exec-path directory)
      (unless (member directory (parse-colon-path (getenv "PATH")))
        (setenv "PATH" (concat directory path-separator (getenv "PATH"))))))

  (autoload 'mmix-mode "mmix-mode" "Edit MMIXAL assembly." t)
  (autoload 'mmix-interactive-run "mmix-interactive" "Debug a compiled MMIX program." t)
  (add-to-list 'auto-mode-alist '("\\.mms\\'" . mmix-mode))

  (defun sanityinc/mmix-assemble ()
    "Save and assemble the current MMIX source without invoking a shell."
    (interactive)
    (unless buffer-file-name (user-error "Save the source file first"))
    (require 'mmix-mode)
    (unless (executable-find mmix-mmixal-program)
      (user-error "Install %s on PATH or in %s; see docs/migration.md"
                  mmix-mmixal-program sanityinc/mmix-bin-directory))
    (require 'compile)
    (save-buffer)
    (let* ((source buffer-file-name)
           (directory default-directory)
           (output (get-buffer-create "*MMIX Assembly*"))
           (args (append (when mmix-mmixal-expand-flag '("-x"))
                         (list source)))
           status)
      (with-current-buffer output
        (let ((inhibit-read-only t))
          (erase-buffer)
          (compilation-mode)
          (setq default-directory directory)
          (setq status (apply #'call-process mmix-mmixal-program nil t nil args))
          (goto-char (point-max))
          (insert (format "\nMMIX assembly finished: %s\n" status))))
      (unless (equal status 0)
        (display-buffer output)
        (user-error "Assembly failed; see *MMIX Assembly*"))
      (message "Assembled %s" (file-name-nondirectory source))))

  (with-eval-after-load 'mmix-mode
    (define-key mmix-mode-map (kbd "C-c C-c") #'sanityinc/mmix-assemble)
    (define-key mmix-mode-map (kbd "C-c C-d") #'mmix-interactive-run)))

(provide 'init-mmix)
;;; init-mmix.el ends here
