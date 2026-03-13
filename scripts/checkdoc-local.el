;; checkdoc-local.el --- -*- lexical-binding: t; -*-

(require 'checkdoc)

(let* ((file (expand-file-name (or (car argv) "eglot-typescript-preset.el")))
       error)
  (find-file file)
  (goto-char (point-min))
  (let ((inhibit-message t)
        (message-log-max nil))
    (while (and (not error)
                (setq error (checkdoc-next-error nil)))
      nil))
  (if error
      (let ((message-text (car error))
            (position (cdr error)))
        (goto-char position)
        (princ (format "%s:%d: %s\n"
                       file
                       (line-number-at-pos position)
                       message-text))
        (kill-emacs 1))
    (princ "ok\n")))

(provide 'checkdoc-local)
;;; checkdoc-local.el ends here
