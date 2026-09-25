;;; init-mail.el --- Configurable Gnus with optional encrypted credentials -*- lexical-binding: t; -*-

;; All libraries are built into Emacs.  Keep Purcell's existing package manager.
(require 'auth-source)
(require 'gnutls)
(require 'nsm)
(require 'subr-x)
(eval-when-compile
  (require 'gnus) (require 'gnus-start) (require 'gnus-art)
  (require 'nnimap) (require 'nnmail) (require 'smtpmail) (require 'message))

(defvar sanityinc/mail-account-name "mail" "Gnus server label, independent of the hostname.")
(defvar sanityinc/mail-imap-host nil "IMAP hostname; configured locally, never in this module.")
(defvar sanityinc/mail-smtp-host nil "SMTP hostname; configured locally, never in this module.")
(defvar sanityinc/mail-imap-port 993)
(defvar sanityinc/mail-smtp-port 465)
(defvar sanityinc/mail-imap-security 'tls "Either tls (implicit TLS) or starttls (required upgrade).")
(defvar sanityinc/mail-smtp-security 'tls "Either tls or starttls; never a plaintext fallback.")
(defvar sanityinc/mail-tls-priority nil
  "Optional GnuTLS compatibility setting.  Nil uses the system default.")
(defvar sanityinc/mail-state-directory
  (expand-file-name "emacs/mail/state/"
                    (or (getenv "XDG_DATA_HOME") (expand-file-name "~/.local/share/"))))
(defvar sanityinc/mail--configured nil)
(defvar sanityinc/mail--login nil)
(require 'init-mail-vault)

(defvar nnimap-address)
(defvar nnimap-user)
(defvar nnimap-stream)
(defvar nnimap-record-commands)
(defvar smtpmail-smtp-server)
(defvar smtpmail-stream-type)
(defvar smtpmail-debug-info)
(defvar smtpmail-debug-verb)
(defvar gnus-asynchronous)

(defun sanityinc/mail--private-connection (function &rest args)
  "Call FUNCTION with ARGS using session passwords or the opt-in GPG vault.
Never consult authinfo, netrc, environment secrets or plaintext files."
  (let ((auth-sources (and (sanityinc/mail-vault-enabled-p) '(private-mail-gpg)))
        (auth-source-save-behavior nil) (auth-source-creation-defaults nil)
        (auth-source-do-cache t) (auth-source-cache-expiry 3600) (auth-source-debug nil)
        (nnimap-record-commands nil) (smtpmail-debug-info nil) (smtpmail-debug-verb nil)
        (debug-on-error nil) (debug-on-quit nil) (debug-on-signal nil)
        (gnutls-verify-error t) (gnutls-log-level 0)
        (gnutls-algorithm-priority (or sanityinc/mail-tls-priority gnutls-algorithm-priority))
        (nsm-settings-file (expand-file-name "network-security.eld" sanityinc/mail-state-directory))
        (network-security-level 'high))
    (apply function args)))

(defun sanityinc/mail--imap-connection (function &rest args)
  "Protect only the configured account's IMAP connection."
  (if (and sanityinc/mail-imap-host (equal nnimap-address sanityinc/mail-imap-host))
      (let ((nnimap-user sanityinc/mail--login) (nnimap-stream sanityinc/mail-imap-security))
        (apply #'sanityinc/mail--private-connection function args))
    (apply function args)))

(defun sanityinc/mail--smtp-connection (function &rest args)
  "Protect only the configured account's SMTP connection."
  (if (and sanityinc/mail-smtp-host (equal smtpmail-smtp-server sanityinc/mail-smtp-host))
      (let ((smtpmail-stream-type sanityinc/mail-smtp-security))
        (apply #'sanityinc/mail--private-connection function args))
    (apply function args)))

(with-eval-after-load 'nnimap
  (advice-add 'nnimap-open-connection :around #'sanityinc/mail--imap-connection))
(with-eval-after-load 'smtpmail
  (advice-add 'smtpmail-via-smtp :around #'sanityinc/mail--smtp-connection))

(defun sanityinc/mail--prompt-profile ()
  "Read account settings locally; do not put identities in minibuffer history."
  (let* ((imap (string-trim (read-string "IMAP hostname: " nil t sanityinc/mail-imap-host)))
         (imap-security (completing-read "IMAP security: " '("tls" "starttls") nil t nil t
                                        (symbol-name sanityinc/mail-imap-security)))
         (imap-port (read-number "IMAP port: " (if (equal imap-security "starttls") 143 sanityinc/mail-imap-port)))
         (smtp (string-trim (read-string "SMTP hostname: " nil t (or sanityinc/mail-smtp-host imap))))
         (smtp-security (completing-read "SMTP security: " '("tls" "starttls") nil t nil t
                                        (symbol-name sanityinc/mail-smtp-security)))
         (smtp-port (read-number "SMTP port: " (if (equal smtp-security "starttls") 587 sanityinc/mail-smtp-port)))
         (compatibility (completing-read "TLS compatibility: " '("default" "tls12") nil t nil t
                                        (if sanityinc/mail-tls-priority "tls12" "default")))
         (address (string-trim (read-string "Your email address: " nil t)))
         (login (string-trim (read-string "IMAP/SMTP login: " nil t address)))
         (name (string-trim (read-string "From display name: " nil t))))
    (list :version 1 :account-name sanityinc/mail-account-name
          :imap-host imap :imap-port imap-port :imap-security imap-security
          :smtp-host smtp :smtp-port smtp-port :smtp-security smtp-security
          :tls-priority (and (equal compatibility "tls12") "NORMAL:-VERS-TLS1.3")
          :email address :login login :name (if (string-empty-p name) address name))))

(defun sanityinc/mail--current-profile ()
  "Build this session's settings in memory, excluding the mail password."
  (list :version 1 :account-name sanityinc/mail-account-name
        :imap-host sanityinc/mail-imap-host :imap-port sanityinc/mail-imap-port
        :imap-security (symbol-name sanityinc/mail-imap-security)
        :smtp-host sanityinc/mail-smtp-host :smtp-port sanityinc/mail-smtp-port
        :smtp-security (symbol-name sanityinc/mail-smtp-security)
        :tls-priority sanityinc/mail-tls-priority
        :email user-mail-address :login sanityinc/mail--login :name user-full-name))

(defun sanityinc/mail--apply-profile (profile)
  "Apply validated PROFILE without connecting or saving credentials."
  (sanityinc/mail-vault--validate profile)
  (require 'gnus) (require 'gnus-start) (require 'nnimap)
  (require 'nnmail) (require 'smtpmail) (require 'message)
  (setq sanityinc/mail-account-name (plist-get profile :account-name)
        sanityinc/mail-imap-host (plist-get profile :imap-host)
        sanityinc/mail-imap-port (plist-get profile :imap-port)
        sanityinc/mail-imap-security (intern (plist-get profile :imap-security))
        sanityinc/mail-smtp-host (plist-get profile :smtp-host)
        sanityinc/mail-smtp-port (plist-get profile :smtp-port)
        sanityinc/mail-smtp-security (intern (plist-get profile :smtp-security))
        sanityinc/mail-tls-priority (plist-get profile :tls-priority)
        user-mail-address (plist-get profile :email) user-full-name (plist-get profile :name)
        sanityinc/mail--login (plist-get profile :login)
        mail-user-agent 'gnus-user-agent send-mail-function #'smtpmail-send-it
        message-send-mail-function #'smtpmail-send-it
        smtpmail-smtp-server sanityinc/mail-smtp-host smtpmail-smtp-service sanityinc/mail-smtp-port
        smtpmail-stream-type sanityinc/mail-smtp-security smtpmail-smtp-user sanityinc/mail--login
        smtpmail-debug-info nil smtpmail-debug-verb nil
        gnus-select-method '(nnnil)
        gnus-secondary-select-methods
        `((nnimap ,sanityinc/mail-account-name (nnimap-address ,sanityinc/mail-imap-host)
                  (nnimap-server-port ,sanityinc/mail-imap-port) (nnimap-stream ,sanityinc/mail-imap-security)))
        gnus-home-directory sanityinc/mail-state-directory
        gnus-directory (expand-file-name "news/" sanityinc/mail-state-directory)
        gnus-startup-file (expand-file-name ".newsrc" sanityinc/mail-state-directory)
        gnus-dribble-directory sanityinc/mail-state-directory
        gnus-cache-directory (expand-file-name "cache/" sanityinc/mail-state-directory)
        message-directory (expand-file-name "mail/" sanityinc/mail-state-directory)
        gnus-message-archive-method
        `(nnfolder "archive" (nnfolder-directory ,(expand-file-name "sent/" sanityinc/mail-state-directory)))
        gnus-message-archive-group "sent" gnus-agent nil gnus-asynchronous nil
        gnus-auto-expirable-newsgroups nil nnmail-expiry-wait 'never
        nnimap-record-commands nil gnus-inhibit-images t)
  (make-directory gnus-directory t)
  (make-directory message-directory t)
  (setq sanityinc/mail--configured t))

(defun sanityinc/mail-setup ()
  "Unlock saved settings once per session, or prompt locally without saving."
  (interactive)
  (unless sanityinc/mail--configured
    (unless (gnutls-available-p) (user-error "This mail account requires GnuTLS support"))
    (sanityinc/mail-forget-passwords)
    (sanityinc/mail--apply-profile
     (if (sanityinc/mail-vault-enabled-p)
         (sanityinc/mail-vault-identity)
       (sanityinc/mail--prompt-profile)))))

(defun sanityinc/mail--store-profile (profile)
  "Prompt locally and encrypt PROFILE together with its mail password."
  (let ((debug-on-error nil) (debug-on-quit nil) (debug-on-signal nil) secret)
    (unwind-protect
        (progn
          (setq secret (read-passwd "Mail password to encrypt locally: " t))
          (when (string-empty-p secret) (user-error "Password must not be empty"))
          (sanityinc/mail-forget-passwords)
          (sanityinc/mail-vault-save (append profile (list :password secret))))
      (when (stringp secret) (clear-string secret)))))

(defun sanityinc/mail-enable-persistence ()
  "Opt in to portable GPG encryption.  Run again to replace a saved password."
  (interactive)
  (sanityinc/mail-setup)
  (sanityinc/mail--store-profile (sanityinc/mail--current-profile))
  (message "Encrypted mail persistence enabled; unlock once after restarting Emacs"))

(defun sanityinc/mail-configure-account ()
  "Configure hosts, ports, TLS and identity without contacting the servers.
If persistence is enabled, also request a password and re-encrypt the profile."
  (interactive)
  (when (and (fboundp 'gnus-alive-p) (gnus-alive-p))
    (user-error "Exit Gnus with q before changing accounts"))
  (let ((profile (sanityinc/mail--prompt-profile)))
    (sanityinc/mail-vault--validate profile)
    (if (sanityinc/mail-vault-enabled-p)
        (sanityinc/mail--store-profile profile)
      (sanityinc/mail-forget-passwords))
    (sanityinc/mail--apply-profile profile)))

(defun sanityinc/mail-disable-persistence ()
  "Delete only the encrypted profile and return to session-only credentials."
  (interactive)
  (when (file-exists-p (sanityinc/mail-vault-file)) (delete-file (sanityinc/mail-vault-file)))
  (sanityinc/mail-forget-passwords)
  (message "Saved mail credentials removed; session-only authentication enabled"))

(defun sanityinc/mail-forget-passwords ()
  "Forget cached passwords and lock the optional vault, leaving connections open."
  (interactive)
  (sanityinc/mail-vault-lock)
  (dolist (host (delete-dups (list sanityinc/mail-imap-host sanityinc/mail-smtp-host sanityinc/mail-account-name)))
    (when host (auth-source-forget+ :host host))))

(defun sanityinc/mail ()
  "Open Gnus after local setup or one vault unlock."
  (interactive) (sanityinc/mail-setup) (gnus))
(defun sanityinc/mail-compose ()
  "Compose mail after local setup or one vault unlock."
  (interactive) (sanityinc/mail-setup) (compose-mail))
(add-hook 'gnus-before-startup-hook #'sanityinc/mail-setup)
(unless (lookup-key global-map (kbd "C-c m")) (global-set-key (kbd "C-c m") #'sanityinc/mail))
(provide 'init-mail)
;;; init-mail.el ends here
