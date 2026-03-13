;; melpa-build-install-check.el --- -*- lexical-binding: t; -*-

(require 'package)

(defun melpa-build-install-check--plist-remove (plist key)
  "Return PLIST without KEY."
  (let (result)
    (while plist
      (let ((current-key (pop plist))
            (current-value (pop plist)))
        (unless (eq current-key key)
          (setq result (plist-put result current-key current-value)))))
    result))

(defun melpa-build-install-check--read-recipe (path)
  "Return the recipe form stored at PATH."
  (with-temp-buffer
    (insert-file-contents path)
    (goto-char (point-min))
    (read (current-buffer))))

(defun melpa-build-install-check--write-local-recipe (source-file dest-file snapshot-repo)
  "Write a local package-build recipe from SOURCE-FILE to DEST-FILE.

SNAPSHOT-REPO is the git repository to package."
  (let* ((recipe (melpa-build-install-check--read-recipe source-file))
         (package-name (car recipe))
         (plist (melpa-build-install-check--plist-remove (cdr recipe) :repo)))
    (setq plist (plist-put plist :fetcher 'git))
    (setq plist (plist-put plist :url snapshot-repo))
    (with-temp-file dest-file
      (prin1 (cons package-name plist) (current-buffer))
      (terpri (current-buffer)))))

(let* ((topdir (expand-file-name (or (car argv) default-directory)))
       (melpa-root (expand-file-name (or (cadr argv)
                                         (error "Missing MELPA root argument"))))
       (temp-root (expand-file-name (or (caddr argv)
                                        (error "Missing temp root argument"))))
       (recipe-file (expand-file-name (or (cadddr argv)
                                          (error "Missing recipe file argument"))))
       (snapshot-repo (expand-file-name (or (car (cddddr argv))
                                            (error "Missing snapshot repo argument"))))
       (package-name (file-name-base recipe-file))
       (recipes-dir (expand-file-name "recipes" temp-root))
       (archive-dir (expand-file-name "packages" temp-root))
       (install-dir (expand-file-name "elpa" temp-root))
       (build-working-dir (expand-file-name "build" temp-root)))
  (add-to-list 'load-path (expand-file-name "package-build" melpa-root))
  (require 'package-build)
  (setq package-user-dir install-dir
        package-build-working-dir build-working-dir
        package-build-recipes-dir recipes-dir
        package-build-archive-dir archive-dir)

  (dolist (dir (list recipes-dir archive-dir install-dir build-working-dir))
    (when (file-directory-p dir)
      (delete-directory dir t)))
  (make-directory recipes-dir t)
  (make-directory archive-dir t)
  (make-directory install-dir t)
  (make-directory build-working-dir t)

  (melpa-build-install-check--write-local-recipe
   recipe-file
   (expand-file-name package-name recipes-dir)
   snapshot-repo)

  (package-initialize)
  (setq package-build--inhibit-cleanup t)

  (let* ((rcp (package-recipe-lookup package-name))
         (tar-file nil)
         (installed-template nil))
    (package-build--fetch rcp)
    (package-build--select-version rcp)
    (package-build--package rcp)
    (setq tar-file
          (car (directory-files package-build-archive-dir t
                                "^eglot-typescript-preset-.*\\.tar$")))
    (unless tar-file
      (error "No package tar produced in %s" package-build-archive-dir))
    (package-install-file tar-file)
    (setq installed-template
          (car (directory-files-recursively package-user-dir
                                            "rass-preset\\.tpl\\.py$" t)))
    (unless installed-template
      (error "Installed package is missing templates/rass-preset.tpl.py"))
    (princ (format "ok\narchive=%s\ninstalled=%s\n"
                   tar-file
                   installed-template))))

(provide 'melpa-build-install-check)
;;; melpa-build-install-check.el ends here
