;;; init-latex-preview-test.el --- Preview cancellation regression tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'preview)
(require 'preview-auto)
(require 'init-latex-preview)

(defvar sanityinc/latex-preview-idle-delay)

(ert-deftest sanityinc/preview-source-survives-output-mode-reset ()
  (with-temp-buffer
    (let ((source (current-buffer))
          (output (generate-new-buffer " *preview-source-test*")))
      (unwind-protect
          (cl-letf (((symbol-function 'processp) (lambda (_) t))
                    ((symbol-function 'process-buffer) (lambda (_) output)))
            (sanityinc/latex-preview-preserve-source
             (lambda (&rest _)
               (set-buffer output)
               (setq-local TeX-command-buffer source)
               (fundamental-mode)
               'test-process)
             "Preview-LaTeX" "latex" "_region_")
            (should (local-variable-p 'TeX-command-buffer output))
            (should (eq (buffer-local-value 'TeX-command-buffer output) source)))
        (kill-buffer output)))))

(defmacro sanityinc/test-with-preview-job (&rest body)
  "Run BODY with deterministic job timers and no external compiler."
  (declare (indent 0) (debug t))
  `(with-temp-buffer
     (insert "\\[x+1\\] more text")
     (cl-letf (((symbol-function 'TeX-master-output-file)
                (lambda (_) (expand-file-name "missing-preview-test.aux" temporary-file-directory)))
               ((symbol-function 'run-with-timer) (lambda (&rest _) 'test-timer))
               ((symbol-function 'cancel-timer) #'ignore)
               ((symbol-function 'sanityinc/latex-preview--processes) (lambda (&rest _) nil)))
       ,@body)))

(ert-deftest sanityinc/preview-invalid-fragment-waits-for-edit ()
  (sanityinc/test-with-preview-job
    (let ((calls 0)
          (compile (lambda (&rest _) (error "Invalid LaTeX"))))
      (cl-letf (((symbol-function 'message) #'ignore))
        (sanityinc/latex-preview-run-once
         (lambda (&rest args) (setq calls (1+ calls)) (apply compile args)) 1 8)
        (sanityinc/latex-preview--watch (current-buffer) sanityinc/latex-preview--job)
        (sanityinc/latex-preview-run-once
         (lambda (&rest _) (setq calls (1+ calls))) 1 8)
        (should (= calls 1))
        (should-not (sanityinc/latex-preview-untried-p 2))
        (should (sanityinc/latex-preview-untried-p 10))
        ;; Cursor movement is not a source edit and must not restart failures.
        (goto-char (point-min))
        (should-not (sanityinc/latex-preview-untried-p 2))
        (insert " ")
        (should (sanityinc/latex-preview-untried-p 2))
        (sanityinc/latex-preview-run-once
         (lambda (&rest _) (setq calls (1+ calls))) 2 9)
        (sanityinc/latex-preview--watch (current-buffer) sanityinc/latex-preview--job)
        (should (= calls 2))))))

(ert-deftest sanityinc/preview-timeout-cancels-once ()
  (sanityinc/test-with-preview-job
    (let ((job (list :deadline 0 :cancelled nil)) stopped)
      (cl-letf (((symbol-function 'sanityinc/latex-preview--processes)
                 (lambda (&rest _) '(compiler converter)))
                ((symbol-function 'sanityinc/latex-preview--stop-process)
                 (lambda (p) (push p stopped)))
                ((symbol-function 'message) #'ignore))
        (sanityinc/latex-preview--watch (current-buffer) job)
        (sanityinc/latex-preview--watch (current-buffer) job)
        (should (plist-get job :cancelled))
        (should (equal stopped '(converter compiler)))))))

(ert-deftest sanityinc/preview-edits-cancel-instead-of-killing-only-shell ()
  (sanityinc/test-with-preview-job
    (let ((sanityinc/latex-preview--job (list :cancelled nil)) stopped)
      (cl-letf (((symbol-function 'sanityinc/latex-preview--processes)
                 (lambda (&rest _) '(compiler)))
                ((symbol-function 'sanityinc/latex-preview--stop-process)
                 (lambda (p) (push p stopped))))
        (sanityinc/latex-preview--after-change
         (lambda (&rest _) (ert-fail "Upstream shell-only cancellation was used")) 1 2 0)
        (should (equal stopped '(compiler)))
        (should preview-abort-flag)
        (should preview-auto--keepalive)))))

(ert-deftest sanityinc/preview-completion-releases-next-attempt ()
  (sanityinc/test-with-preview-job
    (sanityinc/latex-preview-run-once #'ignore 1 8)
    (should sanityinc/latex-preview--job)
    (sanityinc/latex-preview--watch (current-buffer) sanityinc/latex-preview--job)
    (should-not sanityinc/latex-preview--job)
    (should-not preview-abort-flag)
    (should (sanityinc/latex-preview-untried-p 10))))

(ert-deftest sanityinc/preview-mode-restart-allows-retry ()
  (sanityinc/test-with-preview-job
    (sanityinc/latex-preview-run-once #'ignore 1 8)
    (sanityinc/latex-preview--watch (current-buffer) sanityinc/latex-preview--job)
    (should-not (sanityinc/latex-preview-untried-p 2))
    (let ((preview-auto-mode t)) (sanityinc/latex-preview-mode-changed))
    (should (sanityinc/latex-preview-untried-p 2))))

(ert-deftest sanityinc/preview-document-build-allows-refresh ()
  (sanityinc/test-with-preview-job
    (let ((aux (make-temp-file "preview-aux-test-")))
      (unwind-protect
          (cl-letf (((symbol-function 'TeX-master-output-file) (lambda (_) aux)))
            (set-file-times aux (seconds-to-time 100000))
            (sanityinc/latex-preview-run-once #'ignore 1 8)
            (sanityinc/latex-preview--watch (current-buffer) sanityinc/latex-preview--job)
            (should-not (sanityinc/latex-preview-untried-p 2))
            (set-file-times aux (seconds-to-time 100010))
            (should (sanityinc/latex-preview-untried-p 2)))
        (delete-file aux)))))

(ert-deftest sanityinc/preview-cancellation-excludes-builds-and-other-documents ()
  (with-temp-buffer
    (let ((source (current-buffer))
          (owned (generate-new-buffer " *preview-owned*"))
          (other (generate-new-buffer " *preview-other*")))
      (unwind-protect
          (progn
            (with-current-buffer owned (setq-local TeX-command-buffer source))
            (with-current-buffer other (setq-local TeX-command-buffer other))
            (cl-letf (((symbol-function 'process-list)
                       (lambda () '(root converter build foreign)))
                      ((symbol-function 'process-live-p) (lambda (_) t))
                      ((symbol-function 'process-name)
                       (lambda (p) (if (eq p 'build) "LaTeXMk" "Preview-Ghostscript")))
                      ((symbol-function 'process-buffer)
                       (lambda (p) (pcase p ('root nil) ('foreign other) (_ owned)))))
              (should (equal (sanityinc/latex-preview--processes source '(:root root))
                             '(root converter)))))
        (kill-buffer owned)
        (kill-buffer other)))))

(defmacro sanityinc/test-with-pending-preview (&rest body)
  "Run BODY with a pending preview overlay named `ov'."
  (declare (indent 0) (debug t))
  `(let* ((directory (make-temp-file "preview-cancel-test-" t))
          (TeX-active-tempdir (list directory temporary-file-directory 0))
          (source-file (expand-file-name "preview.eps" directory))
          (preview-leave-open-previews-visible nil)
          (preview-prefer-TeX-bb nil)
          (preview-gs-image-type "png")
          (preview-gs-sequence (cons 1 1))
          (preview-gs-outstanding-limit 2))
     (unwind-protect
         (with-temp-buffer
           (insert "x")
           (let ((ov (make-overlay (point-min) (point-max))))
             (with-temp-file source-file (insert "%%BoundingBox: 0 0 10 10\n"))
             (overlay-put ov 'preview-state 'active)
             (overlay-put ov 'strings (cons "" ""))
             (overlay-put ov 'queued (vector [0 0 10 10] nil 1))
             (overlay-put ov 'filenames
                          (list (preview-make-filename source-file TeX-active-tempdir)))
             ;; Only presentation is stubbed; file deletion and Ghostscript's
             ;; transaction/queue logic run as installed in AUCTeX.
             (cl-letf (((symbol-function 'preview-disabled-string) (lambda (_) ""))
                       ;; AUCTeX 14.2 calls this directly; neither renderer is
                       ;; part of the file/queue cancellation contract tested.
                       ((symbol-function 'preview--string) (lambda (&rest _) ""))
                       ((symbol-function 'preview-toggle) #'ignore))
               ,@body)))
       (when (file-exists-p source-file) (delete-file source-file))
       (when (file-directory-p directory) (delete-directory directory)))))

(ert-deftest sanityinc/preview-edit-before-render-drains-queue ()
  (sanityinc/test-with-pending-preview
    (let ((preview-gs-queue (list ov ov))
          preview-gs-outstanding eof)
      (preview-disable ov)
      (should-not (file-exists-p source-file))
      (cl-letf (((symbol-function 'process-send-eof) (lambda (_) (setq eof t)))
                ((symbol-function 'process-send-string)
                 (lambda (&rest _) (ert-fail "Cancelled preview was sent for rendering"))))
        (preview-gs-transact nil "GS>"))
      (should eof)
      (should-not preview-gs-queue)
      (should-not preview-gs-outstanding)
      (should-not (overlay-get ov 'queued)))))

(ert-deftest sanityinc/preview-edit-during-render-ignores-stale-result ()
  (sanityinc/test-with-pending-preview
    (let (preview-gs-queue (preview-gs-outstanding (list ov)) eof)
      (preview-disable ov)
      (cl-letf (((symbol-function 'process-send-eof) (lambda (_) (setq eof t)))
                ((symbol-function 'preview-replace-active-icon)
                 (lambda (&rest _) (ert-fail "Stale result replaced the edited formula"))))
        (preview-gs-transact nil "GS>"))
      (should eof)
      (should-not preview-gs-outstanding)
      (should (eq (overlay-get ov 'preview-state) 'disabled)))))

(ert-deftest sanityinc/preview-cancellation-preserves-owned-files ()
  (sanityinc/test-with-pending-preview
    (overlay-put ov 'preview-state 'disabled)
    (sanityinc/latex-preview-cancel-deleted-image ov)
    (should (overlay-get ov 'queued))
    (should (file-exists-p source-file))))

(ert-deftest sanityinc/preview-cancellation-preserves-active-work ()
  (sanityinc/test-with-pending-preview
    (sanityinc/latex-preview-cancel-deleted-image ov)
    (should (overlay-get ov 'queued))))

(ert-deftest sanityinc/preview-timer-waits-for-idle ()
  (let ((sanityinc/latex-preview-idle-delay 0.8))
    (cl-letf (((symbol-function 'input-pending-p) (lambda () nil)))
      (dolist (idle '(nil 0.1 0.79))
        (cl-letf (((symbol-function 'current-idle-time) (lambda () idle)))
          (should-not (sanityinc/latex-preview-idle-p))))
      (cl-letf (((symbol-function 'current-idle-time) (lambda () 0.8)))
        (should (sanityinc/latex-preview-idle-p)))
      (cl-letf (((symbol-function 'current-idle-time) (lambda () 5))
                ((symbol-function 'input-pending-p) (lambda () t)))
        (should-not (sanityinc/latex-preview-idle-p))))))

;;; init-latex-preview-test.el ends here
