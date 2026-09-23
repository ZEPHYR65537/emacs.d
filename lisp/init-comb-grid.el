;;; init-comb-grid.el --- Local combinatorics grid package -*- lexical-binding: t -*-
;;; Commentary:
;; Source and tested revision are recorded in init-local-package-manifest.el.
;;; Code:

(require 'init-local-packages)
(when (sanityinc/enable-local-package 'comb-grid)
  (autoload 'comb-grid-new "comb-grid-mode" "Create a combinatorics grid." t)
  (autoload 'comb-grid-open "comb-grid-mode" "Open a saved grid." t)
  (autoload 'comb-grid-file-mode "comb-grid-mode" "Visit a saved grid." t)
  (add-to-list 'auto-mode-alist '("\\.cgrid\\'" . comb-grid-file-mode)))

(provide 'init-comb-grid)
;;; init-comb-grid.el ends here
