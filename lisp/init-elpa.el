;;; init-elpa.el --- Settings and helpers for package.el -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(require 'package)
(require 'cl-lib)


;;; Install into separate package dirs for each Emacs version, to prevent bytecode incompatibility
(setq package-user-dir
      (expand-file-name (format "elpa-%s.%s" emacs-major-version emacs-minor-version)
                        user-emacs-directory))

;; Loading one generated activation file is substantially faster than reading
;; every installed package descriptor and autoload file on each startup.  Keep
;; it beside the version-specific package tree so different Emacs versions do
;; not share byte code.  package.el refreshes it after installs and removals.
(setq package-quickstart t
      package-quickstart-file
      (expand-file-name "package-quickstart.el" package-user-dir))



;;; Standard package repositories

(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(add-to-list 'package-unsigned-archives "melpa")
;; Official MELPA Mirror, in case necessary.
;;(add-to-list 'package-archives (cons "melpa-mirror" (concat proto "://www.mirrorservice.org/sites/melpa.org/packages/")) t)

;; Allow built-in packages to be upgraded
(setq package-install-upgrade-built-in t)


;; Work-around for https://debbugs.gnu.org/cgi/bugreport.cgi?bug=34341
(when (and (version< emacs-version "26.3") (boundp 'libgnutls-version) (>= libgnutls-version 30604))
  (setq gnutls-algorithm-priority "NORMAL:-VERS-TLS1.3"))


;;; On-demand installation of packages

(defun require-package (package &optional min-version no-refresh)
  "Install given PACKAGE, optionally requiring MIN-VERSION.
If NO-REFRESH is non-nil, the available package lists will not be
re-downloaded in order to locate PACKAGE."
  (when (stringp min-version)
    (setq min-version (version-to-list min-version)))
  (or (package-installed-p package min-version)
      (let* ((known (cdr (assoc package package-archive-contents)))
             (best (car (sort known (lambda (a b)
                                      (version-list-<= (package-desc-version b)
                                                       (package-desc-version a)))))))
        (if (and best (version-list-<= min-version (package-desc-version best)))
            (package-install best)
          (if no-refresh
              (error "No version of %s >= %S is available" package min-version)
            (package-refresh-contents)
            (require-package package min-version t)))
        (package-installed-p package min-version))))

(defun maybe-require-package (package &optional min-version no-refresh)
  "Try to install PACKAGE, and return non-nil if successful.
In the event of failure, return nil and print a warning message.
Optionally require MIN-VERSION.  If NO-REFRESH is non-nil, the
available package lists will not be re-downloaded in order to
locate PACKAGE."
  (condition-case err
      (require-package package min-version no-refresh)
    (error
     (message "Couldn't install optional package `%s': %S" package err)
     nil)))


;;; Fire up package.el

(setq package-enable-at-startup nil)
(setq package-native-compile t)
(package-initialize)

(defun sanityinc/package-quickstart-refresh-if-missing ()
  "Create the package quickstart cache after the first graphical startup."
  (unless (or (file-readable-p package-quickstart-file)
              (file-readable-p (concat package-quickstart-file "c")))
    (package-quickstart-refresh)))

;; Do not make the first frame wait for cache generation.  Subsequent package
;; operations refresh the cache through package.el's normal lifecycle hooks.
(add-hook 'emacs-startup-hook
          (lambda ()
            (run-with-idle-timer
             2 nil #'sanityinc/package-quickstart-refresh-if-missing)))


;; package.el updates the saved version of package-selected-packages correctly only
;; after custom-file has been loaded, which is a bug. We work around this by adding
;; the required packages to package-selected-packages after startup is complete.

(defvar sanityinc/required-packages nil)

(defun sanityinc/note-selected-package (oldfun package &rest args)
  "If OLDFUN reports PACKAGE was successfully installed, note that fact.
The package name is noted by adding it to
`sanityinc/required-packages'.  This function is used as an
advice for `require-package', to which ARGS are passed."
  (let ((available (apply oldfun package args)))
    (prog1
        available
      (when available
        (add-to-list 'sanityinc/required-packages package)))))

(advice-add 'require-package :around 'sanityinc/note-selected-package)


;; Work around an issue in Emacs 29 where seq gets implicitly
;; reinstalled via the rg -> transient dependency chain, but fails to
;; reload cleanly due to not finding seq-25.el, breaking first-time
;; start-up
;; See https://debbugs.gnu.org/cgi/bugreport.cgi?bug=67025
(when (string= "29.1" emacs-version)
  (defun sanityinc/reload-previously-loaded-with-load-path-updated (orig pkg-desc)
    (let ((load-path (cons (package-desc-dir pkg-desc) load-path)))
      (funcall orig pkg-desc)))

  (advice-add 'package--reload-previously-loaded :around
              'sanityinc/reload-previously-loaded-with-load-path-updated))



(when (fboundp 'package--save-selected-packages)
  (require-package 'seq)
  (add-hook 'after-init-hook
            (lambda ()
              ;; Avoid invoking Customize and rewriting custom.el on every
              ;; startup when the selected package set is already complete.
              (when (seq-difference sanityinc/required-packages
                                    package-selected-packages #'eq)
                (package--save-selected-packages
                 (seq-uniq
                  (append sanityinc/required-packages
                          package-selected-packages)))))))


(let ((package-check-signature nil))
  (require-package 'gnu-elpa-keyring-update))


(defun sanityinc/maybe-widen-package-menu-columns ()
  "Widen some columns of the package menu table to avoid truncation."
  (when (boundp 'tabulated-list-format)
    (setq package-version-column-width 20)
    (let ((longest-archive-name (apply 'max (mapcar 'length (mapcar 'car package-archives)))))
      (setq package-archive-column-width longest-archive-name))))

(add-hook 'package-menu-mode-hook 'sanityinc/maybe-widen-package-menu-columns)


(provide 'init-elpa)
;;; init-elpa.el ends here
