;;; init-latex.el --- Production LaTeX authoring with AUCTeX -*- lexical-binding: t; -*-
;;; Commentary:
;;; Code:

(require 'seq)

(require-package 'auctex)
(require-package 'preview-auto)
(require-package 'auctex-cont-latexmk)
(require-package 'auctex-label-numbers)
(require-package 'laas)
(require-package 'cdlatex)

(defgroup sanityinc-latex nil
  "Production LaTeX support layered on AUCTeX."
  :group 'LaTeX)

(defcustom sanityinc/latex-texlab-program nil
  "Optional Texlab executable name or absolute path.
When nil, search PATH and then the configuration-local `.cache/bin' directory."
  :type '(choice (const :tag "Search automatically" nil)
                 (file :tag "Texlab executable"))
  :group 'sanityinc-latex)

;; AUCTeX uses its parsed information for completion, references, and
;; multi-file documents.  Corfu consumes AUCTeX's standard completion-at-point
;; functions, so a second LaTeX completion framework is unnecessary.
(setq TeX-auto-save t
      TeX-parse-self t
      TeX-source-correlate-mode t
      TeX-source-correlate-start-server t
      reftex-plug-into-AUCTeX t
      TeX-electric-sub-and-superscript t
      LaTeX-electric-left-right-brace t
      font-latex-fontify-script 'multi-level
      font-latex-fontify-sectioning 1.15)
(setq-default TeX-master nil)
;; Use AUCTeX's public output-directory mechanism so one-shot builds,
;; continuous latexmk, SyncTeX, and preview-latex share one project-local
;; directory.  Directory-local and file-local values can still override this
;; default for projects whose toolchain requires outputs beside the master.
(setq-default TeX-output-dir "build")

(defconst sanityinc/latex-texlab-settings
  '(:build (:onSave :json-false)
    :chktex (:onOpenAndSave t :onEdit :json-false)
    :diagnosticsDelay 500
    :latexFormatter "latexindent"
    :bibtexFormatter "texlab"
    :formatterLineLength 100
    :latexindent (:modifyLineBreaks :json-false))
  "Texlab settings that avoid duplicate builds and edit-time lint storms.")

(when (fboundp 'sanityinc/eglot-add-default-workspace-configuration)
  (sanityinc/eglot-add-default-workspace-configuration
   :texlab sanityinc/latex-texlab-settings))

(defun sanityinc/latex-texlab-executable ()
  "Return the configured Texlab executable, or nil when unavailable."
  (or (and sanityinc/latex-texlab-program
           (sanityinc/find-executable sanityinc/latex-texlab-program))
      (sanityinc/find-executable "texlab" ".cache/bin")))

(defun sanityinc/latex-texlab-contact (&optional _interactive _project)
  "Return an Eglot process contact for the available Texlab executable.
Optional arguments match Eglot 30's dynamic contact contract while retaining
compatibility with Eglot versions that invoke contact functions with no args."
  (when-let ((program (sanityinc/latex-texlab-executable)))
    (list program)))

(defun sanityinc/latex-windows-posix-shell ()
  "Return a POSIX shell suitable for AUCTeX on Windows, or nil.
Prefer PATH, then derive Git for Windows' shell from the discovered `git'
executable instead of assuming a fixed Program Files location."
  (when (eq system-type 'windows-nt)
    (or (sanityinc/find-executable "sh")
        (when-let* ((git (sanityinc/find-executable "git"))
                    (git-directory (file-name-directory git)))
          (seq-find
           #'file-executable-p
           (mapcar
            (lambda (relative)
              (expand-file-name relative git-directory))
            '("sh.exe" "../bin/sh.exe" "../usr/bin/sh.exe")))))))

(defun sanityinc/latex-detect-standalone-master ()
  "Treat a buffer containing `documentclass' as its own AUCTeX master."
  (when (and (null TeX-master)
             (save-excursion
               (goto-char (point-min))
               (re-search-forward
                "^[[:space:]]*\\\\documentclass\\_>" nil t)))
    (setq-local TeX-master t)))

(defun sanityinc/latex-refresh-engine-settings ()
  "Select efficient preview and continuous-build settings for `TeX-engine'."
  ;; Preamble dumps give pdfLaTeX a large speed-up for small preview regions,
  ;; but XeLaTeX cannot use them and LuaLaTeX supports only simple preambles.
  (setq-local preview-auto-cache-preamble
              (if (memq TeX-engine '(xetex luatex)) nil t))
  ;; The continuous builder must use the same engine as AUCTeX.  It watches
  ;; files on disk, so it recompiles after saves rather than after keystrokes.
  (setq-local
   auctex-cont-latexmk-command
   (list (concat "latexmk -pvc "
                 (pcase TeX-engine
                   ('xetex "-xelatex ")
                   ('luatex "-lualatex ")
                   (_ "-pdf "))
                 "-view=none -synctex=1 -file-line-error "
                 "-interaction=nonstopmode "))))

(defun sanityinc/latex-eglot-ensure ()
  "Start Texlab without giving it a second document-build pipeline."
  (when (and buffer-file-name
             (fboundp 'eglot-ensure)
             (sanityinc/latex-texlab-executable))
    ;; latexmk/AUCTeX own compilation.  Texlab provides navigation,
    ;; completion, formatting, and diagnostics through Eglot/Flymake.
    (eglot-ensure)))

(defun sanityinc/latex-enable-incremental-preview ()
  "Continuously preview changed, visible LaTeX fragments in graphical frames."
  (when (and (display-images-p)
             (executable-find "latex")
             ;; The production default converts PDF/PS fragments through
             ;; Ghostscript.  `preview-gs-command' includes TeX Live's rungs,
             ;; MiKTeX's mgs, and ordinary Ghostscript discovery.
             (and (boundp 'preview-gs-command) preview-gs-command)
             (or (not (eq system-type 'windows-nt))
                 (sanityinc/latex-windows-posix-shell)))
    ;; Never let a background preview timer prompt for an unknown master file.
    ;; Included files activate after their file-local TeX-master is applied.
    (when (and (or (eq TeX-master t)
                   (and (stringp TeX-master)
                        (not (string= TeX-master ""))))
               (not (bound-and-true-p preview-auto-mode)))
      (preview-auto-conditionally-enable))))

(defun sanityinc/latex-after-local-variables ()
  "Refresh engine state after file-local variables are known."
  (sanityinc/latex-detect-standalone-master)
  (sanityinc/latex-refresh-engine-settings))

(defun sanityinc/latex-windows-process-environment ()
  "Set the Windows environment needed by TeX subprocesses in this buffer."
  (when (eq system-type 'windows-nt)
    (setq-local process-environment (copy-sequence process-environment))
    ;; TeX Live's Perl does not recognise C.UTF-8 on native Windows.
    (dolist (variable '("LANG" "LC_ALL" "LC_CTYPE"))
      (setenv variable "C"))
    ;; Git/MSYS otherwise rewrites preview-latex's `/AUCTEXINPUT{...}' TeX
    ;; macro into a path rooted below the Git installation.
    (setenv "MSYS2_ARG_CONV_EXCL" "*")))

(defun sanityinc/latex-mode-setup ()
  "Set up an AUCTeX buffer for editing and building LaTeX documents."
  ;; LaTeXMk handles reruns, bibliographies, and indexes for explicit builds.
  (setq TeX-command-default "LaTeXMk")
  (turn-on-reftex)
  (visual-line-mode 1)
  (sanityinc/latex-windows-process-environment)
  (sanityinc/latex-detect-standalone-master)
  (sanityinc/latex-refresh-engine-settings)
  ;; File-local TeX-engine settings are applied after the major-mode hook.
  (add-hook 'hack-local-variables-hook
            #'sanityinc/latex-after-local-variables nil t)
  ;; Run after AUCTeX has parsed styles and resolved file-local variables.
  ;; Starting in the major-mode hook races with `after-find-file'.
  (add-hook 'find-file-hook
            #'sanityinc/latex-enable-incremental-preview t t)
  (setq-local flymake-show-diagnostics-at-end-of-line t)
  (if (sanityinc/latex-texlab-executable)
      (progn
        ;; AUCTeX installs a second asynchronous ChkTeX backend.  Remove it
        ;; before Eglot enables Flymake so late callbacks cannot report into
        ;; state that Eglot has replaced.
        (remove-hook 'flymake-diagnostic-functions #'LaTeX-flymake t)
        (sanityinc/latex-eglot-ensure))
    ;; Without Texlab, retain AUCTeX's public ChkTeX backend when the external
    ;; checker is available.  This is a useful, low-cost degraded mode.
    (when (executable-find "chktex")
      (flymake-mode 1))))

(add-hook 'LaTeX-mode-hook #'sanityinc/latex-mode-setup)
(add-hook 'bibtex-mode-hook #'sanityinc/latex-eglot-ensure)

;; CDLaTeX supplies structured TAB-driven insertion; Laas expands short math
;; snippets as they are typed.  They complement AUCTeX rather than replacing it.
(add-hook 'LaTeX-mode-hook #'turn-on-cdlatex)
(add-hook 'LaTeX-mode-hook #'laas-mode)
(add-hook 'LaTeX-mode-hook #'preview-auto-setup)
(add-hook 'TeX-output-mode-hook
          #'sanityinc/latex-windows-process-environment)

(with-eval-after-load 'preview
  ;; Keep AUCTeX's documented PDF/PS -> PNG pipeline as the robust default.
  ;; The faster dvi* path cannot render CTeX/dvipdfmx `pdf:mapline' specials
  ;; and leaves previews stuck at the working icon.  Ghostscript keeps one
  ;; asynchronous process per preview run and handles PDF-producing engines.
  (setq preview-image-type 'png)
  ;; Keep the source visible while a preview is regenerated and avoid noisy
  ;; messages.  preview-auto skips valid overlays, so unchanged formulas are
  ;; not rendered again.
  (setq preview-protect-point t
        preview-locating-previews-message nil
        preview-leave-open-previews-visible t
        ;; Do not force pdfLaTeX into DVI mode: CTeX and custom classes may
        ;; require PDF-capable font and driver specials.
        preview-LaTeX-command-replacements nil))

(with-eval-after-load 'preview-auto
  ;; Scan only a modest window around point, after a short idle interval.  This
  ;; keeps large documents responsive while covering the visible editing area.
  (setq preview-auto-interval 0.3
        preview-auto-chars-above 3000
        preview-auto-chars-below 4000
        preview-auto-refresh-after-compilation t))

(with-eval-after-load 'latex
  (require 'auctex-label-numbers)
  (auctex-label-numbers-mode 1)

  (require 'auctex-cont-latexmk)
  ;; Texlab already owns diagnostics.  Binding the minor mode directly keeps
  ;; latexmk's efficient watcher without installing the package's additional
  ;; Flymake backend (as recommended by auctex-cont-latexmk upstream).
  (define-key LaTeX-mode-map (kbd "C-c C-w")
              #'auctex-cont-latexmk-mode)
  (define-key LaTeX-mode-map (kbd "C-c C-q")
              #'sanityinc/eglot-format-buffer)

  (require 'preview-auto))

(with-eval-after-load 'eglot
  (add-to-list
   'eglot-server-programs
   '(((LaTeX-mode :language-id "latex")
      (bibtex-mode :language-id "bibtex"))
     . sanityinc/latex-texlab-contact)))

(with-eval-after-load 'tex
  (when (eq system-type 'windows-nt)
    ;; preview-latex composes POSIX-style quoted fragments and format names.
    ;; Its Windows documentation requires an MSYS/Cygwin environment; Git for
    ;; Windows supplies a suitable shell.  This is global only to AUCTeX and
    ;; does not change the user's general or interactive Emacs shell.
    (when-let ((posix-shell (sanityinc/latex-windows-posix-shell)))
      (setq TeX-shell posix-shell
            TeX-shell-command-option "-c"))
    (when (executable-find "SumatraPDF")
      ;; Configure forward and inverse SyncTeX search.  Double percent signs
      ;; are reduced to literals by `TeX-command-expand' for placeholders.
      (add-to-list
       'TeX-view-program-list
       '("SumatraPDF"
         ("SumatraPDF -reuse-instance"
          (mode-io-correlate
           " -inverse-search \"emacsclientw.exe --no-wait +%%l \\\"%%f\\\"\" -forward-search \"%b\" %n")
          " %o")
         "SumatraPDF"))
      (setf (alist-get 'output-pdf TeX-view-program-selection)
            '("SumatraPDF")))))

(provide 'init-latex)
;;; init-latex.el ends here
