;;; init-flymake.el --- Configure Flymake global behaviour -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(maybe-require-package 'flymake "1.2.1")

;; Use flycheck checkers with flymake, to extend its coverage
(when (maybe-require-package 'flymake-flycheck)
  ;; Disable flycheck checkers for which we have flymake equivalents
  (with-eval-after-load 'flycheck
    (setq-default
     flycheck-disabled-checkers
     (append (default-value 'flycheck-disabled-checkers)
             '(emacs-lisp emacs-lisp-checkdoc emacs-lisp-package sh-shellcheck))))

  (defun sanityinc/maybe-enable-flymake-flycheck ()
    "Use Flycheck backends for files unless Texlab owns diagnostics."
    (when (and buffer-file-name
               (not (derived-mode-p 'LaTeX-mode)))
      (flymake-flycheck-auto)))

  (add-hook 'flymake-mode-hook #'sanityinc/maybe-enable-flymake-flycheck)
  (defun sanityinc/maybe-enable-flymake-for-file ()
    "Enable Flymake in file-backed programming buffers."
    (when buffer-file-name
      (flymake-mode 1)))

  (add-hook 'prog-mode-hook #'sanityinc/maybe-enable-flymake-for-file)

  (defun sanityinc/maybe-enable-flymake-in-text-mode ()
    "Enable generic Flymake except where Texlab will take ownership."
    (when (and buffer-file-name
               (not (derived-mode-p 'LaTeX-mode)))
      (flymake-mode 1)))

  (add-hook 'text-mode-hook #'sanityinc/maybe-enable-flymake-in-text-mode))

(with-eval-after-load 'flymake
  ;; Provide some flycheck-like bindings in flymake mode to ease transition
  (define-key flymake-mode-map (kbd "C-c ! l") 'flymake-show-buffer-diagnostics)
  (define-key flymake-mode-map (kbd "C-c ! n") 'flymake-goto-next-error)
  (define-key flymake-mode-map (kbd "C-c ! p") 'flymake-goto-prev-error)
  (define-key flymake-mode-map (kbd "C-c ! c") 'flymake-start))

(unless (version< emacs-version "28.1")
  (setq eldoc-documentation-function 'eldoc-documentation-compose)

  (add-hook 'flymake-mode-hook
            (lambda ()
              (add-to-list 'eldoc-documentation-functions 'flymake-eldoc-function))))

(provide 'init-flymake)
;;; init-flymake.el ends here
