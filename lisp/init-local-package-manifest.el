;;; init-local-package-manifest.el --- Local dependency versions -*- lexical-binding: t; -*-
;;; Commentary:
;; Independent repositories, with enough information to restore a new machine.
;; Update revisions deliberately after testing.  No network work happens here.
;;; Code:

(defconst sanityinc/local-package-specs
  '((comb-grid
     :directory "comb-grid" :library "comb-grid.el" :emacs "29.1"
     :url "https://github.com/ZEPHYR65537/comb-grid.git"
     :revision "093a6f933c1acf2b79b0f9d13dfaaccde74bae1b")
    (mmix-mode
     :directory "mmix-mode" :library "mmix-mode.el" :emacs "27.2"
     :url "https://github.com/ppareit/mmix-mode.git"
     :revision "93d9012ef68809d9b58e250cf412de152b0e1cba"
     :patch "patches/mmix-shell-free.patch")
    (nov
     :directory "nov" :library "nov.el" :emacs "25.1"
     :url "https://depp.brause.cc/nov.el.git"
     :revision "874daf5e4791a6d4f47741422c80e2736e907351")
    (static-site
     :directory "static_site" :library "static-site.el" :emacs "28.1"
     :url "https://github.com/ZEPHYR65537/tex2ss.git"
     :revision "57d6b56e8a77c3cca948c5ff7163460ab52a92ca"))
  "Local package sources, recorded commits, minimum Emacs and maintained patches.")

(provide 'init-local-package-manifest)
;;; init-local-package-manifest.el ends here
