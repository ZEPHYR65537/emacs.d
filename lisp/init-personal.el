;;; init-personal.el --- Shared preferences and enabled modules -*- lexical-binding: t; -*-
;;; Commentary:
;; Version this file.  Keep machine paths and display sizing in init-local.el.
;;; Code:

(require 'init-local-packages)

(defvar sanityinc/personal-modules
  '(init-comb-grid init-mmix init-nov init-static-site init-mail)
  "Personal feature modules to load.
Set in init-preload-local.el to select features for a particular machine.")

(when (maybe-require-package 'catppuccin-theme)
  (setq catppuccin-flavor 'frappe)
  (mapc #'disable-theme (copy-sequence custom-enabled-themes))
  (load-theme 'catppuccin t))

;; Let underline color follow the face, as expected by Dimmer.
(custom-set-faces
 '(whitespace-page-delimiter ((t (:underline (:style double-line))))))

(dolist (module sanityinc/personal-modules)
  (if (eq module 'init-mail)
      ;; Built-in autoloads keep all mail/crypto libraries out of startup.
      (progn
        (dolist (command '(jdd/mail jdd/mail-compose jdd/mail-setup
                           jdd/mail-configure-account jdd/mail-enable-persistence
                           jdd/mail-disable-persistence jdd/mail-forget-passwords))
          (autoload command "init-mail" nil t))
        (add-hook 'gnus-before-startup-hook #'jdd/mail-setup)
        (unless (lookup-key global-map (kbd "C-c m"))
          (global-set-key (kbd "C-c m") #'jdd/mail)))
    (require module)))

(provide 'init-personal)
;;; init-personal.el ends here
