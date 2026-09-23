;;; config-doctor.el --- On-demand migration checks -*- lexical-binding: t; -*-
;;; Code:

(require 'init-local-packages)

(defun sanityinc/config-doctor ()
  "Report migration dependencies without installing or changing anything."
  (interactive)
  (with-output-to-temp-buffer "*Configuration health*"
    (princ (format "Emacs %s on %s\nConfiguration: %s\n\nLocal packages\n"
                   emacs-version system-type user-emacs-directory))
    (dolist (entry sanityinc/local-package-specs)
      (let ((spec (cdr entry)))
        (princ
         (format "  %s: %s\n" (car entry)
                 (cond ((version< emacs-version (plist-get spec :emacs))
                        (concat "requires Emacs " (plist-get spec :emacs)))
                       ((file-readable-p (expand-file-name
                                          (plist-get spec :library)
                                          (sanityinc/local-package-directory (car entry))))
                        "present")
                       (t "missing; run M-x sanityinc/bootstrap-local-packages"))))))
    (princ "\nExternal programs (each is only needed for its associated feature)\n")
    (dolist (program '("git" "rg" "latex" "latexmk" "chktex" "latexindent"
                       "texlab" "typst" "tinymist" "mmix" "mmixal" "mmotype"
                       "unzip" "node" "make4ht" "rsync" "ssh"))
      (princ (format "  %s: %s\n" program (or (executable-find program) "not on PATH"))))
    (princ (format "\nEPUB libxml support: %s\nSVG support for grid display: %s\n"
                   (if (and (fboundp 'libxml-available-p) (libxml-available-p)) "yes" "no")
                   (if (image-type-available-p 'svg) "yes" "no")))
    (when (and (require 'treesit nil t) (fboundp 'treesit-language-available-p))
      (dolist (language '(typst zig))
        (princ (format "%s grammar: %s\n" language
                       (if (treesit-language-available-p language) "loadable" "unavailable")))))
    (princ "\nSee docs/migration.md for native tools and installation instructions.\n")))

(provide 'config-doctor)
;;; config-doctor.el ends here
