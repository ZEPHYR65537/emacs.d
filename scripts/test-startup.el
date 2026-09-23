;;; test-startup.el --- Batch startup smoke check -*- lexical-binding: t; -*-
;; Run in an isolated checkout: this performs normal package initialization.
(setq user-emacs-directory
      (file-name-as-directory
       (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name)))))
(setq user-init-file (expand-file-name "init.el" user-emacs-directory))
(setq debug-on-error t)
(load (expand-file-name "early-init.el" user-emacs-directory) nil t)
(load user-init-file nil t)
(run-hooks 'after-init-hook)
(message "Startup successful, including early-init and personal modules")
