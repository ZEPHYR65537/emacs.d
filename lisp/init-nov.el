;;; init-nov.el --- Local EPUB reader -*- lexical-binding: t; -*-
;;; Commentary:
;; Use the Git checkout in ~/.emacs.d/pkg/nov, with dependencies from ELPA.
;;; Code:

(require 'init-local-packages)
(when (and (sanityinc/enable-local-package 'nov)
           (maybe-require-package 'esxml "0.3.6"))

  (autoload 'nov-mode "nov" "Read an EPUB document." t)
  (add-to-list 'auto-mode-alist '("\\.epub\\'" . nov-mode))

  ;; A local checkout does not have package.el-generated autoloads.  Register
  ;; these entry points too, so saved bookmarks and Org links work after restart.
  (autoload 'nov-bookmark-jump-handler "nov")
  (autoload 'nov-org-link-follow "nov")
  (autoload 'nov-org-link-store "nov")
  (with-eval-after-load 'org
    (org-link-set-parameters "nov"
                             :follow #'nov-org-link-follow
                             :store #'nov-org-link-store)))

(provide 'init-nov)
;;; init-nov.el ends here
