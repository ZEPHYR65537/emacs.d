;;; init-mail.el --- Configurable Gnus with optional encrypted credentials -*- lexical-binding: t; -*-

;; All libraries are built into Emacs.  Keep Purcell's existing package manager.
(require 'auth-source)
(require 'gnutls)
(require 'nsm)
(require 'subr-x)
;; Declarations keep interpreted startup lazy too: eval-when-compile would
;; execute its requires when this source file is loaded without bytecode.
(declare-function gnus "gnus" (&optional dont-connect slave))
(declare-function gnus-alive-p "gnus" ())
(declare-function smtpmail-send-it "smtpmail" ())
(defvar smtpmail-smtp-service)
(defvar smtpmail-smtp-user)
(defvar message-send-mail-function)
(defvar message-directory)
(defvar gnus-select-method)
(defvar gnus-secondary-select-methods)
(defvar gnus-home-directory)
(defvar gnus-directory)
(defvar gnus-startup-file)
(defvar gnus-dribble-directory)
(defvar gnus-cache-directory)
(defvar gnus-message-archive-method)
(defvar gnus-message-archive-group)
(defvar gnus-agent)
(defvar gnus-auto-expirable-newsgroups)
(defvar gnus-inhibit-images)
(defvar nnmail-expiry-wait)

(defvar jdd/mail-account-name "mail" "Gnus server label, independent of the hostname.")
(defvar jdd/mail-imap-host nil "IMAP hostname; configured locally, never in this module.")
(defvar jdd/mail-smtp-host nil "SMTP hostname; configured locally, never in this module.")
(defvar jdd/mail-imap-port 993)
(defvar jdd/mail-smtp-port 465)
(defvar jdd/mail-imap-security 'tls "Either tls (implicit TLS) or starttls (required upgrade).")
(defvar jdd/mail-smtp-security 'tls "Either tls or starttls; never a plaintext fallback.")
(defvar jdd/mail-tls-priority nil
  "Optional GnuTLS compatibility setting.  Nil uses the system default.")
(defvar jdd/mail-state-directory
  (expand-file-name "emacs/mail/state/"
                    (or (getenv "XDG_DATA_HOME") (expand-file-name "~/.local/share/"))))
(defvar jdd/mail--configured nil)
(defvar jdd/mail--login nil)
(require 'init-mail-vault)

(defvar nnimap-address)
(defvar nnimap-server-port)
(defvar nnimap-user)
(defvar nnimap-stream)
(defvar nnimap-record-commands)
(defvar smtpmail-smtp-server)
(defvar smtpmail-stream-type)
(defvar smtpmail-debug-info)
(defvar smtpmail-debug-verb)
(defvar gnus-asynchronous)

(defun jdd/mail--private-connection (function &rest args)
  "Call FUNCTION with ARGS using session passwords or the opt-in GPG vault.
Never consult authinfo, netrc, environment secrets or plaintext files."
  (let ((auth-sources (and (jdd/mail-vault-enabled-p) '(private-mail-gpg)))
        (auth-source-save-behavior nil) (auth-source-creation-defaults nil)
        (auth-source-do-cache t) (auth-source-cache-expiry 3600) (auth-source-debug nil)
        (nnimap-record-commands nil) (smtpmail-debug-info nil) (smtpmail-debug-verb nil)
        (debug-on-error nil) (debug-on-quit nil) (debug-on-signal nil)
        (gnutls-verify-error t) (gnutls-log-level 0)
        (gnutls-algorithm-priority (or jdd/mail-tls-priority gnutls-algorithm-priority))
        (nsm-settings-file (expand-file-name "network-security.eld" jdd/mail-state-directory))
        (network-security-level 'high))
    (apply function args)))

(defun jdd/mail--imap-connection (function &rest args)
  "Protect only the configured account's IMAP connection."
  (if (and jdd/mail-imap-host (equal nnimap-address jdd/mail-imap-host)
           (equal (format "%s" nnimap-server-port) (format "%s" jdd/mail-imap-port))
           (or (null nnimap-user) (equal nnimap-user jdd/mail--login)))
      (let ((nnimap-user jdd/mail--login) (nnimap-stream jdd/mail-imap-security))
        (apply #'jdd/mail--private-connection function args))
    (apply function args)))

(defun jdd/mail--smtp-connection (function &rest args)
  "Protect only the configured account's SMTP connection."
  (if (and jdd/mail-smtp-host (equal smtpmail-smtp-server jdd/mail-smtp-host)
           (equal (format "%s" smtpmail-smtp-service) (format "%s" jdd/mail-smtp-port))
           (or (null smtpmail-smtp-user) (equal smtpmail-smtp-user jdd/mail--login)))
      (let ((smtpmail-stream-type jdd/mail-smtp-security))
        (apply #'jdd/mail--private-connection function args))
    (apply function args)))

(with-eval-after-load 'nnimap
  (advice-add 'nnimap-open-connection :around #'jdd/mail--imap-connection))
(with-eval-after-load 'smtpmail
  (advice-add 'smtpmail-via-smtp :around #'jdd/mail--smtp-connection))

(defun jdd/mail--prompt-profile ()
  "Read account settings locally; do not put identities in minibuffer history."
  (let* ((imap (string-trim (read-string "IMAP hostname: " nil t jdd/mail-imap-host)))
         (imap-security (completing-read "IMAP security: " '("tls" "starttls") nil t nil t
                                        (symbol-name jdd/mail-imap-security)))
         (imap-port (read-number "IMAP port: " (if (equal imap-security "starttls") 143 jdd/mail-imap-port)))
         (smtp (string-trim (read-string "SMTP hostname: " nil t (or jdd/mail-smtp-host imap))))
         (smtp-security (completing-read "SMTP security: " '("tls" "starttls") nil t nil t
                                        (symbol-name jdd/mail-smtp-security)))
         (smtp-port (read-number "SMTP port: " (if (equal smtp-security "starttls") 587 jdd/mail-smtp-port)))
         (compatibility (completing-read "TLS compatibility: " '("default" "tls12") nil t nil t
                                        (if jdd/mail-tls-priority "tls12" "default")))
         (address (string-trim (read-string "Your email address: " nil t)))
         (login (string-trim (read-string "IMAP/SMTP login: " nil t address)))
         (name (string-trim (read-string "From display name: " nil t))))
    (list :version 1 :account-name jdd/mail-account-name
          :imap-host imap :imap-port imap-port :imap-security imap-security
          :smtp-host smtp :smtp-port smtp-port :smtp-security smtp-security
          :tls-priority (and (equal compatibility "tls12") "NORMAL:-VERS-TLS1.3")
          :email address :login login :name (if (string-empty-p name) address name))))

(defun jdd/mail--current-profile ()
  "Build this session's settings in memory, excluding the mail password."
  (list :version 1 :account-name jdd/mail-account-name
        :imap-host jdd/mail-imap-host :imap-port jdd/mail-imap-port
        :imap-security (symbol-name jdd/mail-imap-security)
        :smtp-host jdd/mail-smtp-host :smtp-port jdd/mail-smtp-port
        :smtp-security (symbol-name jdd/mail-smtp-security)
        :tls-priority jdd/mail-tls-priority
        :email user-mail-address :login jdd/mail--login :name user-full-name))

(defun jdd/mail--apply-profile (profile)
  "Apply validated PROFILE without connecting or saving credentials."
  (jdd/mail-vault--validate profile)
  (require 'gnus) (require 'gnus-start) (require 'nnimap)
  (require 'nnmail) (require 'smtpmail) (require 'message)
  (setq jdd/mail-account-name (plist-get profile :account-name)
        jdd/mail-imap-host (plist-get profile :imap-host)
        jdd/mail-imap-port (plist-get profile :imap-port)
        jdd/mail-imap-security (intern (plist-get profile :imap-security))
        jdd/mail-smtp-host (plist-get profile :smtp-host)
        jdd/mail-smtp-port (plist-get profile :smtp-port)
        jdd/mail-smtp-security (intern (plist-get profile :smtp-security))
        jdd/mail-tls-priority (plist-get profile :tls-priority)
        user-mail-address (plist-get profile :email) user-full-name (plist-get profile :name)
        jdd/mail--login (plist-get profile :login)
        mail-user-agent 'gnus-user-agent send-mail-function #'smtpmail-send-it
        message-send-mail-function #'smtpmail-send-it
        smtpmail-smtp-server jdd/mail-smtp-host smtpmail-smtp-service jdd/mail-smtp-port
        smtpmail-stream-type jdd/mail-smtp-security smtpmail-smtp-user jdd/mail--login
        smtpmail-debug-info nil smtpmail-debug-verb nil
        gnus-select-method '(nnnil)
        gnus-secondary-select-methods
        `((nnimap ,jdd/mail-account-name (nnimap-address ,jdd/mail-imap-host)
                  (nnimap-server-port ,jdd/mail-imap-port) (nnimap-stream ,jdd/mail-imap-security)))
        gnus-home-directory jdd/mail-state-directory
        gnus-directory (expand-file-name "news/" jdd/mail-state-directory)
        gnus-startup-file (expand-file-name ".newsrc" jdd/mail-state-directory)
        gnus-dribble-directory jdd/mail-state-directory
        gnus-cache-directory (expand-file-name "cache/" jdd/mail-state-directory)
        message-directory (expand-file-name "mail/" jdd/mail-state-directory)
        gnus-message-archive-method
        `(nnfolder "archive" (nnfolder-directory ,(expand-file-name "sent/" jdd/mail-state-directory)))
        gnus-message-archive-group "sent" gnus-agent nil gnus-asynchronous nil
        gnus-auto-expirable-newsgroups nil nnmail-expiry-wait 'never
        nnimap-record-commands nil gnus-inhibit-images t)
  (make-directory gnus-directory t)
  (make-directory message-directory t)
  (setq jdd/mail--configured t))

(defun jdd/mail-setup ()
  "Unlock saved settings once per session, or prompt locally without saving."
  (interactive)
  (unless jdd/mail--configured
    (unless (gnutls-available-p) (user-error "This mail account requires GnuTLS support"))
    (jdd/mail-forget-passwords)
    (jdd/mail--apply-profile
     (if (jdd/mail-vault-enabled-p)
         (jdd/mail-vault-identity)
       (jdd/mail--prompt-profile)))))

(defun jdd/mail--store-profile (profile)
  "Prompt locally and encrypt PROFILE together with its mail password."
  (let ((debug-on-error nil) (debug-on-quit nil) (debug-on-signal nil) secret)
    (unwind-protect
        (progn
          (setq secret (read-passwd "Mail password to encrypt locally: " t))
          (when (string-empty-p secret) (user-error "Password must not be empty"))
          (jdd/mail-forget-passwords)
          (jdd/mail-vault-save (append profile (list :password secret))))
      (when (stringp secret) (clear-string secret)))))

(defun jdd/mail-enable-persistence ()
  "Opt in to portable GPG encryption.  Run again to replace a saved password."
  (interactive)
  (jdd/mail-setup)
  (jdd/mail--store-profile (jdd/mail--current-profile))
  (message "Encrypted mail persistence enabled; unlock once after restarting Emacs"))

(defun jdd/mail-configure-account ()
  "Configure hosts, ports, TLS and identity without contacting the servers.
If persistence is enabled, also request a password and re-encrypt the profile."
  (interactive)
  (when (and (fboundp 'gnus-alive-p) (gnus-alive-p))
    (user-error "Exit Gnus with q before changing accounts"))
  (let ((profile (jdd/mail--prompt-profile)))
    (jdd/mail-vault--validate profile)
    (if (jdd/mail-vault-enabled-p)
        (jdd/mail--store-profile profile)
      (jdd/mail-forget-passwords))
    (jdd/mail--apply-profile profile)))

(defun jdd/mail-disable-persistence ()
  "Delete only the encrypted profile and return to session-only credentials."
  (interactive)
  (when (file-exists-p (jdd/mail-vault-file)) (delete-file (jdd/mail-vault-file)))
  (jdd/mail-forget-passwords)
  (message "Saved mail credentials removed; session-only authentication enabled"))

(defun jdd/mail-forget-passwords ()
  "Forget cached passwords and lock the optional vault, leaving connections open."
  (interactive)
  (jdd/mail-vault-lock)
  (when jdd/mail--login
    (dolist (endpoint (list (cons jdd/mail-imap-host jdd/mail-imap-port)
                            (cons jdd/mail-account-name jdd/mail-imap-port)
                            (cons jdd/mail-smtp-host jdd/mail-smtp-port)))
      (when (car endpoint)
        ;; auth-source caches may use either numeric ports or service strings.
        (dolist (port (list (cdr endpoint) (number-to-string (cdr endpoint))))
          (auth-source-forget+ :host (car endpoint) :port port :user jdd/mail--login))))))

(defun jdd/mail ()
  "Open Gnus after local setup or one vault unlock."
  (interactive) (jdd/mail-setup) (gnus))
(defun jdd/mail-compose ()
  "Compose mail after local setup or one vault unlock."
  (interactive) (jdd/mail-setup) (compose-mail))
(add-hook 'gnus-before-startup-hook #'jdd/mail-setup)
(unless (lookup-key global-map (kbd "C-c m")) (global-set-key (kbd "C-c m") #'jdd/mail))
(provide 'init-mail)
;;; init-mail.el ends here
