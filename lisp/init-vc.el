;;; init-vc.el --- Version control support -*- lexical-binding: t -*-
;;; Commentary:

;; Most version control packages are configured separately: see
;; init-git.el, for example.

;;; Code:

(when (maybe-require-package 'diff-hl)
  (add-hook 'find-file-hook #'diff-hl-mode)
  (add-hook 'dired-mode-hook #'diff-hl-dired-mode-unless-remote)

  (with-eval-after-load 'diff-hl
    (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh)
    (define-key diff-hl-mode-map (kbd "<left-fringe> <mouse-1>") 'diff-hl-diff-goto-hunk)
    (define-key diff-hl-mode-map (kbd "M-C-]") 'diff-hl-next-hunk)
    (define-key diff-hl-mode-map (kbd "M-C-[") 'diff-hl-previous-hunk)))

(provide 'init-vc)
;;; init-vc.el ends here
