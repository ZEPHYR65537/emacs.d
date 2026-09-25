;;; init-zig.el --- Support for the Zig language -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(if (and (maybe-require-package 'zig-ts-mode)
         (fboundp 'treesit-ready-p) (treesit-ready-p 'zig t))
    (progn
      (add-to-list 'auto-mode-alist '("\\.\\(zig\\|zon\\)\\'" . zig-ts-mode))
      (with-eval-after-load 'eglot
        (add-to-list 'eglot-server-programs '(zig-ts-mode . ("zls")))))
  (require-package 'zig-mode)
  ;; zig-ts-mode's package autoloads may already have claimed these files.
  ;; Put the usable fallback first when no compatible grammar is installed.
  (add-to-list 'auto-mode-alist '("\\.\\(zig\\|zon\\)\\'" . zig-mode)))


(provide 'init-zig)
;;; init-zig.el ends here
