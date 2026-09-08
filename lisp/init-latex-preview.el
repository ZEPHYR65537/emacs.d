;;; init-latex-preview.el --- Reliable automatic LaTeX previews -*- lexical-binding: t; -*-
;;; Commentary:
;; Keep cancelled previews out of the converter and wait for a typing pause.
;;; Code:

(require 'seq)

(defvar preview-auto--keepalive)
(defvar preview-auto-mode)
(defvar preview-current-region)
(defvar preview-abort-flag)
(defvar TeX-command-buffer)
(defvar compilation-in-progress)

(defgroup sanityinc-latex-preview nil
  "Reliability settings for automatic LaTeX previews."
  :group 'preview)

(defcustom sanityinc/latex-preview-idle-delay 0.8
  "Seconds without input before automatic LaTeX preview may start."
  :type 'number
  :group 'sanityinc-latex-preview)

(defcustom sanityinc/latex-preview-timeout 30
  "Maximum seconds for one automatic preview attempt, including conversion.
A timed-out fragment is retried after an edit or an explicit mode restart."
  :type 'number
  :group 'sanityinc-latex-preview)

(defvar-local sanityinc/latex-preview--revision nil)
(defvar-local sanityinc/latex-preview--attempts nil)
(defvar-local sanityinc/latex-preview--job nil)

(defun sanityinc/latex-preview-preserve-source (original name &rest args)
  "Keep preview output tied to its source across ORIGINAL's mode change.
AUCTeX 14.1.2 sets the local `TeX-command-buffer' before calling
`TeX-output-mode', which clears it.  The buffer then inherits whichever
document most recently compiled from the global default."
  (let* ((source (current-buffer))
         (process (apply original name args)))
    (when (and (string-prefix-p "Preview-" name)
               (processp process) (buffer-live-p (process-buffer process)))
      (with-current-buffer (process-buffer process)
        (setq-local TeX-command-buffer source)))
    process))

(defun sanityinc/latex-preview--refresh-revision ()
  "Forget attempted regions after source edits or a document build."
  (let ((revision
         (list (buffer-chars-modified-tick)
               (ignore-errors
                 (file-attribute-modification-time
                  (file-attributes (TeX-master-output-file "aux")))))))
    (unless (equal revision sanityinc/latex-preview--revision)
      (setq sanityinc/latex-preview--revision revision
            sanityinc/latex-preview--attempts nil))))

(defun sanityinc/latex-preview-untried-p (&optional position)
  "Allow POSITION only if its fragment has not been attempted this revision.
This prevents invalid but delimited math from being compiled indefinitely.
Other fragments remain eligible even when a neighbouring fragment fails."
  (sanityinc/latex-preview--refresh-revision)
  (let ((position (or position (point))))
    (not (seq-some (lambda (range) (<= (car range) position (1- (cdr range))))
                   sanityinc/latex-preview--attempts))))

(defun sanityinc/latex-preview--processes (source job)
  "Return live preview processes belonging to SOURCE and JOB."
  (seq-filter
   (lambda (process)
     (and (process-live-p process)
          (or (eq process (plist-get job :root))
              (and (string-prefix-p "Preview-" (process-name process))
                   (buffer-live-p (process-buffer process))
                   (eq source (buffer-local-value 'TeX-command-buffer
                                                   (process-buffer process)))))))
   (process-list)))

(defun sanityinc/latex-preview--cancelled-sentinel (process _event)
  "Clean up cancelled PROCESS without starting another converter."
  (unless (process-live-p process)
    (setq compilation-in-progress (delq process compilation-in-progress))
    (when (buffer-live-p (process-buffer process))
      (with-current-buffer (process-buffer process)
        (setq mode-line-process nil)
        (when (fboundp 'preview-gs-queue-empty)
          (preview-gs-queue-empty))))))

(defun sanityinc/latex-preview--stop-process (process)
  "Stop PROCESS and its compiler children without blocking Emacs."
  (set-process-sentinel process #'sanityinc/latex-preview--cancelled-sentinel)
  (if (eq system-type 'windows-nt)
      ;; Killing only AUCTeX's sh.exe leaves pdflatex.exe running on Windows.
      ;; Keep the process alive until taskkill has identified its descendants.
      (make-process
       :name "latex-preview-cancel" :buffer nil :noquery t
       :command (list (or (executable-find "taskkill") "taskkill.exe")
                      "/PID" (number-to-string (process-id process)) "/T" "/F")
       :sentinel
       (lambda (worker _event)
         (when (and (not (process-live-p worker)) (process-live-p process))
           (message "Automatic preview cancellation failed; use M-x list-processes"))))
    (delete-process process)))

(defun sanityinc/latex-preview--cancel (source job)
  "Cancel JOB in SOURCE once, retaining it until its processes have stopped."
  (unless (plist-get job :cancelled)
    (setf (plist-get job :cancelled) t)
    (with-current-buffer source
      (setq preview-abort-flag t preview-current-region nil))
    (dolist (process (sanityinc/latex-preview--processes source job))
      (sanityinc/latex-preview--stop-process process))))

(defun sanityinc/latex-preview--watch (source job)
  "Finish JOB, or cancel it when its deadline expires."
  (let ((processes (sanityinc/latex-preview--processes source job)))
    (cond
     ((null processes)
      (cancel-timer (plist-get job :timer))
      (when (buffer-live-p source)
        (with-current-buffer source
          (when (eq job sanityinc/latex-preview--job)
            (setq sanityinc/latex-preview--job nil
                  preview-current-region nil preview-abort-flag nil)))))
     ((and (buffer-live-p source)
           (not (plist-get job :cancelled))
           (>= (float-time) (plist-get job :deadline)))
      (sanityinc/latex-preview--cancel source job)
      (message "Automatic preview timed out; edit the formula or restart preview-auto-mode")))))

(defun sanityinc/latex-preview-after-change (&rest _args)
  "Interrupt an obsolete automatic preview when its source changes."
  (when sanityinc/latex-preview--job
    (sanityinc/latex-preview--cancel (current-buffer) sanityinc/latex-preview--job))
  (setq preview-auto--keepalive t))

(defun sanityinc/latex-preview--after-change (original &rest args)
  "Use complete process cancellation for managed jobs, otherwise call ORIGINAL."
  (if sanityinc/latex-preview--job
      (sanityinc/latex-preview-after-change)
    (apply original args)))

(defun sanityinc/latex-preview-mode-changed ()
  "Allow an explicit mode restart to retry, and cancel jobs when disabling."
  (if preview-auto-mode
      (setq sanityinc/latex-preview--attempts nil sanityinc/latex-preview--revision nil)
    (when sanityinc/latex-preview--job
      (sanityinc/latex-preview--cancel (current-buffer) sanityinc/latex-preview--job))))

(defun sanityinc/latex-preview--kill-buffer ()
  "Stop automatic preview before its source buffer is killed."
  (when sanityinc/latex-preview--job
    (sanityinc/latex-preview--cancel (current-buffer) sanityinc/latex-preview--job)))

(defun sanityinc/latex-preview-run-once (original begin end)
  "Call ORIGINAL for BEGIN..END at most once per source/build revision."
  (when (and (not sanityinc/latex-preview--job)
             (sanityinc/latex-preview-untried-p begin))
    (push (cons begin end) sanityinc/latex-preview--attempts)
    (let* ((source (current-buffer))
           (job (list :root nil :cancelled nil
                      :deadline (+ (float-time) sanityinc/latex-preview-timeout)
                      :timer nil)))
      (setq sanityinc/latex-preview--job job)
      (add-hook 'after-change-functions #'sanityinc/latex-preview-after-change nil t)
      (add-hook 'kill-buffer-hook #'sanityinc/latex-preview--kill-buffer nil t)
      (setf (plist-get job :timer)
            (run-with-timer 0.3 0.3 #'sanityinc/latex-preview--watch source job))
      (condition-case err
          (save-current-buffer
            (setf (plist-get job :root) (funcall original begin end)))
        (error (message "Automatic preview: %s" (error-message-string err)))))))

(defun sanityinc/latex-preview-idle-p (&rest _args)
  "Return non-nil when automatic preview can run without interrupting typing."
  (let ((idle (current-idle-time)))
    (and idle
         (not (input-pending-p))
         (>= (float-time idle) sanityinc/latex-preview-idle-delay))))

(defun sanityinc/latex-preview-cancel-deleted-image (overlay)
  "Cancel pending rendering for OVERLAY after its files have been discarded.
AUCTeX 14.1.2 leaves `queued' set when `preview-disable' deletes the
overlay's files.  Ghostscript then treats its future PNG as an input
file and stalls with a file-missing error.  Clearing `queued' lets its
normal transaction handler skip the cancelled work and finish.
Leave overlays which still own files alone, including versions of
AUCTeX that retain files until a pending conversion finishes."
  (when (and (eq (overlay-get overlay 'preview-state) 'disabled)
             (null (overlay-get overlay 'filenames)))
    (overlay-put overlay 'queued nil)))

(with-eval-after-load 'preview
  (advice-add 'preview-disable :after
              #'sanityinc/latex-preview-cancel-deleted-image))

(with-eval-after-load 'tex
  (advice-add 'TeX-run-command :around #'sanityinc/latex-preview-preserve-source))

(with-eval-after-load 'preview-auto
  (advice-add 'preview-auto--timer-function :before-while
              #'sanityinc/latex-preview-idle-p)
  (advice-add 'preview-auto--allow-at :before-while
              #'sanityinc/latex-preview-untried-p)
  (advice-add 'preview-auto-preview-region :around
              #'sanityinc/latex-preview-run-once)
  (advice-add 'preview-auto--after-change :around
              #'sanityinc/latex-preview--after-change)
  (add-hook 'preview-auto-mode-hook #'sanityinc/latex-preview-mode-changed))

(provide 'init-latex-preview)
;;; init-latex-preview.el ends here
