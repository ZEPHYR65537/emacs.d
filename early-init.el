;;; early-init.el --- Early startup settings -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

;; Purcell's init-elpa selects an Emacs-version-specific package directory and
;; calls package-initialize itself.  Disable Emacs's earlier default activation
;; so it does not scan the unrelated, non-versioned package directory first.
(setq package-enable-at-startup nil)

;; Apply the startup GC allowance before package activation and the main init.
(setq gc-cons-threshold (* 128 1024 1024))

(provide 'early-init)
;;; early-init.el ends here
