;;; init-projectile.el --- Use Projectile for navigation within projects -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(when (maybe-require-package 'projectile)
  ;; Shorter modeline
  (setq-default projectile-mode-line-prefix " Proj")

  (when (executable-find "rg")
    (setq-default projectile-generic-command "rg --files --hidden -0"))

  (with-eval-after-load 'projectile
    (define-key projectile-mode-map (kbd "C-c p") 'projectile-command-map))

  (defun sanityinc/projectile-command-prefix ()
    "Load Projectile on first use, then activate its normal prefix map."
    (interactive)
    (projectile-mode 1)
    (set-transient-map projectile-command-map t)
    (message "Projectile command:"))

  ;; Once Projectile is loaded its minor-mode map takes precedence and this
  ;; becomes the ordinary `projectile-command-map' prefix binding.
  (global-set-key (kbd "C-c p") #'sanityinc/projectile-command-prefix)

  (maybe-require-package 'ibuffer-projectile))


(provide 'init-projectile)
;;; init-projectile.el ends here
