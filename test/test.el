;;; test/test.el --- ERT tests for eglot-typescript-preset -*- lexical-binding: t; -*-

(add-to-list 'load-path (file-name-directory load-file-name))
(add-to-list 'load-path (expand-file-name ".." (file-name-directory load-file-name)))

(require 'cl-lib)
(require 'ert)
(require 'json)
(require 'project)
(require 'wid-edit)
(require 'eglot-typescript-preset)

(defvar eglot-lsp-context nil)
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

(defun my-test-link-node-modules (target-dir)
  "Symlink project `node_modules' into TARGET-DIR for ESLint resolution."
  (let ((src (expand-file-name "node_modules" my-test-project-dir))
        (dst (expand-file-name "node_modules" target-dir)))
    (make-symbolic-link src dst t)))

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
        (eglot-typescript-preset-astro-lsp-server 'rass)
        (eglot-typescript-preset-rass-program "rass")
        (eglot-typescript-preset-rass-command nil)
        (eglot-typescript-preset-astro-rass-command nil)
        (eglot-typescript-preset-rass-tools
         '( typescript-language-server eslint))
        (eglot-typescript-preset-astro-rass-tools
         '( astro-ls eslint tailwindcss-language-server))
        (eglot-typescript-preset-css-lsp-server 'rass)
        (eglot-typescript-preset-css-rass-command nil)
        (eglot-typescript-preset-css-rass-tools
         '( vscode-css-language-server tailwindcss-language-server))
        (eglot-typescript-preset-vue-lsp-server 'rass)
        (eglot-typescript-preset-vue-rass-command nil)
        (eglot-typescript-preset-vue-rass-tools
         '( vue-language-server typescript-language-server
            tailwindcss-language-server))
        (eglot-typescript-preset-svelte-lsp-server 'rass)
        (eglot-typescript-preset-svelte-rass-command nil)
        (eglot-typescript-preset-svelte-rass-tools
         '( svelte-language-server typescript-language-server
            tailwindcss-language-server))
        (eglot-typescript-preset-rass-generated-directory
         (expand-file-name "eglot-typescript-preset/" tmp-dir))
        (eglot-typescript-preset-rass-max-contextual-presets 50)
        (eglot-typescript-preset-tsdk nil)
        (eglot-typescript-preset-js-project-markers
         '("package.json" "tsconfig.json" "jsconfig.json"))
        (eglot-typescript-preset-js-modes
         '( jtsx-jsx-mode jtsx-tsx-mode jtsx-typescript-mode
            js-mode js-ts-mode typescript-ts-mode tsx-ts-mode))
        (eglot-typescript-preset-astro-modes '(astro-ts-mode))
        (eglot-typescript-preset-css-modes '(css-mode css-ts-mode))
        (eglot-typescript-preset-vue-modes '(vue-mode vue-ts-mode))
        (eglot-typescript-preset-svelte-modes '(svelte-mode svelte-ts-mode))
        (eglot-typescript-preset--setup-done nil)
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
             (major-mode 'jtsx-typescript-mode)
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
             (major-mode 'jtsx-typescript-mode)
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
             (major-mode 'jtsx-typescript-mode)
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
             (major-mode 'jtsx-typescript-mode)
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

(ert-deftest ts-preset--project-find-ignores-non-js-modes ()
  "Return nil for non-JS major modes even when JS markers exist."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((project-dir (expand-file-name "myproject/" tmp-dir))
             (src-dir (expand-file-name "src/" project-dir))
             (eglot-lsp-context t))
        (make-directory src-dir t)
        (with-temp-file (expand-file-name "package.json" project-dir)
          (insert "{}"))
        (with-temp-file (expand-file-name "pyproject.toml" project-dir)
          (insert "[project]\nname = \"test\"\n"))
        (let ((major-mode 'jtsx-typescript-mode))
          (should (eglot-typescript-preset--project-find src-dir)))
        (let ((major-mode 'python-mode))
          (should-not (eglot-typescript-preset--project-find src-dir)))))))

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
        (let ((eglot-lsp-context t)
              (major-mode 'jtsx-typescript-mode))
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

(ert-deftest ts-preset--find-tsdk-project-local ()
  "Return project-local tsdk from node_modules."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((project-dir (expand-file-name "myproject/" tmp-dir))
             (tsdk-dir (expand-file-name
                        "node_modules/typescript/lib" project-dir))
             (src-file (expand-file-name "index.ts" project-dir)))
        (make-directory tsdk-dir t)
        (with-temp-file (expand-file-name "package.json" project-dir)
          (insert "{}"))
        (with-temp-buffer
          (setq buffer-file-name src-file)
          (should (string= (eglot-typescript-preset--find-tsdk)
                           tsdk-dir)))))))

(ert-deftest ts-preset--find-tsdk-project-local-over-explicit ()
  "Project-local tsdk takes precedence over explicit."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((project-dir (expand-file-name "myproject/" tmp-dir))
             (tsdk-dir (expand-file-name
                        "node_modules/typescript/lib" project-dir))
             (src-file (expand-file-name "index.ts" project-dir))
             (eglot-typescript-preset-tsdk "/explicit/typescript/lib"))
        (make-directory tsdk-dir t)
        (with-temp-file (expand-file-name "package.json" project-dir)
          (insert "{}"))
        (with-temp-buffer
          (setq buffer-file-name src-file)
          (should (string= (eglot-typescript-preset--find-tsdk)
                           tsdk-dir)))))))

(ert-deftest ts-preset--find-tsdk-explicit-fallback ()
  "Explicit tsdk used when no project-local typescript."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((project-dir (expand-file-name "myproject/" tmp-dir))
             (src-file (expand-file-name "index.ts" project-dir))
             (eglot-typescript-preset-tsdk "/explicit/typescript/lib"))
        (make-directory project-dir t)
        (with-temp-file (expand-file-name "package.json" project-dir)
          (insert "{}"))
        (with-temp-buffer
          (setq buffer-file-name src-file)
          (should (string= (eglot-typescript-preset--find-tsdk)
                           "/explicit/typescript/lib")))))))


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
  (should (eq (eglot-typescript-preset--tool-kind-from-name
               "svelteserver")
              'svelte-language-server))
  (should (eq (eglot-typescript-preset--tool-kind-from-name
               "svelte-language-server")
              'svelte-language-server))
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

(ert-deftest ts-preset--rass-tool-command-svelte ()
  "Generate svelte-language-server command."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((cmd (eglot-typescript-preset--rass-tool-command
                  'svelte-language-server)))
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
                   "vue-language-server"))
  (should (string= (eglot-typescript-preset--rass-tool-label
                    'svelte-language-server)
                   "svelte-language-server")))

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

(ert-deftest ts-preset--rass-generated-directory-controls-preset-path ()
  "Custom generated directory controls preset paths."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let* ((custom-dir (expand-file-name "custom-generated/" tmp-dir))
             (eglot-typescript-preset-rass-generated-directory custom-dir)
             (path (eglot-typescript-preset--rass-shared-preset-path
                    '(typescript-language-server eslint))))
        (should (string-prefix-p
                 (file-name-as-directory custom-dir)
                 path))))))


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
         nil
         nil)
        (should (file-exists-p path))
        (let ((content (with-temp-buffer
                         (insert-file-contents path)
                         (buffer-string))))
          (should (string-match-p "SERVERS" content))
          (should (string-match-p "INIT_OPTIONS: dict\\[str, Any\\] | None = None" content))
          (should (string-match-p "ESLINT_LOGIC: bool = False" content)))))))

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
         t
         nil)
        (let ((content (with-temp-buffer
                         (insert-file-contents path)
                         (buffer-string))))
          (should (string-match-p "ESLINT_LOGIC: bool = True" content)))))))

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
         t
         nil)
        (let ((content (with-temp-buffer
                         (insert-file-contents path)
                         (buffer-string))))
          (should (string-match-p "contentIntellisense" content))
          (should (string-match-p "ESLINT_LOGIC: bool = True" content)))))))

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
      (let ((eglot-typescript-preset-astro-lsp-server 'astro-ls)
            (eglot-typescript-preset-tsdk "/fake/tsdk"))
        (let ((contact (eglot-typescript-preset--astro-server-contact nil)))
          (should (listp contact))
          (should (string-match-p "astro-ls" (car contact)))
          (should (member :initializationOptions contact)))))))

(ert-deftest ts-preset--astro-server-contact-rass ()
  "Astro server contact returns rass command when configured."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-tsdk "/fake/tsdk"))
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
      (let ((eglot-typescript-preset-vue-lsp-server 'vue-language-server)
            (eglot-typescript-preset-tsdk "/fake/tsdk"))
        (let ((contact (eglot-typescript-preset--vue-server-contact nil)))
          (should (listp contact))
          (should (string-match-p "vue-language-server" (car contact)))
          (should (member :initializationOptions contact)))))))

(ert-deftest ts-preset--vue-server-contact-rass ()
  "Vue server contact returns rass command when configured."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-tsdk "/fake/tsdk"))
        (let ((contact (eglot-typescript-preset--vue-server-contact nil)))
          (should (listp contact))
          (should (string-match-p "rass" (car contact))))))))

(ert-deftest ts-preset--vue-server-contact-rass-command ()
  "Vue server contact uses rass-command verbatim."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-vue-rass-command
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
                      t)))))))

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
                        t))))))))


;;; --- Svelte server contact tests ---

(ert-deftest ts-preset--svelte-server-contact-basic ()
  "Svelte server contact returns svelte-language-server with init options."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-svelte-lsp-server 'svelte-language-server)
            (eglot-typescript-preset-tsdk "/fake/tsdk"))
        (let ((contact (eglot-typescript-preset--svelte-server-contact nil)))
          (should (listp contact))
          (should (string-match-p "svelteserver" (car contact)))
          (should (member :initializationOptions contact)))))))

(ert-deftest ts-preset--svelte-server-contact-rass ()
  "Svelte server contact returns rass command when configured."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-tsdk "/fake/tsdk"))
        (let ((contact (eglot-typescript-preset--svelte-server-contact nil)))
          (should (listp contact))
          (should (string-match-p "rass" (car contact))))))))

(ert-deftest ts-preset--svelte-server-contact-rass-command ()
  "Svelte server contact uses rass-command verbatim."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-svelte-rass-command
             ["rass" "sveltetail"]))
        (let ((contact (eglot-typescript-preset--svelte-server-contact nil)))
          (should (equal contact '("rass" "sveltetail"))))))))

(ert-deftest ts-preset--svelte-init-options-with-tsdk ()
  "Svelte init options include tsdk when set."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-tsdk "/my/typescript/lib"))
        (let ((opts (eglot-typescript-preset--svelte-init-options)))
          (should (equal
                   (plist-get
                    (plist-get (plist-get opts :configuration) :typescript)
                    :tsdk)
                   "/my/typescript/lib")))))))

(ert-deftest ts-preset--svelte-init-options-without-tsdk ()
  "Svelte init options return nil when tsdk not available."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-tsdk nil))
        (cl-letf (((symbol-function 'executable-find)
                   (lambda (_name) nil)))
          (should-not (eglot-typescript-preset--svelte-init-options)))))))


;;; --- Setup tests ---

(ert-deftest ts-preset--setup-adds-server-programs ()
  "Setup adds to eglot-server-programs."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-server-programs nil)
            (project-find-functions nil))
        (unwind-protect
            (progn
              (eglot-typescript-preset-setup)
              (should (>= (length eglot-server-programs) 5))
              (should (member #'eglot-typescript-preset--project-find
                              project-find-functions))
              (should (advice-member-p
                       #'eglot-typescript-preset--client-capabilities-a
                       'eglot-client-capabilities)))
          (advice-remove 'eglot-client-capabilities
                         #'eglot-typescript-preset--client-capabilities-a))))))

(ert-deftest ts-preset--setup-skips-astro-when-disabled ()
  "Setup skips Astro when astro-lsp-server is nil."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-server-programs nil)
            (project-find-functions nil)
            (eglot-typescript-preset-astro-lsp-server nil))
        (eglot-typescript-preset-setup)
        (should (= (length eglot-server-programs) 4))))))

(ert-deftest ts-preset--setup-skips-css-when-disabled ()
  "Setup skips CSS when css-lsp-server is nil."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-server-programs nil)
            (project-find-functions nil)
            (eglot-typescript-preset-css-lsp-server nil))
        (eglot-typescript-preset-setup)
        (should (= (length eglot-server-programs) 4))))))

(ert-deftest ts-preset--setup-skips-vue-when-disabled ()
  "Setup skips Vue when vue-lsp-server is nil."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-server-programs nil)
            (project-find-functions nil)
            (eglot-typescript-preset-vue-lsp-server nil))
        (eglot-typescript-preset-setup)
        (should (= (length eglot-server-programs) 4))))))

(ert-deftest ts-preset--setup-skips-svelte-when-disabled ()
  "Setup skips Svelte when svelte-lsp-server is nil."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-server-programs nil)
            (project-find-functions nil)
            (eglot-typescript-preset-svelte-lsp-server nil))
        (eglot-typescript-preset-setup)
        (should (= (length eglot-server-programs) 4))))))

(ert-deftest ts-preset--maybe-setup-runs-when-auto-setup-t ()
  "Auto-setup calls setup when `eglot-typescript-preset-auto-setup' is t."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-server-programs nil)
            (project-find-functions nil)
            (eglot-typescript-preset-auto-setup t))
        (unwind-protect
            (progn
              (eglot-typescript-preset--maybe-setup)
              (should (>= (length eglot-server-programs) 5)))
          (advice-remove 'eglot-client-capabilities
                         #'eglot-typescript-preset--client-capabilities-a)
          (advice-remove 'eglot--workspace-configuration-plist
                         #'eglot-typescript-preset--workspace-configuration-plist-a))))))

(ert-deftest ts-preset--maybe-setup-skips-when-auto-setup-nil ()
  "Auto-setup skips setup when `eglot-typescript-preset-auto-setup' is nil."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-server-programs nil)
            (project-find-functions nil)
            (eglot-typescript-preset-auto-setup nil))
        (eglot-typescript-preset--maybe-setup)
        (should (null eglot-server-programs))
        (should (null project-find-functions))))))


;;; --- Workspace configuration advice ---

(ert-deftest ts-preset--workspace-config-astro-appends-typescript ()
  "Workspace config advice appends TypeScript validation for Astro buffers."
  (with-temp-buffer
    (setq major-mode 'astro-ts-mode)
    (let ((buf (current-buffer))
          (server 'mock-server))
      (cl-letf (((symbol-function 'eglot--managed-buffers)
                 (lambda (_s) (list buf))))
        (let ((result (eglot-typescript-preset--workspace-configuration-plist-a
                       (lambda (_s &optional _p) nil)
                       server)))
          (should (plist-get result :typescript))
          (should (eq (plist-get
                       (plist-get
                        (plist-get result :typescript) :validate)
                       :enable)
                      t)))))))

(ert-deftest ts-preset--workspace-config-vue-appends-typescript ()
  "Workspace config advice appends TypeScript validation for Vue buffers."
  (with-temp-buffer
    (setq major-mode 'vue-mode)
    (let ((buf (current-buffer))
          (server 'mock-server))
      (cl-letf (((symbol-function 'eglot--managed-buffers)
                 (lambda (_s) (list buf))))
        (let ((result (eglot-typescript-preset--workspace-configuration-plist-a
                       (lambda (_s &optional _p) nil)
                       server)))
          (should (plist-get result :typescript)))))))

(ert-deftest ts-preset--workspace-config-svelte-appends-typescript ()
  "Workspace config advice appends TypeScript validation for Svelte buffers."
  (with-temp-buffer
    (setq major-mode 'svelte-mode)
    (let ((buf (current-buffer))
          (server 'mock-server))
      (cl-letf (((symbol-function 'eglot--managed-buffers)
                 (lambda (_s) (list buf))))
        (let ((result (eglot-typescript-preset--workspace-configuration-plist-a
                       (lambda (_s &optional _p) nil)
                       server)))
          (should (plist-get result :typescript)))))))

(ert-deftest ts-preset--workspace-config-js-unchanged ()
  "Workspace config advice does not modify config for JS buffers."
  (with-temp-buffer
    (setq major-mode 'typescript-ts-mode)
    (let ((buf (current-buffer))
          (server 'mock-server))
      (cl-letf (((symbol-function 'eglot--managed-buffers)
                 (lambda (_s) (list buf))))
        (let ((result (eglot-typescript-preset--workspace-configuration-plist-a
                       (lambda (_s &optional _p) '(:foo 1))
                       server)))
          (should (eq (plist-get result :foo) 1))
          (should-not (plist-get result :typescript)))))))

(ert-deftest ts-preset--workspace-config-user-typescript-takes-precedence ()
  "User-provided :typescript config takes precedence over defaults."
  (with-temp-buffer
    (setq major-mode 'astro-ts-mode)
    (let ((buf (current-buffer))
          (server 'mock-server)
          (user-config '(:typescript (:tsdk "/custom/path"))))
      (cl-letf (((symbol-function 'eglot--managed-buffers)
                 (lambda (_s) (list buf))))
        (let ((result (eglot-typescript-preset--workspace-configuration-plist-a
                       (lambda (_s &optional _p) user-config)
                       server)))
          (should (equal (plist-get result :typescript)
                         '(:tsdk "/custom/path"))))))))


;;; --- Streaming diagnostics ---

(ert-deftest ts-preset--client-capabilities-injects-streaming ()
  "Capabilities advice injects $streamingDiagnostics for our modes."
  (let ((base-caps '(:textDocument (:publishDiagnostics (:relatedInformation t))
                     :workspace (:configuration t))))
    (cl-letf (((symbol-function 'eglot--major-modes)
               (lambda (_s) '(typescript-ts-mode))))
      (let ((result (eglot-typescript-preset--client-capabilities-a
                     (lambda (_s) base-caps)
                     'mock-server)))
        (should (eq t (plist-get (plist-get result :textDocument)
                                 :$streamingDiagnostics)))
        (should (plist-get (plist-get result :textDocument)
                           :publishDiagnostics))))))

(ert-deftest ts-preset--client-capabilities-skips-non-preset-modes ()
  "Capabilities advice does not inject $streamingDiagnostics for other modes."
  (let ((base-caps '(:textDocument (:publishDiagnostics (:relatedInformation t))
                     :workspace (:configuration t))))
    (cl-letf (((symbol-function 'eglot--major-modes)
               (lambda (_s) '(python-mode))))
      (let ((result (eglot-typescript-preset--client-capabilities-a
                     (lambda (_s) base-caps)
                     'mock-server)))
        (should-not (plist-get (plist-get result :textDocument)
                               :$streamingDiagnostics))))))

(defun my-test--streaming-merge (uri)
  "Compute merged diagnostics vector for URI from the streaming table."
  (let ((by-token (gethash uri eglot-typescript-preset--streaming-diag-table))
        (merged []))
    (when by-token
      (maphash (lambda (_tok diags) (setq merged (vconcat merged diags))) by-token))
    merged))

(ert-deftest ts-preset--streaming-diags-accumulates-across-tokens ()
  "Streaming handler merges diagnostics from different tokens."
  (clrhash eglot-typescript-preset--streaming-diag-table)
  (let ((uri "file:///test-accum.ts")
        (diag1 [:message "err1"])
        (diag2 [:message "err2"]))
    (let ((by-token (puthash uri (make-hash-table :test #'equal)
                             eglot-typescript-preset--streaming-diag-table)))
      (puthash "server-a" (vector diag1) by-token)
      (should (= 1 (length (my-test--streaming-merge uri))))
      (puthash "server-b" (vector diag2) by-token)
      (let ((merged (my-test--streaming-merge uri)))
        (should (vectorp merged))
        (should (= 2 (length merged)))))))

(ert-deftest ts-preset--streaming-diags-replaces-same-token ()
  "Same token replaces its diagnostics, not accumulates."
  (clrhash eglot-typescript-preset--streaming-diag-table)
  (let ((uri "file:///test-replace.ts")
        (diag1 [:message "err1"]))
    (let ((by-token (puthash uri (make-hash-table :test #'equal)
                             eglot-typescript-preset--streaming-diag-table)))
      (puthash "server-a" (vector diag1) by-token)
      (should (= 1 (length (my-test--streaming-merge uri))))
      (puthash "server-a" [] by-token)
      (should (= 0 (length (my-test--streaming-merge uri)))))))

(ert-deftest ts-preset--streaming-diags-cleared-on-connect ()
  "Capabilities advice clears the streaming diagnostics table."
  (clrhash eglot-typescript-preset--streaming-diag-table)
  (puthash "file:///old.ts" (make-hash-table :test #'equal)
           eglot-typescript-preset--streaming-diag-table)
  (should (= 1 (hash-table-count eglot-typescript-preset--streaming-diag-table)))
  (let ((base-caps '(:textDocument (:publishDiagnostics (:relatedInformation t)))))
    (cl-letf (((symbol-function 'eglot--major-modes)
               (lambda (_s) '(typescript-ts-mode))))
      (eglot-typescript-preset--client-capabilities-a
       (lambda (_s) base-caps) 'mock-server)))
  (should (= 0 (hash-table-count eglot-typescript-preset--streaming-diag-table))))


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

(ert-deftest ts-preset--svelte-lsp-server-safe-local-variable ()
  (should (eglot-typescript-preset--svelte-lsp-server-safe-p
           'svelte-language-server))
  (should (eglot-typescript-preset--svelte-lsp-server-safe-p 'rass))
  (should (eglot-typescript-preset--svelte-lsp-server-safe-p nil))
  (should-not (eglot-typescript-preset--svelte-lsp-server-safe-p 'unknown))
  (should-not (eglot-typescript-preset--svelte-lsp-server-safe-p
               "svelte-language-server")))

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
  (should (eglot-typescript-preset--rass-tools-safe-p
           '(svelte-language-server tailwindcss-language-server)))
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

(ert-deftest ts-preset--language-id-overrides-safe-local-variable ()
  (should (eglot-typescript-preset--language-id-overrides-safe-p
           '((js-mode . "javascript") (jtsx-tsx-mode . "typescriptreact"))))
  (should (eglot-typescript-preset--language-id-overrides-safe-p '()))
  (should-not (eglot-typescript-preset--language-id-overrides-safe-p
               '(("js-mode" . "javascript"))))
  (should-not (eglot-typescript-preset--language-id-overrides-safe-p
               '((js-mode . javascript))))
  (should-not (eglot-typescript-preset--language-id-overrides-safe-p
               "not-an-alist")))

(ert-deftest ts-preset--setup-sets-language-ids ()
  "Setup applies eglot-language-id properties from the overrides alist."
  (my-test-with-tmp-dir tmp-dir
    (my-test-with-project-env tmp-dir
      (let ((eglot-typescript-preset-language-id-overrides
             '((jtsx-typescript-mode . "typescript")
               (js-mode . "javascript"))))
        (eglot-typescript-preset-setup)
        (should (equal "typescript"
                       (get 'jtsx-typescript-mode 'eglot-language-id)))
        (should (equal "javascript"
                       (get 'js-mode 'eglot-language-id)))))))


;;; --- Live tests (opt-in) ---

(defun my-test-live-tests-enabled-p ()
  "Return non-nil when opt-in live tests should run."
  (or my-test-run-live-tests
      (getenv "MY_TEST_RUN_LIVE_TESTS")))

(defun my-test--live-local-bins-available-p ()
  "Return non-nil if local node_modules/.bin exists."
  (file-directory-p my-test-local-bin-dir))

(defun my-test--run-rass-session (preset-path file-specs root-dir
                                              &optional timeout min-events
                                              extra-args)
  "Run rass-live-client with multiple files and return parsed result.
PRESET-PATH is the rass preset.  FILE-SPECS is a list of
\(FILE-PATH . LANGUAGE-ID) cons cells.  ROOT-DIR is the workspace
root.  TIMEOUT defaults to 20 seconds.  MIN-EVENTS is the minimum
publishDiagnostics events per file before settle starts (default 1).
EXTRA-ARGS is an optional string appended to the command."
  (let* ((timeout (or timeout 20))
         (min-events (or min-events 1))
         (file-args (mapconcat
                     (lambda (spec)
                       (format "%s:%s"
                               (shell-quote-argument (car spec))
                               (shell-quote-argument (cdr spec))))
                     file-specs " "))
         (output (shell-command-to-string
                  (format
                   "python3 %s %s %s --root %s --timeout %s --min-events %s%s"
                   (shell-quote-argument my-test-live-rass-client)
                   (shell-quote-argument preset-path)
                   file-args
                   (shell-quote-argument root-dir)
                   timeout
                   min-events
                   (if extra-args (concat " " extra-args) "")))))
    (json-parse-string output :object-type 'alist)))

(defun my-test--session-file-result (session-result file-path)
  "Extract per-file diagnostics from SESSION-RESULT for FILE-PATH."
  (let* ((files (alist-get 'files session-result))
         (uri (concat "file://" (expand-file-name file-path))))
    (alist-get (intern uri) files)))

(defun my-test--assert-file-diagnostics (session-result file-path
                                                        expected-codes
                                                        &optional expected-sources)
  "Assert FILE-PATH in SESSION-RESULT has exactly EXPECTED-CODES.
SESSION-RESULT is the parsed multi-file result.  EXPECTED-CODES is
compared as sorted deduplicated sets.  EXPECTED-SOURCES, when
non-nil, lists source patterns that must each match at least one
actual source."
  (should (alist-get 'initialized session-result))
  (let* ((file-data (my-test--session-file-result session-result file-path))
         (actual-codes (sort (delete-dups
                              (append (alist-get 'diagnosticCodes file-data) nil))
                             #'string<))
         (expected (sort (copy-sequence expected-codes) #'string<)))
    (should (equal actual-codes expected))
    (dolist (src-pat expected-sources)
      (should (cl-some (lambda (s) (string-match-p src-pat s))
                       (append (alist-get 'diagnosticSources file-data) nil))))))

(defun my-test--setup-fixture-dir (fixture-subdir tmp-dir
                                                  &optional need-node-modules)
  "Copy FIXTURE-SUBDIR contents into TMP-DIR.
When NEED-NODE-MODULES is non-nil, symlink node_modules."
  (let ((src-dir (expand-file-name fixture-subdir my-test-fixtures-dir)))
    (dolist (file (directory-files src-dir nil "\\`[^.]"))
      (unless (string= file "node_modules")
        (let ((src (expand-file-name file src-dir))
              (dst (expand-file-name file tmp-dir)))
          (if (file-directory-p src)
              (copy-directory src dst nil t t)
            (copy-file src dst t))))))
  (when need-node-modules
    (my-test-link-node-modules tmp-dir)))

;; --- TypeScript + eslint ---

(ert-deftest ts-preset--live-ts-eslint ()
  "Live: typescript-language-server + eslint on valid and debugger files."
  (skip-unless (my-test-live-tests-enabled-p))
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
		      eglot-typescript-preset-rass-tools nil)))
	  (my-test--setup-fixture-dir "eslint" tmp-dir t)
	  (let* ((valid (expand-file-name "valid.ts" tmp-dir))
		 (debugger-f (expand-file-name "debugger.ts" tmp-dir))
		 (type-err (expand-file-name "type-error.ts" tmp-dir))
		 (result (my-test--run-rass-session
			  path
			  `((,valid . "typescript")
			    (,debugger-f . "typescript")
			    (,type-err . "typescript"))
			  tmp-dir)))
	    (my-test--assert-file-diagnostics result valid '())
	    (my-test--assert-file-diagnostics
	     result debugger-f '("no-debugger") '("eslint"))
	    (my-test--assert-file-diagnostics
	     result type-err
	     '("2322" "@typescript-eslint/no-unused-vars")
	     '("typescript" "eslint"))))))))

;; --- TypeScript + biome ---

(ert-deftest ts-preset--live-ts-biome ()
  "Live: typescript-language-server + biome on valid and debugger files."
  (skip-unless (my-test-live-tests-enabled-p))
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
		      eglot-typescript-preset-rass-tools nil)))
	  (my-test--setup-fixture-dir "biome" tmp-dir)
	  (let* ((valid (expand-file-name "valid.ts" tmp-dir))
		 (debugger-f (expand-file-name "debugger.ts" tmp-dir))
		 (result (my-test--run-rass-session
			  path
			  `((,valid . "typescript")
			    (,debugger-f . "typescript"))
			  tmp-dir)))
	    (my-test--assert-file-diagnostics result valid '())
	    (my-test--assert-file-diagnostics
	     result debugger-f
	     '("lint/suspicious/noDebugger") '("biome"))))))))

;; --- TypeScript + oxlint ---

(ert-deftest ts-preset--live-ts-oxlint ()
  "Live: typescript-language-server + oxlint on debugger and type-error files."
  (skip-unless (my-test-live-tests-enabled-p))
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
		      eglot-typescript-preset-rass-tools nil)))
	  (my-test--setup-fixture-dir "oxlint" tmp-dir)
	  (let* ((valid (expand-file-name "valid.ts" tmp-dir))
		 (debugger-f (expand-file-name "debugger.ts" tmp-dir))
		 (type-err (expand-file-name "type-error.ts" tmp-dir))
		 (result (my-test--run-rass-session
			  path
			  `((,valid . "typescript")
			    (,debugger-f . "typescript")
			    (,type-err . "typescript"))
			  tmp-dir 30 2 "--settle 3")))
	    (my-test--assert-file-diagnostics result valid '())
	    (my-test--assert-file-diagnostics
	     result debugger-f '("eslint(no-debugger)") '("oxc"))
	    (my-test--assert-file-diagnostics
	     result type-err
	     '("2322" "eslint(no-unused-vars)") '("oxc" "typescript"))))))))

;; --- TypeScript + eslint + oxlint ---

(ert-deftest ts-preset--live-ts-eslint-oxlint ()
  "Live: typescript-language-server + eslint + oxlint on valid and debugger."
  (skip-unless (my-test-live-tests-enabled-p))
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
		      eglot-typescript-preset-rass-tools nil)))
	  (my-test--setup-fixture-dir "eslint-oxlint" tmp-dir t)
	  (let* ((valid (expand-file-name "valid.ts" tmp-dir))
		 (debugger-f (expand-file-name "debugger.ts" tmp-dir))
		 (type-err (expand-file-name "type-error.ts" tmp-dir))
		 (result (my-test--run-rass-session
			  path
			  `((,valid . "typescript")
			    (,debugger-f . "typescript")
			    (,type-err . "typescript"))
			  tmp-dir 30 2 "--settle 3")))
	    (my-test--assert-file-diagnostics result valid '())
	    (my-test--assert-file-diagnostics
	     result debugger-f
	     '("eslint(no-debugger)") '("oxc"))
	    (my-test--assert-file-diagnostics
	     result type-err
	     '("2322" "eslint(no-unused-vars)") '("typescript" "oxc"))))))))

;; --- TypeScript + tailwindcss ---

(ert-deftest ts-preset--live-ts-tailwind ()
  "Live: typescript + tailwindcss-language-server together."
  (skip-unless (my-test-live-tests-enabled-p))
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
		      eglot-typescript-preset-rass-tools nil)))
	  (my-test--setup-fixture-dir "ts-tailwind" tmp-dir)
	  (let* ((invalid (expand-file-name
			   "tw-invalid-directive.css" tmp-dir))
		 (result (my-test--run-rass-session
			  path
			  `((,invalid . "css"))
			  tmp-dir)))
	    (my-test--assert-file-diagnostics
	     result invalid
	     '("invalidTailwindDirective") '("tailwindcss"))))))))

;; --- CSS + tailwindcss ---

(ert-deftest ts-preset--live-css-tailwind ()
  "Live: vscode-css + tailwindcss via rass flags invalid directive."
  (skip-unless (my-test-live-tests-enabled-p))
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
		      eglot-typescript-preset-css-rass-tools nil)))
	  (my-test--setup-fixture-dir "css-tailwind" tmp-dir)
	  (let* ((invalid (expand-file-name
			   "tw-invalid-directive.css" tmp-dir))
		 (result (my-test--run-rass-session
			  path
			  `((,invalid . "css"))
			  tmp-dir 30 2 "--settle 3")))
	    (my-test--assert-file-diagnostics
	     result invalid
	     '("invalidTailwindDirective") '("tailwindcss"))))))))

;; --- CSS only ---

(ert-deftest ts-preset--live-css-unknown-property ()
  "Live: vscode-css via rass flags unknown CSS property."
  (skip-unless (my-test-live-tests-enabled-p))
  (skip-unless (my-test--live-local-bins-available-p))
  (let ((exec-path (cons my-test-local-bin-dir exec-path)))
    (skip-unless (executable-find "rass"))
    (skip-unless (executable-find "vscode-css-language-server"))
    (my-test-with-tmp-dir tmp-dir
      (my-test-with-project-env tmp-dir
	(let* ((eglot-typescript-preset-css-rass-tools
		'(vscode-css-language-server))
	       (path (eglot-typescript-preset--rass-preset-path
		      eglot-typescript-preset-css-rass-tools nil)))
	  (my-test--setup-fixture-dir "css" tmp-dir)
	  (let* ((css-file (expand-file-name
			    "css-unknown-property.css" tmp-dir))
		 (result (my-test--run-rass-session
			  path
			  `((,css-file . "css"))
			  tmp-dir)))
	    (my-test--assert-file-diagnostics
	     result css-file
	     '("unknownProperties") '("css"))))))))

;; --- Vue + typescript ---

(ert-deftest ts-preset--live-vue-typescript ()
  "Live: vue-language-server + typescript-language-server on valid and type-error."
  (skip-unless (my-test-live-tests-enabled-p))
  (skip-unless (my-test--live-local-bins-available-p))
  (let ((exec-path (cons my-test-local-bin-dir exec-path)))
    (skip-unless (executable-find "rass"))
    (skip-unless (executable-find "vue-language-server"))
    (skip-unless (executable-find "typescript-language-server"))
    (my-test-with-tmp-dir tmp-dir
      (my-test-with-project-env tmp-dir
	(let* ((eglot-typescript-preset-tsdk my-test-local-tsdk)
	       (tools '(vue-language-server typescript-language-server))
	       (path (eglot-typescript-preset--rass-preset-path tools nil)))
	  (my-test--setup-fixture-dir "vue" tmp-dir)
	  (let* ((valid (expand-file-name "valid.vue" tmp-dir))
		 (type-err (expand-file-name "type-error.vue" tmp-dir))
		 (tmpl-err (expand-file-name "template-error.vue" tmp-dir))
		 (result (my-test--run-rass-session
			  path
			  `((,valid . "vue")
			    (,type-err . "vue")
			    (,tmpl-err . "vue"))
			  tmp-dir 30)))
	    (my-test--assert-file-diagnostics result valid '())
	    (my-test--assert-file-diagnostics
	     result type-err '("2322" "6133") '("typescript"))
	    (my-test--assert-file-diagnostics
	     result tmpl-err '("28") '("vue"))))))))

;; --- Vue + tailwindcss ---

(ert-deftest ts-preset--live-vue-tailwind ()
  "Live: vue-language-server + typescript + tailwindcss on Vue and CSS diagnostics."
  (skip-unless (my-test-live-tests-enabled-p))
  (skip-unless (my-test--live-local-bins-available-p))
  (let ((exec-path (cons my-test-local-bin-dir exec-path)))
    (skip-unless (executable-find "rass"))
    (skip-unless (executable-find "vue-language-server"))
    (skip-unless (executable-find "typescript-language-server"))
    (skip-unless (executable-find "tailwindcss-language-server"))
    (my-test-with-tmp-dir tmp-dir
      (my-test-with-project-env tmp-dir
	(let* ((eglot-typescript-preset-tsdk my-test-local-tsdk)
	       (tools '(vue-language-server typescript-language-server
					    tailwindcss-language-server))
	       (path (eglot-typescript-preset--rass-preset-path tools nil)))
	  (my-test--setup-fixture-dir "vue-tailwind" tmp-dir)
	  (let* ((valid (expand-file-name "valid.vue" tmp-dir))
		 (type-err (expand-file-name "type-error.vue" tmp-dir))
		 (tw-dir (expand-file-name "tw-project" tmp-dir))
		 (conflict (expand-file-name "css-conflict.vue" tw-dir))
		 (result (my-test--run-rass-session
			  path
			  `((,valid . "vue")
			    (,type-err . "vue")
			    (,conflict . "vue"))
			  tmp-dir 30 2 "--settle 3")))
	    (my-test--assert-file-diagnostics result valid '())
	    (my-test--assert-file-diagnostics
	     result type-err '("2322" "6133") '("typescript"))
	    (my-test--assert-file-diagnostics
	     result conflict
	     '("cssConflict") '("tailwindcss"))))))))

;; --- Svelte + typescript ---

(ert-deftest ts-preset--live-svelte-typescript ()
  "Live: svelteserver + typescript-language-server on valid, type-error, and a11y."
  (skip-unless (my-test-live-tests-enabled-p))
  (skip-unless (my-test--live-local-bins-available-p))
  (let ((exec-path (cons my-test-local-bin-dir exec-path)))
    (skip-unless (executable-find "rass"))
    (skip-unless (executable-find "svelteserver"))
    (skip-unless (executable-find "typescript-language-server"))
    (my-test-with-tmp-dir tmp-dir
      (my-test-with-project-env tmp-dir
	(let* ((eglot-typescript-preset-tsdk my-test-local-tsdk)
	       (tools '(svelte-language-server typescript-language-server))
	       (path (eglot-typescript-preset--rass-preset-path tools nil)))
	  (my-test--setup-fixture-dir "svelte" tmp-dir)
	  (let* ((valid (expand-file-name "valid.svelte" tmp-dir))
		 (type-err (expand-file-name "type-error.svelte" tmp-dir))
		 (a11y-err (expand-file-name "a11y-error.svelte" tmp-dir))
		 (result (my-test--run-rass-session
			  path
			  `((,valid . "svelte")
			    (,type-err . "svelte")
			    (,a11y-err . "svelte"))
			  tmp-dir 30)))
	    (my-test--assert-file-diagnostics result valid '())
	    (my-test--assert-file-diagnostics
	     result type-err '("2322") '("ts"))
	    (my-test--assert-file-diagnostics
	     result a11y-err
	     '("a11y-missing-attribute") '("svelte"))))))))

;; --- Svelte + tailwindcss ---

(ert-deftest ts-preset--live-svelte-tailwind ()
  "Live: svelteserver + tailwindcss on valid, CSS conflict, and a11y+tw conflict."
  (skip-unless (my-test-live-tests-enabled-p))
  (skip-unless (my-test--live-local-bins-available-p))
  (let ((exec-path (cons my-test-local-bin-dir exec-path)))
    (skip-unless (executable-find "rass"))
    (skip-unless (executable-find "svelteserver"))
    (skip-unless (executable-find "tailwindcss-language-server"))
    (my-test-with-tmp-dir tmp-dir
      (my-test-with-project-env tmp-dir
	(let* ((eglot-typescript-preset-tsdk my-test-local-tsdk)
	       (tools '(svelte-language-server tailwindcss-language-server))
	       (path (eglot-typescript-preset--rass-preset-path tools nil)))
	  (my-test--setup-fixture-dir "svelte-tailwind" tmp-dir)
	  (let* ((valid (expand-file-name "valid.svelte" tmp-dir))
		 (tw-dir (expand-file-name "tw-project" tmp-dir))
		 (conflict (expand-file-name "css-conflict.svelte" tw-dir))
		 (a11y-tw (expand-file-name "a11y-tw-conflict.svelte" tw-dir))
		 (result (my-test--run-rass-session
			  path
			  `((,valid . "svelte")
			    (,conflict . "svelte")
			    (,a11y-tw . "svelte"))
			  tmp-dir 30 2 "--settle 3")))
	    (my-test--assert-file-diagnostics result valid '())
	    (my-test--assert-file-diagnostics
	     result conflict
	     '("cssConflict") '("tailwindcss"))
	    (my-test--assert-file-diagnostics
	     result a11y-tw
	     '("a11y-missing-attribute" "cssConflict")
	     '("svelte" "tailwindcss"))))))))


;; --- Svelte URI normalization (+ in filename) ---

(ert-deftest ts-preset--live-svelte-uri-normalization ()
  "Live: svelteserver normalizes percent-encoded URIs for + filenames."
  (skip-unless (my-test-live-tests-enabled-p))
  (skip-unless (my-test--live-local-bins-available-p))
  (let ((exec-path (cons my-test-local-bin-dir exec-path)))
    (skip-unless (executable-find "rass"))
    (skip-unless (executable-find "svelteserver"))
    (skip-unless (executable-find "typescript-language-server"))
    (my-test-with-tmp-dir tmp-dir
      (my-test-with-project-env tmp-dir
	(let* ((eglot-typescript-preset-tsdk my-test-local-tsdk)
	       (tools '(svelte-language-server typescript-language-server))
	       (path (eglot-typescript-preset--rass-preset-path tools nil)))
	  (my-test--setup-fixture-dir "svelte" tmp-dir)
	  (let* ((plus-err (expand-file-name "+type-error.svelte" tmp-dir))
		 (result (my-test--run-rass-session
			  path
			  `((,plus-err . "svelte"))
			  tmp-dir 30 1 "--raw-uri")))
	    (my-test--assert-file-diagnostics
	     result plus-err '("2322") '("ts"))))))))

(defun my-test-run-live-tests-parallel ()
  "Run all live tests in parallel child Emacs processes, then exit.
Parallelism defaults to 6 or the LIVE_TEST_JOBS env variable."
  (let* ((max-jobs (string-to-number (or (getenv "LIVE_TEST_JOBS") "6")))
         (test-names
          (with-temp-buffer
            (insert-file-contents
             (expand-file-name "test/test.el" my-test-project-dir))
            (let (names)
              (while (re-search-forward
                      "ert-deftest \\(ts-preset--live-[^ ()]+\\)" nil t)
                (push (match-string 1) names))
              (nreverse names))))
         (total (length test-names))
         (emacs-bin (expand-file-name invocation-name invocation-directory))
         (preset-el (expand-file-name
                     "eglot-typescript-preset.el" my-test-project-dir))
         (test-el (expand-file-name "test/test.el" my-test-project-dir))
         (running '())
         (passed 0)
         (failed 0)
         (failures '()))
    (message "Running %d live tests with up to %d parallel jobs..."
             total max-jobs)
    (while (or test-names running)
      ;; Launch jobs up to max-jobs
      (while (and test-names (< (length running) max-jobs))
        (let* ((name (pop test-names))
               (buf (generate-new-buffer (concat " *live-test:" name "*")))
               (proc (start-process
                      name buf emacs-bin
                      "-Q" "--batch"
                      "-l" preset-el
                      "--eval" "(setq my-test-run-live-tests t)"
                      "-l" test-el
                      "--eval"
                      (format "(ert-run-tests-batch-and-exit \"^%s$\")" name))))
          (set-process-sentinel proc #'ignore)
          (push (list name proc buf) running)))
      ;; Poll for completion
      (sleep-for 0.1)
      (let (still-running)
        (dolist (entry running)
          (cl-destructuring-bind (name proc buf) entry
            (if (process-live-p proc)
                (push entry still-running)
              (let ((rc (process-exit-status proc))
                    (output (with-current-buffer buf (buffer-string))))
                (if (= rc 0)
                    (progn
                      (cl-incf passed)
                      (message "PASS: %s" name))
                  (cl-incf failed)
                  (push name failures)
                  (message "FAIL: %s" name)
                  (message "%s" (car (last (split-string output "\n\n")))))
                (kill-buffer buf)))))
        (setq running (nreverse still-running))))
    (message "\n%d/%d live tests passed." passed total)
    (when failures
      (message "Failures: %s" (string-join (nreverse failures) ", ")))
    (kill-emacs (if (= failed 0) 0 1))))

(provide 'test)
;;; test.el ends here
