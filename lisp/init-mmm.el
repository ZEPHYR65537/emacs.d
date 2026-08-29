;;; init-mmm.el --- Multiple Major Modes support -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(require-package 'mmm-mode)
(setq mmm-global-mode 'buffers-with-submode-classes)
(setq mmm-submode-decoration-level 2)

(defun sanityinc/mmm-enable-for-template-file ()
  "Load and enable MMM only for file types with configured submodes."
  (when (and buffer-file-name
             (string-match-p
              "\\.\\(?:r?html\\|yaml\\|erb\\|ejs\\)\\'"
              buffer-file-name))
    (require 'mmm-auto)
    (mmm-mode-on-maybe)))

(add-hook 'find-file-hook #'sanityinc/mmm-enable-for-template-file)


(provide 'init-mmm)
;;; init-mmm.el ends here
