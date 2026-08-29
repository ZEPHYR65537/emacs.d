;;; init-typst.el --- Production Typst authoring support -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

(require 'seq)

(defgroup sanityinc-typst nil
  "Production Typst editing, language-server, and preview support."
  :group 'languages)

(defcustom sanityinc/typst-compiler-program nil
  "Optional Typst compiler executable name or absolute path.
When nil, search PATH and then the configuration-local `.cache/bin' directory."
  :type '(choice (const :tag "Search automatically" nil)
                 (file :tag "Typst executable"))
  :group 'sanityinc-typst)

(defcustom sanityinc/typst-tinymist-program nil
  "Optional Tinymist executable name or absolute path.
When nil, search PATH and then typst-ts-mode's local download directory."
  :type '(choice (const :tag "Search automatically" nil)
                 (file :tag "Tinymist executable"))
  :group 'sanityinc-typst)

(defconst sanityinc/typst-tinymist-settings
  '(:exportPdf "never"
    :formatterMode "typstyle")
  "Tinymist settings that leave builds to explicit preview/watch commands.")

(when (fboundp 'sanityinc/eglot-add-default-workspace-configuration)
  (sanityinc/eglot-add-default-workspace-configuration
   :tinymist sanityinc/typst-tinymist-settings))

(defun sanityinc/typst-compiler-executable ()
  "Return the configured Typst compiler, or nil when unavailable."
  (or (and sanityinc/typst-compiler-program
           (sanityinc/find-executable sanityinc/typst-compiler-program))
      (sanityinc/find-executable "typst" ".cache/bin")))

(defun sanityinc/typst-tinymist-executable ()
  "Return the configured Tinymist executable, or nil when unavailable."
  (or (and sanityinc/typst-tinymist-program
           (sanityinc/find-executable sanityinc/typst-tinymist-program))
      (sanityinc/find-executable "tinymist" ".cache/lsp/tinymist")))

(defun sanityinc/typst-tinymist-contact (&optional _interactive _project)
  "Return an Eglot process contact for the available Tinymist executable.
Optional arguments match Eglot 30's dynamic contact contract while retaining
compatibility with Eglot versions that invoke contact functions with no args."
  (when-let ((program (sanityinc/typst-tinymist-executable)))
    (list program)))

(defun sanityinc/typst-eglot-ensure ()
  "Start Tinymist for a file-backed Typst buffer when it is available."
  (when (and buffer-file-name
             (fboundp 'eglot-ensure)
             (sanityinc/typst-tinymist-executable))
    (eglot-ensure)))

(defun sanityinc/typst-preview-pdf (file)
  "Open Typst output FILE in an available platform viewer."
  (if-let ((sumatra
            (and (eq system-type 'windows-nt)
                 (sanityinc/find-executable "SumatraPDF" ".cache/bin"))))
      (start-process "SumatraPDF" nil sumatra "-reuse-instance"
                     (expand-file-name file))
    (browse-url-of-file (expand-file-name file))))

(defun sanityinc/typst-set-auto-mode (mode)
  "Use MODE for `.typ' files, replacing only our two supported choices.
Package autoloads can register `typst-ts-mode' before this module is evaluated.
Putting the selected entry first avoids order-dependent fallback behaviour."
  (setq auto-mode-alist
        (cons (cons "\\.typ\\'" mode)
              (seq-remove
               (lambda (entry)
                 (and (equal (car-safe entry) "\\.typ\\'")
                      (memq (cdr-safe entry) '(text-mode typst-ts-mode))))
               auto-mode-alist))))

(when (require 'treesit nil t)
  ;; typst-ts-mode's bundled queries target this grammar.
  (add-to-list 'treesit-language-source-alist
               '(typst "https://github.com/uben0/tree-sitter-typst"))

  (when (maybe-require-package 'typst-ts-mode)
    (if (and (fboundp 'treesit-ready-p)
             (treesit-ready-p 'typst t))
        (progn
          (sanityinc/typst-set-auto-mode 'typst-ts-mode)

          (setq typst-ts-indent-offset 2
                typst-ts-preview-function #'sanityinc/typst-preview-pdf)
          (when-let ((compiler (sanityinc/typst-compiler-executable)))
            (setq typst-ts-compile-executable-location compiler))

          (add-hook 'typst-ts-mode-hook #'sanityinc/typst-eglot-ensure)

          (with-eval-after-load 'eglot
            (add-to-list 'eglot-server-programs
                         '(typst-ts-mode . sanityinc/typst-tinymist-contact)))

          (with-eval-after-load 'typst-ts-mode
            (define-key typst-ts-mode-map (kbd "C-c C-c")
                        #'typst-ts-compile-and-preview)
            (define-key typst-ts-mode-map (kbd "C-c C-w")
                        #'typst-ts-watch-mode)
            (define-key typst-ts-mode-map (kbd "C-c C-q")
                        #'sanityinc/eglot-format-buffer)))
      ;; Package autoloads select typst-ts-mode unconditionally.  Restore the
      ;; portable fallback until the user installs the grammar and restarts.
      (sanityinc/typst-set-auto-mode 'text-mode))))

(when (maybe-require-package 'typst-preview)
  (when-let ((tinymist (sanityinc/typst-tinymist-executable)))
    (setq typst-preview-executable tinymist))
  (setq typst-preview-partial-rendering t)
  (with-eval-after-load 'typst-ts-mode
    (define-key typst-ts-mode-map (kbd "C-c C-p") #'typst-preview-mode)))

(provide 'init-typst)
;;; init-typst.el ends here
