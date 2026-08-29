;;; init-exec-path.el --- Set up exec-path to help Emacs find programs  -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(require-package 'exec-path-from-shell)

(with-eval-after-load 'exec-path-from-shell
  (dolist (var '("SSH_AUTH_SOCK" "SSH_AGENT_PID" "GPG_AGENT_INFO" "LANG" "LC_CTYPE" "NIX_SSL_CERT_FILE" "NIX_PATH"))
    (add-to-list 'exec-path-from-shell-variables var)))


(when (or (memq window-system '(mac ns x pgtk))
          (unless (memq system-type '(ms-dos windows-nt))
            (daemonp)))
  (exec-path-from-shell-initialize))

;; Keep manually installed, configuration-local tools discoverable without
;; requiring a machine-wide PATH change.  Add this after importing the login
;; shell environment, because `exec-path-from-shell-initialize' replaces PATH.
(let ((local-bin (locate-user-emacs-file ".cache/bin")))
  (when (file-directory-p local-bin)
    (add-to-list 'exec-path local-bin)
    (setenv "PATH" (concat local-bin path-separator (getenv "PATH")))))

(defun sanityinc/find-executable (program &optional local-directory)
  "Find PROGRAM on PATH or in LOCAL-DIRECTORY under `user-emacs-directory'.
PROGRAM may also be an absolute file name.  `executable-find' supplies the
platform suffix, so callers should use portable names such as `texlab'."
  (or (and (file-name-absolute-p program)
           (file-executable-p program)
           program)
      (executable-find program)
      (when local-directory
        (let ((exec-path
               (cons (locate-user-emacs-file local-directory) exec-path)))
          (executable-find program)))))

(provide 'init-exec-path)
;;; init-exec-path.el ends here
