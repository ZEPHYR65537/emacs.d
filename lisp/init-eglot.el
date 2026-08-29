;;; init-eglot.el --- LSP support via eglot          -*- lexical-binding: t; -*-

;;; Commentary:

;;; Code:

(when (maybe-require-package 'eglot)
  (setq-default eglot-extend-to-xref t)
  (setq eglot-code-action-indicator "✓")
  (setq eglot-code-action-indications '(eldoc-hint mode-line))

  (defcustom sanityinc/eglot-format-timeout 30
    "Seconds to wait for an explicit language-server formatting request.
Formatting an entire production document can legitimately take longer than
jsonrpc's short default used for routine interactive requests."
    :type 'number
    :group 'eglot)

  (defun sanityinc/eglot-format-buffer ()
    "Format the current buffer, allowing time for an external formatter."
    (interactive)
    (let ((jsonrpc-default-request-timeout sanityinc/eglot-format-timeout))
      (eglot-format-buffer)))

  (defun sanityinc/disable-eglot-semantic-tokens ()
    ;; Semantic token support is not present in every Eglot/Emacs version.
    (when (fboundp 'eglot-semantic-tokens-mode)
      (eglot-semantic-tokens-mode -1)))
  (add-hook 'eglot-managed-mode-hook #'sanityinc/disable-eglot-semantic-tokens)

  (defvar sanityinc/eglot-default-workspace-sections nil
    "Language-server sections to merge after Eglot defines its options.")

  (defun sanityinc/eglot--apply-default-workspace-configuration (section value)
    "Merge SECTION and VALUE into Eglot's default workspace configuration."
    (let ((configuration
           (copy-tree (default-value 'eglot-workspace-configuration))))
      (cond
       ((functionp configuration)
        (display-warning
         'eglot
         (format "Not adding default %s settings: workspace configuration is a function"
                 section)
         :warning))
       ((and configuration (consp (car configuration)))
        (setf (alist-get section configuration nil nil #'equal) value)
        (setq-default eglot-workspace-configuration configuration))
       (t
        (setq-default eglot-workspace-configuration
                      (plist-put configuration section value))))))

  (defun sanityinc/eglot-add-default-workspace-configuration (section value)
    "Register SECTION and VALUE as default Eglot workspace configuration.
Registration is safe before Eglot is loaded.  Existing server sections are
preserved, while a user-supplied configuration function remains authoritative."
    (setf (alist-get section sanityinc/eglot-default-workspace-sections
                     nil nil #'eq)
          value)
    (when (featurep 'eglot)
      (sanityinc/eglot--apply-default-workspace-configuration section value)))

  (with-eval-after-load 'eglot
    (dolist (entry sanityinc/eglot-default-workspace-sections)
      (sanityinc/eglot--apply-default-workspace-configuration
       (car entry) (cdr entry))))

  (maybe-require-package 'consult-eglot))



(provide 'init-eglot)
;;; init-eglot.el ends here
