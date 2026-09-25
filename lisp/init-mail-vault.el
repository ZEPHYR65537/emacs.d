;;; init-mail-vault.el --- Portable, pipe-only GnuPG mail vault -*- lexical-binding: t; -*-
(require 'auth-source)
(require 'json)
(require 'cl-lib)
(require 'subr-x)

(defvar jdd/mail-account-name)
(defvar jdd/mail-imap-host)
(defvar jdd/mail-smtp-host)
(defvar jdd/mail-imap-port)
(defvar jdd/mail-smtp-port)
(defvar jdd/mail--login)
(defvar jdd/mail-vault-directory
  (expand-file-name "emacs/mail/credentials/"
                    (or (getenv "XDG_DATA_HOME") (expand-file-name "~/.local/share/"))))
(defvar jdd/mail-gpg-program nil
  "Optional GPG executable path.  No credential belongs in this variable.")
(defvar jdd/mail-vault--profile nil
  "Decrypted profile for this session only.  Never persist or log this variable.")

(defun jdd/mail-vault-file ()
  "Return the portable ciphertext path, without reading its contents."
  (expand-file-name "account.gpg" jdd/mail-vault-directory))

(defun jdd/mail-vault-enabled-p ()
  "Whether the user explicitly saved an encrypted mail profile."
  (file-exists-p (jdd/mail-vault-file)))

(defun jdd/mail-vault--gpg ()
  "Find GnuPG, including existing Windows distributions without changing PATH."
  (or jdd/mail-gpg-program (executable-find "gpg") (executable-find "gpg2")
      (and (eq system-type 'windows-nt)
           (cl-find-if #'file-executable-p
                       (list (expand-file-name "~/scoop/apps/git/current/usr/bin/gpg.exe")
                             "C:/Program Files/Git/usr/bin/gpg.exe"
                             "C:/Program Files (x86)/GnuPG/bin/gpg.exe"
                             "C:/Program Files/GnuPG/bin/gpg.exe")))
      (user-error "Install GnuPG 2.x or set jdd/mail-gpg-program")))

(defun jdd/mail-vault--run (encrypt passphrase &optional plaintext)
  "Run GPG through pipes only.  ENCRYPT selects encryption of PLAINTEXT.
PASSPHRASE is the first stdin line, never a command argument or file.
Decryption reads ciphertext from disk and emits plaintext into Lisp memory.
Do not replace this with epg-decrypt-string: it uses a plaintext temp file."
  (when (or (string-empty-p passphrase) (string-match-p "[\r\n]" passphrase))
    (user-error "Vault passphrase must be nonempty and on one line"))
  (let* ((debug-on-error nil) (debug-on-quit nil) (debug-on-signal nil)
         (gpg (jdd/mail-vault--gpg))
         (gpg-home (expand-file-name "gpg-home/" jdd/mail-vault-directory))
         (output (unibyte-string))
         (process-connection-type nil)
         (input (concat (encode-coding-string passphrase 'utf-8-unix) "\n"
                        (if plaintext (encode-coding-string plaintext 'utf-8-unix) "")))
         (command
          (append (list gpg "--no-options" "--homedir" gpg-home
                        "--batch" "--yes" "--no-tty" "--pinentry-mode" "loopback"
                        "--passphrase-fd" "0" "--no-symkey-cache" "--output" "-")
                  (if encrypt
                      '("--cipher-algo" "AES256" "--s2k-mode" "3"
                        "--s2k-digest-algo" "SHA256" "--s2k-count" "65011712" "--symmetric")
                    (list "--decrypt" (jdd/mail-vault-file)))))
         process stderr-process succeeded)
    (make-directory gpg-home t)
    (set-file-modes jdd/mail-vault-directory #o700)
    (set-file-modes gpg-home #o700)
    (unwind-protect
        (progn
          (setq stderr-process
                (make-pipe-process :name "mail-gpg-stderr" :buffer nil
                                   :filter #'ignore :sentinel #'ignore :noquery t))
          (setq process
                (make-process :name "mail-gpg" :buffer nil :connection-type 'pipe
                              :coding 'binary :noquery t :sentinel #'ignore
                              :stderr stderr-process :command command
                              :filter (lambda (_process chunk) (setq output (concat output chunk)))))
          (with-timeout (30 (user-error "GPG operation timed out"))
            (process-send-string process input)
            (process-send-eof process)
            (while (process-live-p process) (accept-process-output process 0.05))
            (accept-process-output process 0.05))
          (unless (and (eq (process-status process) 'exit)
                       (zerop (process-exit-status process))
                       (> (length output) 0))
            (user-error "GPG could not open/save the vault; check the passphrase and GnuPG installation"))
          (setq succeeded t)
          output)
      (clear-string input)
      (unless succeeded (clear-string output))
      (when (processp process) (delete-process process))
      (when (processp stderr-process) (delete-process stderr-process)))))

(defun jdd/mail-vault-lock ()
  "Forget the decrypted profile.  The encrypted file is retained."
  (when-let* ((secret (plist-get jdd/mail-vault--profile :password)))
    (when (stringp secret) (clear-string secret)))
  (setq jdd/mail-vault--profile nil))

(defun jdd/mail-vault--validate (profile &optional require-secret)
  "Validate decrypted PROFILE without including its values in errors."
  (unless (and (equal (plist-get profile :version) 1)
               (cl-every (lambda (key) (stringp (plist-get profile key)))
                         '(:email :login :name :account-name :imap-host :smtp-host))
               (string-match-p "\\`[[:alnum:]_-]+\\'" (plist-get profile :account-name))
               (cl-every (lambda (key)
                           (let ((host (plist-get profile key)))
                             (and (not (string-empty-p host))
                                  (not (string-match-p "[[:space:]/@]" host)))))
                         '(:imap-host :smtp-host))
               (cl-every (lambda (key)
                           (let ((port (plist-get profile key)))
                             (and (integerp port) (<= 1 port 65535))))
                         '(:imap-port :smtp-port))
               (cl-every (lambda (key) (member (plist-get profile key) '("tls" "starttls")))
                         '(:imap-security :smtp-security))
               (member (plist-get profile :tls-priority)
                       '(nil "NORMAL:-VERS-TLS1.3"))
               (string-match-p "\\`[^[:space:]<>@]+@[^[:space:]<>@]+\\'"
                               (plist-get profile :email))
               (not (string-empty-p (plist-get profile :login)))
               (or (not require-secret)
                   (and (stringp (plist-get profile :password))
                        (not (string-empty-p (plist-get profile :password)))))
               (not (string-match-p "[\r\n]" (concat (plist-get profile :login)
                                                     (plist-get profile :name)))))
    (user-error "Invalid encrypted mail profile"))
  profile)

(defun jdd/mail-vault--unlock ()
  "Unlock once per session, without keeping the passphrase or plaintext files."
  (or jdd/mail-vault--profile
      (let ((debug-on-error nil) (debug-on-quit nil) (debug-on-signal nil)
            passphrase bytes plaintext)
        (unwind-protect
            (progn
              (setq passphrase (read-passwd "Unlock encrypted mail vault: ")
                    bytes (jdd/mail-vault--run nil passphrase)
                    plaintext (decode-coding-string bytes 'utf-8-unix))
              (condition-case nil
                  (setq jdd/mail-vault--profile
                        (jdd/mail-vault--validate
                         (json-parse-string plaintext :object-type 'plist :null-object nil) t))
                (error (user-error "Invalid encrypted mail profile"))))
          (dolist (value (list passphrase bytes plaintext))
            (when (stringp value) (clear-string value)))))))

(defun jdd/mail-vault-identity ()
  "Return only identity fields from the locally unlocked profile."
  (cl-loop for (key value) on (jdd/mail-vault--unlock) by #'cddr
           unless (eq key :password) append (list key value)))

(defun jdd/mail-vault-save (profile)
  "Save PROFILE as AES256 OpenPGP ciphertext, with no plaintext temp files."
  (jdd/mail-vault--validate profile t)
  (let ((debug-on-error nil) (debug-on-quit nil) (debug-on-signal nil)
        (file-name-handler-alist nil)
        (coding-system-for-write 'binary)
        (write-region-inhibit-fsync nil)
        passphrase plaintext ciphertext temporary)
    (unwind-protect
        (progn
          (setq passphrase (read-passwd "Choose independent vault passphrase: " t)
                plaintext (json-serialize profile :null-object nil)
                ciphertext (jdd/mail-vault--run t passphrase plaintext)
                temporary (make-temp-file (expand-file-name ".account-" jdd/mail-vault-directory)))
          (set-file-modes temporary #o600)
          ;; Only ciphertext reaches write-region, including atomic replacements.
          (write-region ciphertext nil temporary nil 'silent)
          (rename-file temporary (jdd/mail-vault-file) t)
          (setq temporary nil)
          (set-file-modes (jdd/mail-vault-file) #o600)
          (jdd/mail-vault-lock)
          ;; Parse a separate copy so clearing the caller's password is safe.
          (setq jdd/mail-vault--profile
                (json-parse-string plaintext :object-type 'plist :null-object nil)))
      (when (and temporary (file-exists-p temporary)) (delete-file temporary))
      (dolist (value (list passphrase plaintext ciphertext))
        (when (stringp value) (clear-string value))))))

(defun jdd/mail-vault--secret ()
  "Return the saved password only inside the local mail authentication flow."
  (plist-get (jdd/mail-vault--unlock) :password))

(defun jdd/mail-vault--search (&rest spec)
  "Return a lazy credential only for this account and encrypted mail ports."
  (let* ((host (plist-get spec :host)) (port (plist-get spec :port)) (user (plist-get spec :user))
         (hosts (if (listp host) host (list host)))
         (ports (mapcar (lambda (value) (format "%s" value))
                        (if (listp port) port (list port))))
         (imap-match (and (or (member jdd/mail-imap-host hosts)
                             (member jdd/mail-account-name hosts))
                          (member (number-to-string jdd/mail-imap-port) ports)))
         (smtp-match (and (member jdd/mail-smtp-host hosts)
                          (member (number-to-string jdd/mail-smtp-port) ports)))
         (matched-port (car (or imap-match smtp-match))))
    (when (and (jdd/mail-vault-enabled-p)
               matched-port jdd/mail--login
               (or (null user) (equal user jdd/mail--login))
               (not (plist-get spec :delete))
               (cl-every (lambda (key) (memq key '(:host :port :user :secret)))
                         (plist-get spec :require)))
      (list (list :host (if imap-match jdd/mail-imap-host jdd/mail-smtp-host) :port matched-port
                  :user jdd/mail--login :secret #'jdd/mail-vault--secret)))))

(defun jdd/mail-vault--parse (entry)
  "Recognize only the private-mail-gpg auth source."
  (when (eq entry 'private-mail-gpg)
    (auth-source-backend :type 'private-mail-gpg :source "private-mail-gpg"
                         :search-function #'jdd/mail-vault--search)))
(add-hook 'auth-source-backend-parser-functions #'jdd/mail-vault--parse)
(provide 'init-mail-vault)
;;; init-mail-vault.el ends here
