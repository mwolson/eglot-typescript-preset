;;; test/test.el --- ERT tests for eglot-typescript-preset -*- lexical-binding: t; -*-

(add-to-list 'load-path (file-name-directory load-file-name))
(add-to-list 'load-path (expand-file-name ".." (file-name-directory load-file-name)))

(require 'cl-lib)
(require 'ert)
(require 'json)
(require 'project)
(require 'wid-edit)
(require 'eglot-typescript-preset)

(defvar eglot-server-programs nil)
(defvar eglot-workspace-configuration nil)
(defvar project-find-functions nil)

(defun my-test--display-warning-fail (type message &optional _level _buffer-name)
  "Fail the current test for warning TYPE with MESSAGE."
  (ert-fail (format "Unexpected warning (%s): %s" type message)))

(advice-add 'display-warning :override #'my-test--display-warning-fail)

(defvar my-test-run-live-tests nil)
(defvar my-test-test-dir (file-name-directory load-file-name))
(defvar my-test-fixtures-dir
  (expand-file-name "fixtures/" my-test-test-dir))
(defvar my-test-project-dir
  (expand-file-name ".." my-test-test-dir))
(defvar my-test-local-bin-dir
  (expand-file-name "node_modules/.bin/" my-test-project-dir))
(defvar my-test-local-tsdk
  (expand-file-name "node_modules/typescript/lib/" my-test-project-dir))
(defvar my-test-argv-lsp-server
  (expand-file-name "argv-lsp-server.py" my-test-test-dir))
(defvar my-test-live-rass-client
  (expand-file-name "rass-live-client.py" my-test-test-dir))
(defvar my-test-rass-template-unit
  (expand-file-name "rass-template-unit.py" my-test-test-dir))

(defun my-test-write-executable (path)
  "Create an executable file at PATH."
  (with-temp-file path
    (insert "#!/bin/bash\nexit 0\n"))
  (set-file-modes path #o755))

(defun my-test-write-node-launcher (path target &optional args)
  "Create a shell launcher at PATH that execs TARGET with ARGS."
  (with-temp-file path
    (insert "#!/bin/bash\n")
    (insert (format "exec %s" (shell-quote-argument target)))
    (dolist (arg args)
      (insert " " (shell-quote-argument arg)))
    (insert " \"$@\"\n"))
  (set-file-modes path #o755))

(defun my-test-fixture-content (name)
  "Return the contents of fixture file NAME."
  (with-temp-buffer
    (insert-file-contents (expand-file-name name my-test-fixtures-dir))
    (buffer-string)))

(defun my-test-copy-fixture (name target-dir &optional target-name)
  "Copy fixture NAME into TARGET-DIR.  Return the new path.
If TARGET-NAME is non-nil, rename the file."
  (let ((src (expand-file-name name my-test-fixtures-dir))
        (dst (expand-file-name (or target-name name) target-dir)))
    (copy-file src dst t)
    dst))

(defun my-test-copy-fixture-dir (name target-dir)
  "Copy fixture subdirectory NAME into TARGET-DIR.  Return the new path."
  (let ((src (expand-file-name name my-test-fixtures-dir))
        (dst (expand-file-name name target-dir)))
    (copy-directory src dst nil t t)
    dst))

(defun my-test--with-tmp-dir (fn)
  "Call FN with a temporary directory, cleaned up afterward."
  (let ((tmp (make-temp-file "eglot-ts-test-" t)))
    (unwind-protect
        (funcall fn tmp)
      (delete-directory tmp t))))

(defmacro my-test-with-tmp-dir (var &rest body)
  "Bind VAR to a temporary directory, evaluate BODY, then clean up."
  (declare (indent 1))
  `(my-test--with-tmp-dir (lambda (,var) ,@body)))

(defun my-test--with-project-env (tmp-dir fn)
  "Call FN with eglot-typescript-preset variables scoped to TMP-DIR."
  (let ((eglot-typescript-preset-lsp-server 'typescript-language-server)
        (eglot-typescript-preset-astro-lsp-server 'astro-ls)
        (eglot-typescript-preset-rass-program "rass")
        (eglot-typescript-preset-rass-command nil)
        (eglot-typescript-preset-astro-rass-command nil)
        (eglot-typescript-preset-rass-tools
         '(typescript-language-server eslint))
        (eglot-typescript-preset-astro-rass-tools
         '(astro-ls eslint))
        (eglot-typescript-preset-css-lsp-server 'rass)
        (eglot-typescript-preset-css-rass-command nil)
        (eglot-typescript-preset-css-rass-tools
         '(vscode-css-language-server tailwindcss-language-server))
        (eglot-typescript-preset-vue-lsp-server 'vue-language-server)
        (eglot-typescript-preset-vue-rass-command nil)
        (eglot-typescript-preset-vue-rass-tools
         '(vue-language-server tailwindcss-language-server))
        (eglot-typescript-preset-rass-max-contextual-presets 50)
        (eglot-typescript-preset-tsdk nil)
        (eglot-typescript-preset-js-project-markers
         '("package.json" "tsconfig.json" "jsconfig.json"))
        (eglot-typescript-preset-js-modes
         '(jtsx-jsx-mode jtsx-tsx-mode jtsx-typescript-mode
           js-mode js-ts-mode typescript-ts-mode tsx-ts-mode))
        (eglot-typescript-preset-astro-modes '(astro-ts-mode))
        (eglot-typescript-preset-css-modes '(css-mode css-ts-mode))
        (eglot-typescript-preset-vue-modes '(vue-mode vue-ts-mode))
        (user-emacs-directory (file-name-as-directory tmp-dir)))
    (funcall fn)))

(defmacro my-test-with-project-env (tmp-dir &rest body)
  "Set up a project environment in TMP-DIR, evaluate BODY."
  (declare (indent 1))
  `(my-test--with-project-env ,tmp-dir (lambda () ,@body)))


;;; --- Project detection tests ---

(ert-deftest ts-preset--project-find-package-json ()
  "Detect JS project by package.json."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((project-dir (expand-file-name "myproject/" tmp-dir))
             (src-dir (expand-file-name "src/" project-dir))
             (eglot-lsp-context t))
        (make-directory src-dir t)
        (with-temp-file (expand-file-name "package.json" project-dir)
          (insert "{}"))
        (let ((result (eglot-typescript-preset--project-find src-dir)))
          (should result)
          (should (eq (car result) 'js-project))
          (should (string= (cdr result)
                           (file-name-as-directory project-dir))))))))

(ert-deftest ts-preset--project-find-tsconfig ()
  "Detect JS project by tsconfig.json."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((project-dir (expand-file-name "myproject/" tmp-dir))
             (src-dir (expand-file-name "src/" project-dir))
             (eglot-lsp-context t))
        (make-directory src-dir t)
        (with-temp-file (expand-file-name "tsconfig.json" project-dir)
          (insert "{}"))
        (let ((result (eglot-typescript-preset--project-find src-dir)))
          (should result)
          (should (eq (car result) 'js-project)))))))

(ert-deftest ts-preset--project-find-jsconfig ()
  "Detect JS project by jsconfig.json."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((project-dir (expand-file-name "myproject/" tmp-dir))
             (src-dir (expand-file-name "src/" project-dir))
             (eglot-lsp-context t))
        (make-directory src-dir t)
        (with-temp-file (expand-file-name "jsconfig.json" project-dir)
          (insert "{}"))
        (let ((result (eglot-typescript-preset--project-find src-dir)))
          (should result)
          (should (eq (car result) 'js-project)))))))

(ert-deftest ts-preset--project-find-none ()
  "Return nil when no project markers found."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((project-dir (expand-file-name "noproject/" tmp-dir))
             (eglot-lsp-context t))
        (make-directory project-dir t)
        (should-not (eglot-typescript-preset--project-find project-dir))))))

(ert-deftest ts-preset--project-root ()
  "Project root returns the correct directory."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((project-dir (expand-file-name "myproject/" tmp-dir))
             (src-file (expand-file-name "src/index.ts" project-dir)))
        (make-directory (file-name-directory src-file) t)
        (with-temp-file (expand-file-name "package.json" project-dir)
          (insert "{}"))
        (with-temp-file src-file (insert ""))
        (with-current-buffer (find-file-noselect src-file)
          (unwind-protect
              (should (string= (eglot-typescript-preset--project-root)
                               (file-name-as-directory project-dir)))
            (kill-buffer)))))))


(ert-deftest ts-preset--project-find-without-lsp-context ()
  "Return nil when eglot-lsp-context is not set."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((project-dir (expand-file-name "myproject/" tmp-dir))
             (src-dir (expand-file-name "src/" project-dir))
             (eglot-lsp-context nil))
        (make-directory src-dir t)
        (with-temp-file (expand-file-name "package.json" project-dir)
          (insert "{}"))
        (should-not (eglot-typescript-preset--project-find src-dir))))))

(ert-deftest ts-preset--monorepo-project-boundary ()
  "In a monorepo, project-find-file escapes the LSP project boundary.
With eglot-lsp-context, --project-find scopes to the JS project.
Without it, project-try-vc returns the git root, and project-files
respects .gitignore (excludes dist/) while including files outside
the JS project boundary."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((monorepo-dir (my-test-copy-fixture-dir "monorepo" tmp-dir))
             (frontend-dir (expand-file-name "frontend/" monorepo-dir))
             (frontend-src (expand-file-name "src/" frontend-dir))
             (frontend-dist (expand-file-name "dist/" frontend-dir))
             (default-directory monorepo-dir))
        ;; Initialize git repo and commit the fixture files
        (call-process "git" nil nil nil "init" "-q" monorepo-dir)
        (call-process "git" nil nil nil "-C" monorepo-dir "add" ".")
        (call-process "git" nil nil nil "-C" monorepo-dir
                      "-c" "user.name=Test" "-c" "user.email=test@test"
                      "commit" "-q" "-m" "init")
        ;; Create dist/ file after commit (gitignored build output)
        (make-directory frontend-dist t)
        (with-temp-file (expand-file-name "bundle.js" frontend-dist)
          (insert "compiled output\n"))
        ;; 1. With eglot-lsp-context, project-find scopes to frontend
        (let ((eglot-lsp-context t))
          (let ((result (eglot-typescript-preset--project-find frontend-src)))
            (should result)
            (should (eq (car result) 'js-project))
            (should (string= (cdr result)
                             (file-name-as-directory frontend-dir)))))
        ;; 2. Without eglot-lsp-context, project-find returns nil
        (let ((eglot-lsp-context nil))
          (should-not (eglot-typescript-preset--project-find frontend-src)))
        ;; 3. project-try-vc finds the git root (monorepo root)
        (let ((vc-project (project-try-vc frontend-src)))
          (should vc-project)
          (should (string= (file-name-as-directory monorepo-dir)
                           (project-root vc-project)))
          ;; 4. project-files includes backend but excludes dist/
          (let ((files (project-files vc-project)))
            (should (cl-some (lambda (f) (string-suffix-p "backend/server.js" f))
                             files))
            (should (cl-some (lambda (f) (string-suffix-p "frontend/src/index.ts" f))
                             files))
            (should-not (cl-some (lambda (f) (string-match-p "dist/" f))
                                 files))))))))


;;; --- TSDK detection tests ---

(ert-deftest ts-preset--find-tsdk-explicit ()
  "Return explicit tsdk when set."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-tsdk "/custom/typescript/lib"))
        (should (string= (eglot-typescript-preset--find-tsdk)
                         "/custom/typescript/lib"))))))


;;; --- Executable resolution tests ---

(ert-deftest ts-preset--resolve-executable-from-node-modules ()
  "Prefer node_modules/.bin executables."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((project-dir (expand-file-name "myproject/" tmp-dir))
             (bin-dir (expand-file-name "node_modules/.bin/" project-dir))
             (ts-server (expand-file-name "typescript-language-server" bin-dir))
             (src-file (expand-file-name "index.ts" project-dir)))
        (make-directory bin-dir t)
        (with-temp-file (expand-file-name "package.json" project-dir)
          (insert "{}"))
        (my-test-write-executable ts-server)
        (with-temp-buffer
          (setq buffer-file-name src-file)
          (let ((resolved (eglot-typescript-preset--resolve-executable
                           "typescript-language-server")))
            (should (string= resolved ts-server))))))))

(ert-deftest ts-preset--resolve-executable-fallback ()
  "Fall back to PATH when no node_modules."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((project-dir (expand-file-name "myproject/" tmp-dir))
             (src-file (expand-file-name "index.ts" project-dir)))
        (make-directory project-dir t)
        (with-temp-file (expand-file-name "package.json" project-dir)
          (insert "{}"))
        (with-temp-buffer
          (setq buffer-file-name src-file)
          (let ((resolved (eglot-typescript-preset--resolve-executable
                           "nonexistent-binary-xyz")))
            (should (string= resolved "nonexistent-binary-xyz"))))))))


;;; --- Tool kind tests ---

(ert-deftest ts-preset--tool-kind-from-name ()
  "Identify known tool kinds from executable names."
  (should (eq (eglot-typescript-preset--tool-kind-from-name
               "typescript-language-server")
              'typescript-language-server))
  (should (eq (eglot-typescript-preset--tool-kind-from-name "biome")
              'biome))
  (should (eq (eglot-typescript-preset--tool-kind-from-name
               "vscode-eslint-language-server")
              'eslint))
  (should (eq (eglot-typescript-preset--tool-kind-from-name
               "eslint-language-server")
              'eslint))
  (should (eq (eglot-typescript-preset--tool-kind-from-name "eslint")
              'eslint))
  (should (eq (eglot-typescript-preset--tool-kind-from-name "oxlint")
              'oxlint))
  (should (eq (eglot-typescript-preset--tool-kind-from-name "oxfmt")
              'oxfmt))
  (should (eq (eglot-typescript-preset--tool-kind-from-name "astro-ls")
              'astro-ls))
  (should (eq (eglot-typescript-preset--tool-kind-from-name "deno")
              'deno))
  (should (eq (eglot-typescript-preset--tool-kind-from-name
               "tailwindcss-language-server")
              'tailwindcss-language-server))
  (should (eq (eglot-typescript-preset--tool-kind-from-name
               "vscode-css-language-server")
              'vscode-css-language-server))
  (should (eq (eglot-typescript-preset--tool-kind-from-name
               "css-language-server")
              'vscode-css-language-server))
  (should (eq (eglot-typescript-preset--tool-kind-from-name
               "vue-language-server")
              'vue-language-server))
  (should-not (eglot-typescript-preset--tool-kind-from-name "unknown-tool"))
  (should-not (eglot-typescript-preset--tool-kind-from-name nil)))


;;; --- Tool command tests ---

(ert-deftest ts-preset--rass-tool-command-typescript ()
  "Generate typescript-language-server command."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((cmd (eglot-typescript-preset--rass-tool-command
                  'typescript-language-server)))
        (should (equal (cadr cmd) "--stdio"))))))

(ert-deftest ts-preset--rass-tool-command-eslint ()
  "Generate ESLint command."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((cmd (eglot-typescript-preset--rass-tool-command 'eslint)))
        (should (equal (cadr cmd) "--stdio"))))))

(ert-deftest ts-preset--rass-tool-command-biome ()
  "Generate Biome command."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((cmd (eglot-typescript-preset--rass-tool-command 'biome)))
        (should (equal (cadr cmd) "lsp-proxy"))))))

(ert-deftest ts-preset--rass-tool-command-oxlint ()
  "Generate oxlint command."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((cmd (eglot-typescript-preset--rass-tool-command 'oxlint)))
        (should (equal (cadr cmd) "--lsp"))))))

(ert-deftest ts-preset--rass-tool-command-oxfmt ()
  "Generate oxfmt command."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((cmd (eglot-typescript-preset--rass-tool-command 'oxfmt)))
        (should (equal (cadr cmd) "--lsp"))))))

(ert-deftest ts-preset--rass-tool-command-astro ()
  "Generate astro-ls command."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((cmd (eglot-typescript-preset--rass-tool-command 'astro-ls)))
        (should (equal (cadr cmd) "--stdio"))))))

(ert-deftest ts-preset--rass-tool-command-tailwindcss ()
  "Generate tailwindcss-language-server command."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((cmd (eglot-typescript-preset--rass-tool-command
                  'tailwindcss-language-server)))
        (should (equal (cadr cmd) "--stdio"))))))

(ert-deftest ts-preset--rass-tool-command-vscode-css ()
  "Generate vscode-css-language-server command."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((cmd (eglot-typescript-preset--rass-tool-command
                  'vscode-css-language-server)))
        (should (equal (cadr cmd) "--stdio"))))))

(ert-deftest ts-preset--rass-tool-command-vue ()
  "Generate vue-language-server command."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((cmd (eglot-typescript-preset--rass-tool-command
                  'vue-language-server)))
        (should (equal (cadr cmd) "--stdio"))))))

(ert-deftest ts-preset--rass-tool-command-vector ()
  "Pass through vector commands with executable resolution."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((cmd (eglot-typescript-preset--rass-tool-command
                  ["custom-tool" "--flag"])))
        (should (equal cmd '("custom-tool" "--flag")))))))

(ert-deftest ts-preset--rass-tool-command-unsupported ()
  "Error on unsupported tool entries."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (should-error (eglot-typescript-preset--rass-tool-command 'bad-tool)
                    :type 'user-error))))


;;; --- Tool label tests ---

(ert-deftest ts-preset--rass-tool-label-symbols ()
  "Generate labels from tool symbols."
  (should (string= (eglot-typescript-preset--rass-tool-label
                     'typescript-language-server)
                    "typescript-language-server"))
  (should (string= (eglot-typescript-preset--rass-tool-label 'eslint)
                    "eslint"))
  (should (string= (eglot-typescript-preset--rass-tool-label 'biome)
                    "biome"))
  (should (string= (eglot-typescript-preset--rass-tool-label 'oxlint)
                    "oxlint"))
  (should (string= (eglot-typescript-preset--rass-tool-label 'oxfmt)
                    "oxfmt"))
  (should (string= (eglot-typescript-preset--rass-tool-label 'astro-ls)
                    "astro-ls"))
  (should (string= (eglot-typescript-preset--rass-tool-label
                     'tailwindcss-language-server)
                    "tailwindcss-language-server"))
  (should (string= (eglot-typescript-preset--rass-tool-label
                     'vscode-css-language-server)
                    "vscode-css-language-server"))
  (should (string= (eglot-typescript-preset--rass-tool-label
                     'vue-language-server)
                    "vue-language-server")))

(ert-deftest ts-preset--rass-tool-label-vector-single ()
  "Generate label from single-element vector."
  (should (string= (eglot-typescript-preset--rass-tool-label ["biome"])
                    "biome")))

(ert-deftest ts-preset--rass-tool-label-vector-multi ()
  "Generate hash-based label from multi-element vector."
  (let ((label (eglot-typescript-preset--rass-tool-label
                ["oxlint" "--config" "strict"])))
    (should (string-match-p "^oxlint-argv-" label))))


;;; --- Rass preset generation tests ---

(ert-deftest ts-preset--rass-shared-preset-path ()
  "Generate stable shared preset path."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((path1 (eglot-typescript-preset--rass-shared-preset-path
                     '(typescript-language-server eslint)))
            (path2 (eglot-typescript-preset--rass-shared-preset-path
                     '(typescript-language-server eslint))))
        (should (string= path1 path2))
        (should (string-match-p "rass-preset-shared-" path1))
        (should (string-match-p "\\.py\\'" path1))))))

(ert-deftest ts-preset--rass-shared-preset-different-tools ()
  "Different tools produce different shared preset paths."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((path1 (eglot-typescript-preset--rass-shared-preset-path
                     '(typescript-language-server eslint)))
            (path2 (eglot-typescript-preset--rass-shared-preset-path
                     '(typescript-language-server biome))))
        (should-not (string= path1 path2))))))

(ert-deftest ts-preset--rass-contextual-preset-path ()
  "Generate contextual preset path."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((path (eglot-typescript-preset--rass-contextual-preset-path
                   "test-hash-input")))
        (should (string-match-p "rass-preset-contextual-" path))
        (should (string-match-p "\\.py\\'" path))))))


;;; --- Preset write tests ---

(ert-deftest ts-preset--write-rass-preset-basic ()
  "Write a basic rass preset."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((path (expand-file-name "test-preset.py"
                                     (expand-file-name
                                      "eglot-typescript-preset/" tmp-dir))))
        (make-directory (file-name-directory path) t)
        (eglot-typescript-preset--write-rass-preset
         path
         '(("typescript-language-server" "--stdio")
           ("biome" "lsp-proxy"))
         nil
         nil)
        (should (file-exists-p path))
        (let ((content (with-temp-buffer
                         (insert-file-contents path)
                         (buffer-string))))
          (should (string-match-p "SERVERS" content))
          (should (string-match-p "INIT_OPTIONS = None" content))
          (should (string-match-p "ESLINT_LOGIC = False" content)))))))

(ert-deftest ts-preset--write-rass-preset-with-eslint ()
  "Write a rass preset with ESLint logic enabled."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((path (expand-file-name "test-eslint.py"
                                     (expand-file-name
                                      "eglot-typescript-preset/" tmp-dir))))
        (make-directory (file-name-directory path) t)
        (eglot-typescript-preset--write-rass-preset
         path
         '(("typescript-language-server" "--stdio")
           ("vscode-eslint-language-server" "--stdio"))
         nil
         t)
        (let ((content (with-temp-buffer
                         (insert-file-contents path)
                         (buffer-string))))
          (should (string-match-p "ESLINT_LOGIC = True" content)))))))

(ert-deftest ts-preset--write-rass-preset-with-astro ()
  "Write a rass preset with Astro init options."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((path (expand-file-name "test-astro.py"
                                     (expand-file-name
                                      "eglot-typescript-preset/" tmp-dir))))
        (make-directory (file-name-directory path) t)
        (eglot-typescript-preset--write-rass-preset
         path
         '(("astro-ls" "--stdio")
           ("vscode-eslint-language-server" "--stdio"))
         '(:contentIntellisense t :typescript (:tsdk "/path/to/tsdk"))
         t)
        (let ((content (with-temp-buffer
                         (insert-file-contents path)
                         (buffer-string))))
          (should (string-match-p "contentIntellisense" content))
          (should (string-match-p "ESLINT_LOGIC = True" content)))))))

(ert-deftest ts-preset--write-file-if-changed-no-rewrite ()
  "Do not rewrite file when content is identical."
  (my-test-with-tmp-dir tmp-dir
    (let ((path (expand-file-name "test-file.txt" tmp-dir))
          (content "hello world"))
      (eglot-typescript-preset--write-file-if-changed path content)
      (let ((mtime1 (file-attribute-modification-time
                     (file-attributes path))))
        (sleep-for 0.1)
        (eglot-typescript-preset--write-file-if-changed path content)
        (let ((mtime2 (file-attribute-modification-time
                       (file-attributes path))))
          (should (equal mtime1 mtime2)))))))

(ert-deftest ts-preset--write-file-if-changed-rewrite ()
  "Rewrite file when content differs."
  (my-test-with-tmp-dir tmp-dir
    (let ((path (expand-file-name "test-file.txt" tmp-dir)))
      (eglot-typescript-preset--write-file-if-changed path "old content")
      (let ((mtime1 (file-attribute-modification-time
                     (file-attributes path))))
        (sleep-for 0.1)
        (eglot-typescript-preset--write-file-if-changed path "new content")
        (let ((mtime2 (file-attribute-modification-time
                       (file-attributes path))))
          (should-not (equal mtime1 mtime2)))))))


;;; --- Preset cleanup tests ---

(ert-deftest ts-preset--cleanup-contextual-presets ()
  "Clean up older contextual presets beyond the limit."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-rass-max-contextual-presets 2)
            (dir (expand-file-name "eglot-typescript-preset/" tmp-dir)))
        (make-directory dir t)
        (dotimes (i 4)
          (let ((path (expand-file-name
                       (format "rass-preset-contextual-%d.py" i) dir)))
            (with-temp-file path
              (insert (format "preset %d" i)))
            (sleep-for 0.1)))
        (eglot-typescript-preset--cleanup-rass-contextual-presets)
        (let ((remaining (directory-files
                          dir nil "^rass-preset-contextual-.*\\.py\\'")))
          (should (= (length remaining) 2)))))))

(ert-deftest ts-preset--cleanup-preserves-path ()
  "Cleanup preserves the specified path."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((eglot-typescript-preset-rass-max-contextual-presets 1)
             (dir (expand-file-name "eglot-typescript-preset/" tmp-dir))
             (preserve (expand-file-name
                        "rass-preset-contextual-keep.py" dir)))
        (make-directory dir t)
        (with-temp-file preserve
          (insert "keep me"))
        (sleep-for 0.1)
        (with-temp-file (expand-file-name
                         "rass-preset-contextual-old.py" dir)
          (insert "old"))
        (eglot-typescript-preset--cleanup-rass-contextual-presets preserve)
        (should (file-exists-p preserve))))))


;;; --- Rass preset path integration tests ---

(ert-deftest ts-preset--rass-preset-path-shared ()
  "Generate shared preset for global tools."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((eglot-typescript-preset-rass-tools
              '(typescript-language-server biome))
             (path (eglot-typescript-preset--rass-preset-path
                    eglot-typescript-preset-rass-tools nil)))
        (should path)
        (should (file-exists-p path))
        (should (string-match-p "rass-preset-shared-" path))))))

(ert-deftest ts-preset--rass-preset-path-shared-reuse ()
  "Shared presets are reused for same tools."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((eglot-typescript-preset-rass-tools
              '(typescript-language-server eslint))
             (path1 (eglot-typescript-preset--rass-preset-path
                     eglot-typescript-preset-rass-tools nil))
             (path2 (eglot-typescript-preset--rass-preset-path
                     eglot-typescript-preset-rass-tools nil)))
        (should (string= path1 path2))))))

(ert-deftest ts-preset--rass-preset-path-nil-when-command ()
  "Return nil when rass-command is set."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (should-not (eglot-typescript-preset--rass-preset-path
                   eglot-typescript-preset-rass-tools
                   ["rass" "tslint"])))))

(ert-deftest ts-preset--rass-preset-path-contextual-with-astro ()
  "Generate contextual preset when astro-ls is in tools."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((eglot-typescript-preset-tsdk "/fake/tsdk")
             (tools '(astro-ls eslint))
             (path (eglot-typescript-preset--rass-preset-path tools nil)))
        (should path)
        (should (file-exists-p path))
        (should (string-match-p "rass-preset-contextual-" path))))))

(ert-deftest ts-preset--rass-preset-path-contextual-with-node-modules ()
  "Generate contextual preset when tools resolve to node_modules."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((project-dir (expand-file-name "myproject/" tmp-dir))
             (bin-dir (expand-file-name "node_modules/.bin/" project-dir))
             (src-file (expand-file-name "index.ts" project-dir)))
        (make-directory bin-dir t)
        (with-temp-file (expand-file-name "package.json" project-dir)
          (insert "{}"))
        (my-test-write-executable
         (expand-file-name "typescript-language-server" bin-dir))
        (my-test-write-executable
         (expand-file-name "vscode-eslint-language-server" bin-dir))
        (with-temp-buffer
          (setq buffer-file-name src-file)
          (let ((path (eglot-typescript-preset--rass-preset-path
                       '(typescript-language-server eslint) nil)))
            (should path)
            (should (string-match-p "rass-preset-contextual-" path))))))))


;;; --- Template rendering tests ---

(ert-deftest ts-preset--template-unit-basic ()
  "Validate the generated template via Python helper."
  (skip-unless (executable-find "python3"))
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((eglot-typescript-preset-rass-tools
              '(typescript-language-server biome))
             (path (eglot-typescript-preset--rass-preset-path
                    eglot-typescript-preset-rass-tools nil)))
        (should path)
        (let* ((output (shell-command-to-string
                        (format "python3 %s %s"
                                (shell-quote-argument my-test-rass-template-unit)
                                (shell-quote-argument path))))
               (result (json-parse-string output :object-type 'alist)))
          (let-alist result
            (should (equal .eslintLogic :false))
            (should (equal .initOptions :null))
            (should (equal .initOptionsScoping :null))
            (should .hasLogicClass)
            (let-alist .serverKind
              (should (equal .typescript-language-server
                             "typescript-language-server"))
              (should (equal .biome "biome"))
              (should (equal .deno "deno"))
              (should (equal .eslint "eslint"))
              (should (equal .oxlint "oxlint"))
              (should (equal .oxfmt "oxfmt"))
              (should (equal .astro-ls "astro-ls"))
              (should (equal .tailwindcss-language-server
                             "tailwindcss-language-server"))
              (should (equal .vscode-css-language-server
                             "vscode-css-language-server"))
              (should (equal .vue-language-server "vue-language-server"))
              (should (equal .unknown :null)))))))))

(ert-deftest ts-preset--template-unit-eslint ()
  "Validate template with ESLint logic enabled."
  (skip-unless (executable-find "python3"))
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((eglot-typescript-preset-rass-tools
              '(typescript-language-server eslint))
             (path (eglot-typescript-preset--rass-preset-path
                    eglot-typescript-preset-rass-tools nil)))
        (should path)
        (let* ((output (shell-command-to-string
                        (format "python3 %s %s"
                                (shell-quote-argument my-test-rass-template-unit)
                                (shell-quote-argument path))))
               (result (json-parse-string output :object-type 'alist)))
          (let-alist result
            (should (not (equal .eslintLogic :false)))))))))

(ert-deftest ts-preset--template-unit-astro ()
  "Validate template with Astro init options."
  (skip-unless (executable-find "python3"))
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((eglot-typescript-preset-tsdk "/fake/lib")
             (tools '(astro-ls eslint))
             (path (eglot-typescript-preset--rass-preset-path tools nil)))
        (should path)
        (let* ((output (shell-command-to-string
                        (format "python3 %s %s"
                                (shell-quote-argument my-test-rass-template-unit)
                                (shell-quote-argument path))))
               (result (json-parse-string output :object-type 'alist)))
          (let-alist result
            (should (not (equal .initOptions :null)))
            (should (not (equal .eslintLogic :false)))
            (let-alist .initOptionsScoping
              (should (not (equal .primaryGotOptions :false)))
              (should (equal .secondaryGotOptions :false)))))))))

(ert-deftest ts-preset--template-unit-vue ()
  "Validate template with Vue init options."
  (skip-unless (executable-find "python3"))
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((eglot-typescript-preset-tsdk "/fake/lib")
             (tools '(vue-language-server tailwindcss-language-server))
             (path (eglot-typescript-preset--rass-preset-path tools nil)))
        (should path)
        (let* ((output (shell-command-to-string
                        (format "python3 %s %s"
                                (shell-quote-argument my-test-rass-template-unit)
                                (shell-quote-argument path))))
               (result (json-parse-string output :object-type 'alist)))
          (let-alist result
            (should (not (equal .initOptions :null)))
            (should (equal .eslintLogic :false))
            (let-alist .initOptionsScoping
              (should (not (equal .primaryGotOptions :false)))
              (should (equal .secondaryGotOptions :false)))))))))

(ert-deftest ts-preset--template-unit-ts-eslint-oxlint ()
  "Validate template with typescript-language-server + eslint + oxlint."
  (skip-unless (executable-find "python3"))
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((tools '(typescript-language-server eslint oxlint))
             (path (eglot-typescript-preset--rass-preset-path tools nil)))
        (should path)
        (let* ((output (shell-command-to-string
                        (format "python3 %s %s"
                                (shell-quote-argument my-test-rass-template-unit)
                                (shell-quote-argument path))))
               (result (json-parse-string output :object-type 'alist)))
          (let-alist result
            (should (equal .initOptions :null))
            (should (not (equal .eslintLogic :false)))
            (should (= (length .servers) 3))))))))

(ert-deftest ts-preset--template-unit-astro-eslint-oxlint ()
  "Validate template with astro-ls + eslint + oxlint."
  (skip-unless (executable-find "python3"))
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((eglot-typescript-preset-tsdk "/fake/lib")
             (tools '(astro-ls eslint oxlint))
             (path (eglot-typescript-preset--rass-preset-path tools nil)))
        (should path)
        (let* ((output (shell-command-to-string
                        (format "python3 %s %s"
                                (shell-quote-argument my-test-rass-template-unit)
                                (shell-quote-argument path))))
               (result (json-parse-string output :object-type 'alist)))
          (let-alist result
            (should (not (equal .initOptions :null)))
            (should (not (equal .eslintLogic :false)))
            (should (= (length .servers) 3))))))))


;;; --- Server contact tests ---

(ert-deftest ts-preset--server-contact-typescript ()
  "Server contact returns typescript-language-server command."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((contact (eglot-typescript-preset--server-contact nil)))
        (should (listp contact))
        (should (string-match-p "typescript-language-server"
                                (car contact)))
        (should (equal (cadr contact) "--stdio"))))))

(ert-deftest ts-preset--server-contact-rass ()
  "Server contact returns rass command with preset path."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-lsp-server 'rass))
        (let ((contact (eglot-typescript-preset--server-contact nil)))
          (should (listp contact))
          (should (string-match-p "rass" (car contact)))
          (should (string-match-p "\\.py\\'" (cadr contact))))))))

(ert-deftest ts-preset--server-contact-rass-command ()
  "Server contact uses rass-command verbatim when set."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-lsp-server 'rass)
            (eglot-typescript-preset-rass-command ["rass" "tslint"]))
        (let ((contact (eglot-typescript-preset--server-contact nil)))
          (should (equal contact '("rass" "tslint"))))))))

(ert-deftest ts-preset--server-contact-deno ()
  "Server contact returns deno lsp command with init options."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-lsp-server 'deno))
        (let ((contact (eglot-typescript-preset--server-contact nil)))
          (should (listp contact))
          (should (string-match-p "deno" (car contact)))
          (should (equal (cadr contact) "lsp"))
          (should (member :initializationOptions contact)))))))


;;; --- Astro server contact tests ---

(ert-deftest ts-preset--astro-server-contact-basic ()
  "Astro server contact returns astro-ls with init options."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-tsdk "/fake/tsdk"))
        (let ((contact (eglot-typescript-preset--astro-server-contact nil)))
          (should (listp contact))
          (should (string-match-p "astro-ls" (car contact)))
          (should (member :initializationOptions contact)))))))

(ert-deftest ts-preset--astro-server-contact-rass ()
  "Astro server contact returns rass command when configured."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-astro-lsp-server 'rass)
            (eglot-typescript-preset-tsdk "/fake/tsdk"))
        (let ((contact (eglot-typescript-preset--astro-server-contact nil)))
          (should (listp contact))
          (should (string-match-p "rass" (car contact))))))))

(ert-deftest ts-preset--astro-server-contact-rass-command ()
  "Astro server contact uses rass-command verbatim."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-astro-lsp-server 'rass)
            (eglot-typescript-preset-astro-rass-command
             ["rass" "/custom/preset.py"]))
        (let ((contact (eglot-typescript-preset--astro-server-contact nil)))
          (should (equal contact '("rass" "/custom/preset.py"))))))))


;;; --- CSS server contact tests ---

(ert-deftest ts-preset--css-server-contact-rass ()
  "CSS server contact returns rass command."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((contact (eglot-typescript-preset--css-server-contact nil)))
        (should (listp contact))
        (should (string-match-p "rass" (car contact)))))))

(ert-deftest ts-preset--css-server-contact-standalone ()
  "CSS server contact returns vscode-css-language-server when configured."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-css-lsp-server
             'vscode-css-language-server))
        (let ((contact (eglot-typescript-preset--css-server-contact nil)))
          (should (listp contact))
          (should (string-match-p "vscode-css-language-server"
                                  (car contact)))
          (should (equal (cadr contact) "--stdio")))))))

(ert-deftest ts-preset--css-server-contact-rass-command ()
  "CSS server contact uses rass-command verbatim."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-css-rass-command
             ["rass" "csstail"]))
        (let ((contact (eglot-typescript-preset--css-server-contact nil)))
          (should (equal contact '("rass" "csstail"))))))))


;;; --- Vue server contact tests ---

(ert-deftest ts-preset--vue-server-contact-basic ()
  "Vue server contact returns vue-language-server with init options."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-tsdk "/fake/tsdk"))
        (let ((contact (eglot-typescript-preset--vue-server-contact nil)))
          (should (listp contact))
          (should (string-match-p "vue-language-server" (car contact)))
          (should (member :initializationOptions contact)))))))

(ert-deftest ts-preset--vue-server-contact-rass ()
  "Vue server contact returns rass command when configured."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-vue-lsp-server 'rass)
            (eglot-typescript-preset-tsdk "/fake/tsdk"))
        (let ((contact (eglot-typescript-preset--vue-server-contact nil)))
          (should (listp contact))
          (should (string-match-p "rass" (car contact))))))))

(ert-deftest ts-preset--vue-server-contact-rass-command ()
  "Vue server contact uses rass-command verbatim."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-vue-lsp-server 'rass)
            (eglot-typescript-preset-vue-rass-command
             ["rass" "vuetail"]))
        (let ((contact (eglot-typescript-preset--vue-server-contact nil)))
          (should (equal contact '("rass" "vuetail"))))))))

(ert-deftest ts-preset--vue-init-options-with-tsdk ()
  "Vue init options include tsdk and hybridMode."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-tsdk "/my/typescript/lib"))
        (let ((opts (eglot-typescript-preset--vue-init-options)))
          (should (equal (plist-get (plist-get opts :typescript) :tsdk)
                         "/my/typescript/lib"))
          (should (eq (plist-get (plist-get opts :vue) :hybridMode)
                      :json-false)))))))

(ert-deftest ts-preset--vue-init-options-without-tsdk ()
  "Vue init options omit tsdk when not available."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-tsdk nil))
        (cl-letf (((symbol-function 'executable-find)
                   (lambda (_name) nil)))
          (let ((opts (eglot-typescript-preset--vue-init-options)))
            (should-not (plist-get opts :typescript))
            (should (eq (plist-get (plist-get opts :vue) :hybridMode)
                        :json-false))))))))


;;; --- Setup tests ---

(ert-deftest ts-preset--setup-adds-server-programs ()
  "Setup adds to eglot-server-programs."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-server-programs nil)
            (project-find-functions nil))
        (eglot-typescript-preset-setup)
        (should (>= (length eglot-server-programs) 4))
        (should (member #'eglot-typescript-preset--project-find
                        project-find-functions))))))

(ert-deftest ts-preset--setup-skips-astro-when-disabled ()
  "Setup skips Astro when astro-lsp-server is nil."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-server-programs nil)
            (project-find-functions nil)
            (eglot-typescript-preset-astro-lsp-server nil))
        (eglot-typescript-preset-setup)
        (should (= (length eglot-server-programs) 3))))))

(ert-deftest ts-preset--setup-skips-css-when-disabled ()
  "Setup skips CSS when css-lsp-server is nil."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-server-programs nil)
            (project-find-functions nil)
            (eglot-typescript-preset-css-lsp-server nil))
        (eglot-typescript-preset-setup)
        (should (= (length eglot-server-programs) 3))))))

(ert-deftest ts-preset--setup-skips-vue-when-disabled ()
  "Setup skips Vue when vue-lsp-server is nil."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-server-programs nil)
            (project-find-functions nil)
            (eglot-typescript-preset-vue-lsp-server nil))
        (eglot-typescript-preset-setup)
        (should (= (length eglot-server-programs) 3))))))


;;; --- Widget type validation ---

(ert-deftest ts-preset--rass-command-vector-p ()
  "Validate rass command vector type."
  (should (eglot-typescript-preset--rass-command-vector-p ["rass" "tslint"]))
  (should (eglot-typescript-preset--rass-command-vector-p ["rass"]))
  (should-not (eglot-typescript-preset--rass-command-vector-p []))
  (should-not (eglot-typescript-preset--rass-command-vector-p '("rass")))
  (should-not (eglot-typescript-preset--rass-command-vector-p "rass")))


;;; --- Astro init options tests ---

(ert-deftest ts-preset--astro-init-options-with-tsdk ()
  "Astro init options include tsdk when set."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-tsdk "/my/typescript/lib"))
        (let ((opts (eglot-typescript-preset--astro-init-options)))
          (should (plist-get opts :contentIntellisense))
          (should (equal (plist-get (plist-get opts :typescript) :tsdk)
                         "/my/typescript/lib")))))))

(ert-deftest ts-preset--astro-init-options-without-tsdk ()
  "Astro init options omit tsdk when not available."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-tsdk nil))
        (cl-letf (((symbol-function 'executable-find)
                   (lambda (_name) nil)))
          (let ((opts (eglot-typescript-preset--astro-init-options)))
            (should (plist-get opts :contentIntellisense))
            (should-not (plist-get opts :typescript))))))))


;;; --- Path helper tests ---

(ert-deftest ts-preset--path-in-directory-p ()
  "Check if path is inside directory."
  (should (eglot-typescript-preset--path-in-directory-p "/a/b/c" "/a/b"))
  (should (eglot-typescript-preset--path-in-directory-p "/a/b/c" "/a/b/"))
  (should-not (eglot-typescript-preset--path-in-directory-p "/a/b" "/a/b/c"))
  (should-not (eglot-typescript-preset--path-in-directory-p nil "/a"))
  (should-not (eglot-typescript-preset--path-in-directory-p "/a" nil)))


;;; --- Safe local variable tests ---

(ert-deftest ts-preset--lsp-server-safe-local-variable ()
  (should (eglot-typescript-preset--lsp-server-safe-p
           'typescript-language-server))
  (should (eglot-typescript-preset--lsp-server-safe-p 'deno))
  (should (eglot-typescript-preset--lsp-server-safe-p 'rass))
  (should-not (eglot-typescript-preset--lsp-server-safe-p 'unknown))
  (should-not (eglot-typescript-preset--lsp-server-safe-p "rass"))
  (should-not (eglot-typescript-preset--lsp-server-safe-p nil)))

(ert-deftest ts-preset--astro-lsp-server-safe-local-variable ()
  (should (eglot-typescript-preset--astro-lsp-server-safe-p 'astro-ls))
  (should (eglot-typescript-preset--astro-lsp-server-safe-p 'rass))
  (should (eglot-typescript-preset--astro-lsp-server-safe-p nil))
  (should-not (eglot-typescript-preset--astro-lsp-server-safe-p 'unknown))
  (should-not (eglot-typescript-preset--astro-lsp-server-safe-p "astro-ls")))

(ert-deftest ts-preset--css-lsp-server-safe-local-variable ()
  (should (eglot-typescript-preset--css-lsp-server-safe-p
           'vscode-css-language-server))
  (should (eglot-typescript-preset--css-lsp-server-safe-p 'rass))
  (should (eglot-typescript-preset--css-lsp-server-safe-p nil))
  (should-not (eglot-typescript-preset--css-lsp-server-safe-p 'unknown))
  (should-not (eglot-typescript-preset--css-lsp-server-safe-p
               "vscode-css-language-server")))

(ert-deftest ts-preset--vue-lsp-server-safe-local-variable ()
  (should (eglot-typescript-preset--vue-lsp-server-safe-p 'vue-language-server))
  (should (eglot-typescript-preset--vue-lsp-server-safe-p 'rass))
  (should (eglot-typescript-preset--vue-lsp-server-safe-p nil))
  (should-not (eglot-typescript-preset--vue-lsp-server-safe-p 'unknown))
  (should-not (eglot-typescript-preset--vue-lsp-server-safe-p
               "vue-language-server")))

(ert-deftest ts-preset--rass-tools-safe-local-variable ()
  (should (eglot-typescript-preset--rass-tools-safe-p
           '(typescript-language-server eslint)))
  (should (eglot-typescript-preset--rass-tools-safe-p
           '(typescript-language-server biome oxlint oxfmt)))
  (should (eglot-typescript-preset--rass-tools-safe-p
           '(astro-ls eslint)))
  (should (eglot-typescript-preset--rass-tools-safe-p
           '(vscode-css-language-server tailwindcss-language-server)))
  (should (eglot-typescript-preset--rass-tools-safe-p
           '(vue-language-server tailwindcss-language-server)))
  (should (eglot-typescript-preset--rass-tools-safe-p '()))
  (should-not (eglot-typescript-preset--rass-tools-safe-p
               '(typescript-language-server ["biome" "lsp-proxy"])))
  (should-not (eglot-typescript-preset--rass-tools-safe-p '(unknown)))
  (should-not (eglot-typescript-preset--rass-tools-safe-p "eslint")))

(ert-deftest ts-preset--project-markers-safe-local-variable ()
  (should (eglot-typescript-preset--project-markers-safe-p
           '("package.json" "tsconfig.json")))
  (should (eglot-typescript-preset--project-markers-safe-p '()))
  (should-not (eglot-typescript-preset--project-markers-safe-p
               '(package.json)))
  (should-not (eglot-typescript-preset--project-markers-safe-p
               "package.json")))


;;; --- Live tests (opt-in) ---

(when (or my-test-run-live-tests
          (getenv "MY_TEST_RUN_LIVE_TESTS"))

  (defun my-test--live-local-bins-available-p ()
    "Return non-nil if local node_modules/.bin exists."
    (file-directory-p my-test-local-bin-dir))

  (defun my-test--run-rass-with-diagnostics
      (preset-path test-file language-id root-dir &optional timeout)
    "Run rass-live-client and return parsed result as alist.
PRESET-PATH is the rass preset.  TEST-FILE is the file to open.
LANGUAGE-ID is the LSP language identifier.  ROOT-DIR is the
workspace root.  TIMEOUT defaults to 20 seconds."
    (let* ((timeout (or timeout 20))
           (output (shell-command-to-string
                    (format "python3 %s %s %s --language-id %s --root %s --timeout %s"
                            (shell-quote-argument my-test-live-rass-client)
                            (shell-quote-argument preset-path)
                            (shell-quote-argument test-file)
                            (shell-quote-argument language-id)
                            (shell-quote-argument root-dir)
                            timeout))))
      (json-parse-string output :object-type 'alist)))

  (ert-deftest ts-preset--live-rass-tslint ()
    "Live: rass with tslint preset."
    (skip-unless (my-test--live-local-bins-available-p))
    (let ((exec-path (cons my-test-local-bin-dir exec-path)))
      (skip-unless (executable-find "rass"))
      (skip-unless (executable-find "typescript-language-server"))
      (skip-unless (executable-find "vscode-eslint-language-server"))
      (my-test-with-tmp-dir tmp-dir
        (my-test-with-project-env tmp-dir
          (let* ((eglot-typescript-preset-rass-tools
                  '(typescript-language-server eslint))
                 (path (eglot-typescript-preset--rass-preset-path
                        eglot-typescript-preset-rass-tools nil))
                 (test-file (my-test-copy-fixture "valid.ts" tmp-dir)))
            (my-test-copy-fixture "package.json" tmp-dir)
            (let* ((output (shell-command-to-string
                            (format "python3 %s %s %s --language-id typescript"
                                    (shell-quote-argument
                                     my-test-live-rass-client)
                                    (shell-quote-argument path)
                                    (shell-quote-argument test-file))))
                   (result (json-parse-string output :object-type 'alist)))
              (let-alist result
                (should .initialized))))))))

  (ert-deftest ts-preset--live-rass-tsbiome ()
    "Live: rass with typescript + biome."
    (skip-unless (my-test--live-local-bins-available-p))
    (let ((exec-path (cons my-test-local-bin-dir exec-path)))
      (skip-unless (executable-find "rass"))
      (skip-unless (executable-find "typescript-language-server"))
      (skip-unless (executable-find "biome"))
      (my-test-with-tmp-dir tmp-dir
        (my-test-with-project-env tmp-dir
          (let* ((eglot-typescript-preset-rass-tools
                  '(typescript-language-server biome))
                 (path (eglot-typescript-preset--rass-preset-path
                        eglot-typescript-preset-rass-tools nil))
                 (test-file (my-test-copy-fixture "valid.ts" tmp-dir)))
            (let* ((output (shell-command-to-string
                            (format "python3 %s %s %s --language-id typescript"
                                    (shell-quote-argument
                                     my-test-live-rass-client)
                                    (shell-quote-argument path)
                                    (shell-quote-argument test-file))))
                   (result (json-parse-string output :object-type 'alist)))
              (let-alist result
                (should .initialized))))))))

  (ert-deftest ts-preset--live-diag-ts-biome-debugger ()
    "Live diagnostic: biome flags debugger statement in TS file."
    (skip-unless (my-test--live-local-bins-available-p))
    (let ((exec-path (cons my-test-local-bin-dir exec-path)))
      (skip-unless (executable-find "rass"))
      (skip-unless (executable-find "typescript-language-server"))
      (skip-unless (executable-find "biome"))
      (my-test-with-tmp-dir tmp-dir
        (my-test-with-project-env tmp-dir
          (let* ((eglot-typescript-preset-rass-tools
                  '(typescript-language-server biome))
                 (path (eglot-typescript-preset--rass-preset-path
                        eglot-typescript-preset-rass-tools nil))
                 (test-file (my-test-copy-fixture
                             "debugger.ts" tmp-dir)))
            (my-test-copy-fixture "package.json" tmp-dir)
            (let-alist (my-test--run-rass-with-diagnostics
                        path test-file "typescript" tmp-dir)
              (should .initialized)
              (should (cl-some (lambda (src)
                                 (string-match-p "Biome\\|biome" src))
                               (append .diagnosticSources nil)))
              (should (cl-some (lambda (code)
                                 (string-match-p "noDebugger" code))
                               (append .diagnosticCodes nil)))))))))

  (ert-deftest ts-preset--live-rass-ts-eslint-oxlint ()
    "Live: rass with typescript-language-server + eslint + oxlint."
    (skip-unless (my-test--live-local-bins-available-p))
    (let ((exec-path (cons my-test-local-bin-dir exec-path)))
      (skip-unless (executable-find "rass"))
      (skip-unless (executable-find "typescript-language-server"))
      (skip-unless (executable-find "vscode-eslint-language-server"))
      (skip-unless (executable-find "oxlint"))
      (my-test-with-tmp-dir tmp-dir
        (my-test-with-project-env tmp-dir
          (let* ((eglot-typescript-preset-rass-tools
                  '(typescript-language-server eslint oxlint))
                 (path (eglot-typescript-preset--rass-preset-path
                        eglot-typescript-preset-rass-tools nil))
                 (test-file (my-test-copy-fixture "valid.ts" tmp-dir)))
            (my-test-copy-fixture "package.json" tmp-dir)
            (let* ((output (shell-command-to-string
                            (format "python3 %s %s %s --language-id typescript"
                                    (shell-quote-argument
                                     my-test-live-rass-client)
                                    (shell-quote-argument path)
                                    (shell-quote-argument test-file))))
                   (result (json-parse-string output :object-type 'alist)))
              (let-alist result
                (should .initialized))))))))

  (ert-deftest ts-preset--live-rass-astro-eslint-oxlint ()
    "Live: rass with astro-ls + eslint + oxlint."
    (skip-unless (my-test--live-local-bins-available-p))
    (let ((exec-path (cons my-test-local-bin-dir exec-path)))
      (skip-unless (executable-find "rass"))
      (skip-unless (executable-find "astro-ls"))
      (skip-unless (executable-find "vscode-eslint-language-server"))
      (skip-unless (executable-find "oxlint"))
      (my-test-with-tmp-dir tmp-dir
        (my-test-with-project-env tmp-dir
          (let* ((eglot-typescript-preset-tsdk my-test-local-tsdk)
                 (tools '(astro-ls eslint oxlint))
                 (path (eglot-typescript-preset--rass-preset-path tools nil))
                 (test-file (my-test-copy-fixture "valid.astro" tmp-dir)))
            (my-test-copy-fixture "package.json" tmp-dir)
            (let* ((output (shell-command-to-string
                            (format "python3 %s %s %s --language-id astro"
                                    (shell-quote-argument
                                     my-test-live-rass-client)
                                    (shell-quote-argument path)
                                    (shell-quote-argument test-file))))
                   (result (json-parse-string output :object-type 'alist)))
              (let-alist result
                (should .initialized))))))))

  ;; --- Diagnostic verification tests ---

  (ert-deftest ts-preset--live-diag-ts-oxlint-debugger ()
    "Live diagnostic: oxlint flags debugger statement in TS file."
    (skip-unless (my-test--live-local-bins-available-p))
    (let ((exec-path (cons my-test-local-bin-dir exec-path)))
      (skip-unless (executable-find "rass"))
      (skip-unless (executable-find "typescript-language-server"))
      (skip-unless (executable-find "oxlint"))
      (my-test-with-tmp-dir tmp-dir
        (my-test-with-project-env tmp-dir
          (let* ((eglot-typescript-preset-rass-tools
                  '(typescript-language-server oxlint))
                 (path (eglot-typescript-preset--rass-preset-path
                        eglot-typescript-preset-rass-tools nil))
                 (test-file (my-test-copy-fixture
                             "debugger.ts" tmp-dir)))
            (my-test-copy-fixture "package.json" tmp-dir)
            (let-alist (my-test--run-rass-with-diagnostics
                        path test-file "typescript" tmp-dir)
              (should .initialized)
              (should (member "oxc" (append .diagnosticSources nil)))
              (should (cl-some (lambda (code)
                                 (string-match-p "no-debugger" code))
                               (append .diagnosticCodes nil)))))))))

  (ert-deftest ts-preset--live-diag-ts-type-error ()
    "Live diagnostic: typescript-language-server flags type mismatch."
    (skip-unless (my-test--live-local-bins-available-p))
    (let ((exec-path (cons my-test-local-bin-dir exec-path)))
      (skip-unless (executable-find "rass"))
      (skip-unless (executable-find "typescript-language-server"))
      (skip-unless (executable-find "oxlint"))
      (my-test-with-tmp-dir tmp-dir
        (my-test-with-project-env tmp-dir
          (let* ((eglot-typescript-preset-rass-tools
                  '(typescript-language-server oxlint))
                 (path (eglot-typescript-preset--rass-preset-path
                        eglot-typescript-preset-rass-tools nil))
                 (test-file (my-test-copy-fixture
                             "type-error.ts" tmp-dir)))
            (my-test-copy-fixture "package.json" tmp-dir)
            (let-alist (my-test--run-rass-with-diagnostics
                        path test-file "typescript" tmp-dir)
              (should .initialized)
              (should (member "typescript" (append .diagnosticSources nil)))
              (should (member "2322"
                              (append .diagnosticCodes nil)))))))))

  (ert-deftest ts-preset--live-diag-astro-oxlint-debugger ()
    "Live diagnostic: oxlint flags debugger in Astro frontmatter."
    (skip-unless (my-test--live-local-bins-available-p))
    (let ((exec-path (cons my-test-local-bin-dir exec-path)))
      (skip-unless (executable-find "rass"))
      (skip-unless (executable-find "astro-ls"))
      (skip-unless (executable-find "oxlint"))
      (my-test-with-tmp-dir tmp-dir
        (my-test-with-project-env tmp-dir
          (let* ((eglot-typescript-preset-tsdk my-test-local-tsdk)
                 (tools '(astro-ls oxlint))
                 (path (eglot-typescript-preset--rass-preset-path tools nil))
                 (test-file (my-test-copy-fixture
                             "debugger.astro" tmp-dir)))
            (my-test-copy-fixture "package.json" tmp-dir)
            (let-alist (my-test--run-rass-with-diagnostics
                        path test-file "astro" tmp-dir 30)
              (should .initialized)
              (should (member "oxc" (append .diagnosticSources nil)))
              (should (cl-some (lambda (code)
                                 (string-match-p "no-debugger" code))
                               (append .diagnosticCodes nil)))))))))

  (ert-deftest ts-preset--live-diag-astro-type-error ()
    "Live diagnostic: astro-ls flags type mismatch in frontmatter."
    (skip-unless (my-test--live-local-bins-available-p))
    (let ((exec-path (cons my-test-local-bin-dir exec-path)))
      (skip-unless (executable-find "rass"))
      (skip-unless (executable-find "astro-ls"))
      (skip-unless (executable-find "oxlint"))
      (skip-unless (executable-find "vscode-eslint-language-server"))
      (my-test-with-tmp-dir tmp-dir
        (my-test-with-project-env tmp-dir
          (let* ((eglot-typescript-preset-tsdk my-test-local-tsdk)
                 (tools '(astro-ls eslint oxlint))
                 (path (eglot-typescript-preset--rass-preset-path tools nil))
                 (test-file (my-test-copy-fixture
                             "type-error.astro" tmp-dir)))
            (my-test-copy-fixture "package.json" tmp-dir)
            (let-alist (my-test--run-rass-with-diagnostics
                        path test-file "astro" tmp-dir 30)
              (should .initialized)
              (should (member "ts" (append .diagnosticSources nil)))
              (should (member "2322"
                              (append .diagnosticCodes nil)))))))))

  (ert-deftest ts-preset--live-diag-tw-invalid-directive ()
    "Live diagnostic: tailwindcss-language-server flags invalid directive."
    (skip-unless (my-test--live-local-bins-available-p))
    (let ((exec-path (cons my-test-local-bin-dir exec-path)))
      (skip-unless (executable-find "rass"))
      (skip-unless (executable-find "tailwindcss-language-server"))
      (my-test-with-tmp-dir tmp-dir
        (my-test-with-project-env tmp-dir
          (let* ((eglot-typescript-preset-rass-tools
                  '(tailwindcss-language-server))
                 (path (eglot-typescript-preset--rass-preset-path
                        eglot-typescript-preset-rass-tools nil))
                 (test-file (my-test-copy-fixture
                             "tw-invalid-directive.css" tmp-dir)))
            (my-test-copy-fixture "package.json" tmp-dir)
            (let-alist (my-test--run-rass-with-diagnostics
                        path test-file "css" tmp-dir)
              (should .initialized)
              (should (cl-some (lambda (src)
                                 (string-match-p "tailwindcss" src))
                               (append .diagnosticSources nil)))
              (should (member "invalidTailwindDirective"
                              (append .diagnosticCodes nil)))))))))

  (ert-deftest ts-preset--live-diag-tw-ts-combo ()
    "Live diagnostic: typescript + tailwindcss-language-server together."
    (skip-unless (my-test--live-local-bins-available-p))
    (let ((exec-path (cons my-test-local-bin-dir exec-path)))
      (skip-unless (executable-find "rass"))
      (skip-unless (executable-find "typescript-language-server"))
      (skip-unless (executable-find "tailwindcss-language-server"))
      (my-test-with-tmp-dir tmp-dir
        (my-test-with-project-env tmp-dir
          (let* ((eglot-typescript-preset-rass-tools
                  '(typescript-language-server tailwindcss-language-server))
                 (path (eglot-typescript-preset--rass-preset-path
                        eglot-typescript-preset-rass-tools nil))
                 (test-file (my-test-copy-fixture
                             "tw-invalid-directive.css" tmp-dir)))
            (my-test-copy-fixture "package.json" tmp-dir)
            (let-alist (my-test--run-rass-with-diagnostics
                        path test-file "css" tmp-dir)
              (should .initialized)
              (should (cl-some (lambda (src)
                                 (string-match-p "tailwindcss" src))
                               (append .diagnosticSources nil)))
              (should (member "invalidTailwindDirective"
                              (append .diagnosticCodes nil)))))))))

  (ert-deftest ts-preset--live-diag-tw-astro-css-conflict ()
    "Live diagnostic: tailwindcss flags conflicting classes in Astro file."
    (skip-unless (my-test--live-local-bins-available-p))
    (let ((exec-path (cons my-test-local-bin-dir exec-path)))
      (skip-unless (executable-find "rass"))
      (skip-unless (executable-find "tailwindcss-language-server"))
      (my-test-with-tmp-dir tmp-dir
        (my-test-with-project-env tmp-dir
          (let* ((eglot-typescript-preset-rass-tools
                  '(tailwindcss-language-server))
                 (path (eglot-typescript-preset--rass-preset-path
                        eglot-typescript-preset-rass-tools nil))
                 (tw-dir (my-test-copy-fixture-dir "tw-project" tmp-dir))
                 (test-file (expand-file-name "css-conflict.astro" tw-dir)))
            (my-test-copy-fixture "package.json" tmp-dir)
            (let-alist (my-test--run-rass-with-diagnostics
                        path test-file "astro" tw-dir)
              (should .initialized)
              (should (cl-some (lambda (src)
                                 (string-match-p "tailwindcss" src))
                               (append .diagnosticSources nil)))
              (should (member "cssConflict"
                              (append .diagnosticCodes nil)))))))))

  (ert-deftest ts-preset--live-diag-css-rass-invalid-directive ()
    "Live diagnostic: vscode-css + tailwindcss via rass flags invalid directive."
    (skip-unless (my-test--live-local-bins-available-p))
    (let ((exec-path (cons my-test-local-bin-dir exec-path)))
      (skip-unless (executable-find "rass"))
      (skip-unless (executable-find "vscode-css-language-server"))
      (skip-unless (executable-find "tailwindcss-language-server"))
      (my-test-with-tmp-dir tmp-dir
        (my-test-with-project-env tmp-dir
          (let* ((eglot-typescript-preset-css-rass-tools
                  '(vscode-css-language-server tailwindcss-language-server))
                 (path (eglot-typescript-preset--rass-preset-path
                        eglot-typescript-preset-css-rass-tools nil))
                 (test-file (my-test-copy-fixture
                             "tw-invalid-directive.css" tmp-dir)))
            (my-test-copy-fixture "package.json" tmp-dir)
            (let-alist (my-test--run-rass-with-diagnostics
                        path test-file "css" tmp-dir)
              (should .initialized)
              (should (cl-some (lambda (src)
                                 (string-match-p "tailwindcss" src))
                               (append .diagnosticSources nil)))
              (should (member "invalidTailwindDirective"
                              (append .diagnosticCodes nil)))))))))

  (ert-deftest ts-preset--live-diag-css-rass-unknown-property ()
    "Live diagnostic: vscode-css via rass flags unknown CSS property."
    (skip-unless (my-test--live-local-bins-available-p))
    (let ((exec-path (cons my-test-local-bin-dir exec-path)))
      (skip-unless (executable-find "rass"))
      (skip-unless (executable-find "vscode-css-language-server"))
      (my-test-with-tmp-dir tmp-dir
        (my-test-with-project-env tmp-dir
          (let* ((eglot-typescript-preset-css-rass-tools
                  '(vscode-css-language-server))
                 (path (eglot-typescript-preset--rass-preset-path
                        eglot-typescript-preset-css-rass-tools nil))
                 (test-file (my-test-copy-fixture
                             "css-unknown-property.css" tmp-dir)))
            (my-test-copy-fixture "package.json" tmp-dir)
            (let-alist (my-test--run-rass-with-diagnostics
                        path test-file "css" tmp-dir)
              (should .initialized)
              (should (cl-some (lambda (src)
                                 (string-match-p "css" src))
                               (append .diagnosticSources nil)))
              (should (member "unknownProperties"
                              (append .diagnosticCodes nil)))))))))

  ) ;; end of (when ... live tests)

(provide 'test)
;;; test.el ends here
