;;; eglot-typescript-preset.el --- Eglot preset for TypeScript -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Michael Olson <mwolson@gnu.org>

;; Version: 0.2.0
;; Author: Michael Olson <mwolson@gnu.org>
;; Maintainer: Michael Olson <mwolson@gnu.org>
;; URL: https://github.com/mwolson/eglot-typescript-preset
;; SPDX-License-Identifier: GPL-3.0-or-later
;; Keywords: typescript, javascript, convenience, languages, tools
;; Package-Requires: ((emacs "30.2") (eglot "1.17"))

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package provides a preset for Eglot to work with TypeScript,
;; JavaScript, CSS, Astro, and Vue files.  It configures LSP servers and
;; optional linter/formatter integration via rassumfrassum (rass).

;; Prerequisites:
;;
;; - Install typescript-language-server or deno (for TS/JS files)
;; - Install @astrojs/language-server (for Astro files, optional)
;; - Install @vue/language-server (for Vue files, optional)
;; - Optionally install eslint-language-server, biome, oxlint, or oxfmt
;; - Download this file and add it to the load path

;; Quick start:
;;
;;   (require 'eglot-typescript-preset)
;;   (eglot-typescript-preset-setup)
;;
;; After that, opening TypeScript, JavaScript, CSS, Astro, or Vue files
;; will automatically start the LSP server using Eglot.

;;; Code:

(require 'cl-lib)
(require 'json)

(declare-function eglot--managed-buffers "eglot")
(declare-function eglot-current-server "eglot")
(declare-function eglot-ensure "eglot")
(declare-function eglot-shutdown "eglot")

(defvar eglot-server-programs)
(defvar eglot-workspace-configuration)

(defgroup eglot-typescript-preset nil
  "TypeScript preset for Eglot."
  :group 'eglot
  :prefix "eglot-typescript-preset-")

;;;###autoload
(defcustom eglot-typescript-preset-lsp-server 'typescript-language-server
  "LSP server to use for TypeScript and JavaScript files."
  :type '(choice (const :tag "typescript-language-server" typescript-language-server)
                 (const :tag "deno" deno)
                 (const :tag "rass" rass))
  :group 'eglot-typescript-preset)

;;;###autoload
(defcustom eglot-typescript-preset-astro-lsp-server 'astro-ls
  "LSP server to use for Astro files."
  :type '(choice (const :tag "astro-ls" astro-ls)
                 (const :tag "rass" rass)
                 (const :tag "Disabled" nil))
  :group 'eglot-typescript-preset)

;;;###autoload
(defcustom eglot-typescript-preset-rass-program "rass"
  "Program used when `eglot-typescript-preset-lsp-server' is `rass'."
  :type 'string
  :group 'eglot-typescript-preset)

;;;###autoload
(defcustom eglot-typescript-preset-rass-command nil
  "Exact command vector to run when `eglot-typescript-preset-lsp-server' is `rass'.

When non-nil, this command is used verbatim and no generated preset is written.
The value must include the `rass` executable and any preset or arguments that
should be passed to it."
  :type '(choice
          (const :tag "Use generated preset" nil)
          (restricted-sexp
           :tag "Exact command vector"
           :value ["rass" "tslint"]
           :match-alternatives (eglot-typescript-preset--rass-command-vector-p)))
  :group 'eglot-typescript-preset)

;;;###autoload
(defcustom eglot-typescript-preset-astro-rass-command nil
  "Exact command vector to run for Astro when using `rass'.

When non-nil, this command is used verbatim and no generated preset is written."
  :type '(choice
          (const :tag "Use generated preset" nil)
          (restricted-sexp
           :tag "Exact command vector"
           :value ["rass" "tslint"]
           :match-alternatives
           (eglot-typescript-preset--rass-command-vector-p)))
  :group 'eglot-typescript-preset)

;;;###autoload
(defcustom eglot-typescript-preset-css-lsp-server 'rass
  "LSP server to use for CSS files."
  :type '(choice (const :tag "vscode-css-language-server"
                   vscode-css-language-server)
                 (const :tag "rass" rass)
                 (const :tag "Disabled" nil))
  :group 'eglot-typescript-preset)

;;;###autoload
(defcustom eglot-typescript-preset-css-rass-command nil
  "Exact command vector to run for CSS when using `rass'.

When non-nil, this command is used verbatim and no generated preset is written."
  :type '(choice
          (const :tag "Use generated preset" nil)
          (restricted-sexp
           :tag "Exact command vector"
           :value ["rass" "csstail"]
           :match-alternatives (eglot-typescript-preset--rass-command-vector-p)))
  :group 'eglot-typescript-preset)

;;;###autoload
(defcustom eglot-typescript-preset-vue-lsp-server 'rass
  "LSP server to use for Vue files."
  :type '(choice (const :tag "vue-language-server" vue-language-server)
                 (const :tag "rass" rass)
                 (const :tag "Disabled" nil))
  :group 'eglot-typescript-preset)

;;;###autoload
(defcustom eglot-typescript-preset-vue-rass-command nil
  "Exact command vector to run for Vue when using `rass'.

When non-nil, this command is used verbatim and no generated preset is written."
  :type '(choice
          (const :tag "Use generated preset" nil)
          (restricted-sexp
           :tag "Exact command vector"
           :value ["rass" "vuetail"]
           :match-alternatives (eglot-typescript-preset--rass-command-vector-p)))
  :group 'eglot-typescript-preset)

(defcustom eglot-typescript-preset-rass-max-contextual-presets 50
  "Maximum number of contextual generated `rass` presets to keep.

When more contextual presets are present in the generated preset directory,
older ones are deleted.  Shared presets are not affected."
  :type '(choice (const :tag "Disable cleanup" nil)
                 (integer :tag "Maximum contextual presets"))
  :group 'eglot-typescript-preset)

(defun eglot-typescript-preset--rass-command-vector-p (value)
  "Return non-nil if VALUE is a vector-form literal command."
  (and (vectorp value)
       (> (length value) 0)
       (seq-every-p #'stringp value)))

(defvar eglot-typescript-preset--rass-tools-type
  '(repeat
    (choice
     (const :tag "astro-ls" astro-ls)
     (const :tag "biome" biome)
     (const :tag "eslint" eslint)
     (const :tag "oxfmt" oxfmt)
     (const :tag "oxlint" oxlint)
     (const :tag "tailwindcss-language-server" tailwindcss-language-server)
     (const :tag "typescript-language-server" typescript-language-server)
     (const :tag "vscode-css-language-server" vscode-css-language-server)
     (const :tag "vue-language-server" vue-language-server)
     (restricted-sexp
      :tag "Command vector"
      :value ["command"]
      :match-alternatives (eglot-typescript-preset--rass-command-vector-p))))
  "Shared customize type for rass-tools variables.")

;;;###autoload
(defcustom eglot-typescript-preset-rass-tools
  '(typescript-language-server eslint)
  "Tools included in the generated `rass` preset for TS/JS files.

Each entry may be a supported symbol like `typescript-language-server',
`eslint', `biome', `oxlint', or `oxfmt', or a literal command vector
of strings."
  :type eglot-typescript-preset--rass-tools-type
  :group 'eglot-typescript-preset)

;;;###autoload
(defcustom eglot-typescript-preset-astro-rass-tools
  '(astro-ls eslint)
  "Tools included in the generated `rass` preset for Astro files.

Same format as `eglot-typescript-preset-rass-tools'."
  :type eglot-typescript-preset--rass-tools-type
  :group 'eglot-typescript-preset)

;;;###autoload
(defcustom eglot-typescript-preset-css-rass-tools
  '(vscode-css-language-server tailwindcss-language-server)
  "Tools included in the generated `rass` preset for CSS files.

Same format as `eglot-typescript-preset-rass-tools'."
  :type eglot-typescript-preset--rass-tools-type
  :group 'eglot-typescript-preset)

;;;###autoload
(defcustom eglot-typescript-preset-vue-rass-tools
  '(vue-language-server typescript-language-server tailwindcss-language-server)
  "Tools included in the generated `rass` preset for Vue files.

Same format as `eglot-typescript-preset-rass-tools'."
  :type eglot-typescript-preset--rass-tools-type
  :group 'eglot-typescript-preset)

;;;###autoload
(defcustom eglot-typescript-preset-tsdk nil
  "Path to the TypeScript SDK `lib' directory.

When non-nil, this is used as a fallback for the Astro and Vue
language servers' `typescript.tsdk' initialization option.
A project-local `node_modules/typescript/lib' always takes
priority.  When both are nil, the package falls back to
`npm root -g'."
  :type '(choice (const :tag "Auto-detect" nil)
                 (directory :tag "TypeScript SDK lib path"))
  :group 'eglot-typescript-preset)

;;;###autoload
(defcustom eglot-typescript-preset-js-project-markers
  '("package.json" "tsconfig.json" "jsconfig.json")
  "Files that indicate a JavaScript or TypeScript project root."
  :type '(repeat string)
  :group 'eglot-typescript-preset)

;;;###autoload
(defcustom eglot-typescript-preset-js-modes
  '( jtsx-jsx-mode jtsx-tsx-mode jtsx-typescript-mode
     js-mode js-ts-mode typescript-ts-mode tsx-ts-mode)
  "Major modes for JavaScript and TypeScript files."
  :type '(repeat symbol)
  :group 'eglot-typescript-preset)

;;;###autoload
(defcustom eglot-typescript-preset-astro-modes '(astro-ts-mode)
  "Major modes for Astro files."
  :type '(repeat symbol)
  :group 'eglot-typescript-preset)

;;;###autoload
(defcustom eglot-typescript-preset-css-modes '(css-mode css-ts-mode)
  "Major modes for CSS files."
  :type '(repeat symbol)
  :group 'eglot-typescript-preset)

;;;###autoload
(defcustom eglot-typescript-preset-vue-modes '(vue-mode vue-ts-mode)
  "Major modes for Vue files."
  :type '(repeat symbol)
  :group 'eglot-typescript-preset)

(defun eglot-typescript-preset--lsp-server-safe-p (value)
  "Return non-nil if VALUE is a safe `eglot-typescript-preset-lsp-server' value."
  (memq value '(typescript-language-server deno rass)))

(put 'eglot-typescript-preset-lsp-server 'safe-local-variable
     #'eglot-typescript-preset--lsp-server-safe-p)

(defun eglot-typescript-preset--astro-lsp-server-safe-p (value)
  "Return non-nil if VALUE is a safe `eglot-typescript-preset-astro-lsp-server'."
  (memq value '(astro-ls rass nil)))

(put 'eglot-typescript-preset-astro-lsp-server 'safe-local-variable
     #'eglot-typescript-preset--astro-lsp-server-safe-p)

(defun eglot-typescript-preset--css-lsp-server-safe-p (value)
  "Return non-nil if VALUE is safe for `eglot-typescript-preset-css-lsp-server'."
  (memq value '(vscode-css-language-server rass nil)))

(put 'eglot-typescript-preset-css-lsp-server 'safe-local-variable
     #'eglot-typescript-preset--css-lsp-server-safe-p)

(defun eglot-typescript-preset--vue-lsp-server-safe-p (value)
  "Return non-nil if VALUE is safe for `eglot-typescript-preset-vue-lsp-server'."
  (memq value '(vue-language-server rass nil)))

(put 'eglot-typescript-preset-vue-lsp-server 'safe-local-variable
     #'eglot-typescript-preset--vue-lsp-server-safe-p)

(defun eglot-typescript-preset--rass-tools-safe-p (value)
  "Return non-nil if VALUE is a safe `eglot-typescript-preset-rass-tools' value.
Only lists of known symbols are considered safe.  Literal command vectors
are excluded because they could execute arbitrary programs."
  (and (listp value)
       (seq-every-p (lambda (item)
                      (memq item '( astro-ls biome eslint oxfmt oxlint
                                    tailwindcss-language-server
                                    typescript-language-server
                                    vscode-css-language-server
                                    vue-language-server)))
                    value)))

(put 'eglot-typescript-preset-rass-tools 'safe-local-variable
     #'eglot-typescript-preset--rass-tools-safe-p)

(put 'eglot-typescript-preset-astro-rass-tools 'safe-local-variable
     #'eglot-typescript-preset--rass-tools-safe-p)

(put 'eglot-typescript-preset-css-rass-tools 'safe-local-variable
     #'eglot-typescript-preset--rass-tools-safe-p)

(put 'eglot-typescript-preset-vue-rass-tools 'safe-local-variable
     #'eglot-typescript-preset--rass-tools-safe-p)

(defun eglot-typescript-preset--project-markers-safe-p (value)
  "Return non-nil if VALUE is safe for project markers.
Checks `eglot-typescript-preset-js-project-markers'."
  (and (listp value)
       (seq-every-p #'stringp value)))

(put 'eglot-typescript-preset-js-project-markers 'safe-local-variable
     #'eglot-typescript-preset--project-markers-safe-p)

(defun eglot-typescript-preset--find-tsdk ()
  "Find the TypeScript SDK `lib' directory.

Project-local `node_modules/typescript/lib' takes highest priority.
If `eglot-typescript-preset-tsdk' is set, use that as a fallback.
As a last resort, try to find it via `npm root -g'."
  (or (when-let* ((root (eglot-typescript-preset--project-root))
                  (tsdk (expand-file-name "node_modules/typescript/lib" root))
                  ((file-directory-p tsdk)))
        tsdk)
      eglot-typescript-preset-tsdk
      (when-let* ((npm (executable-find "npm"))
                  (global-root (string-trim
                                (shell-command-to-string "npm root -g")))
                  ((not (string-empty-p global-root)))
                  (tsdk (expand-file-name "typescript/lib" global-root))
                  ((file-directory-p tsdk)))
        tsdk)))

(defun eglot-typescript-preset--node-modules-bin-dir ()
  "Return the project-local `node_modules/.bin' directory if it exists."
  (when-let* ((root (eglot-typescript-preset--project-root))
              (bin-dir (expand-file-name "node_modules/.bin" root))
              ((file-directory-p bin-dir)))
    bin-dir))

(defun eglot-typescript-preset--resolve-executable (name)
  "Resolve executable NAME, preferring the current project's `node_modules'."
  (or (when-let* ((bin-dir (eglot-typescript-preset--node-modules-bin-dir)))
        (let ((exec-path (cons bin-dir exec-path)))
          (executable-find name)))
      (executable-find name)
      name))

(defun eglot-typescript-preset--tool-kind-from-name (name)
  "Return the known tool kind for executable NAME, or nil."
  (when name
    (let ((base (downcase (file-name-sans-extension
                           (file-name-nondirectory name)))))
      (cond
       ((string= base "astro-ls") 'astro-ls)
       ((string= base "biome") 'biome)
       ((string= base "deno") 'deno)
       ((member base '("eslint" "eslint-language-server"
                       "vscode-eslint-language-server"))
        'eslint)
       ((string= base "oxfmt") 'oxfmt)
       ((string= base "oxlint") 'oxlint)
       ((string= base "tailwindcss-language-server")
        'tailwindcss-language-server)
       ((member base '("typescript-language-server" "tsserver"))
        'typescript-language-server)
       ((member base '("vscode-css-language-server" "css-language-server"
                       "css-languageserver"))
        'vscode-css-language-server)
       ((string= base "vue-language-server") 'vue-language-server)))))

(defun eglot-typescript-preset--rass-tool-command (tool)
  "Return the server command for `rass` TOOL."
  (cond
   ((eq tool 'astro-ls)
    (list (eglot-typescript-preset--resolve-executable "astro-ls")
          "--stdio"))
   ((eq tool 'biome)
    (list (eglot-typescript-preset--resolve-executable "biome")
          "lsp-proxy"))
   ((eq tool 'eslint)
    (list (eglot-typescript-preset--resolve-executable
           "vscode-eslint-language-server")
          "--stdio"))
   ((eq tool 'oxfmt)
    (list (eglot-typescript-preset--resolve-executable "oxfmt")
          "--lsp"))
   ((eq tool 'oxlint)
    (list (eglot-typescript-preset--resolve-executable "oxlint")
          "--lsp"))
   ((eq tool 'tailwindcss-language-server)
    (list (eglot-typescript-preset--resolve-executable
           "tailwindcss-language-server")
          "--stdio"))
   ((eq tool 'typescript-language-server)
    (list (eglot-typescript-preset--resolve-executable
           "typescript-language-server")
          "--stdio"))
   ((eq tool 'vscode-css-language-server)
    (list (eglot-typescript-preset--resolve-executable
           "vscode-css-language-server")
          "--stdio"))
   ((eq tool 'vue-language-server)
    (list (eglot-typescript-preset--resolve-executable
           "vue-language-server")
          "--stdio"))
   ((vectorp tool)
    (let* ((command (append tool nil))
           (kind (eglot-typescript-preset--tool-kind-from-name (car command))))
      (when kind
        (setcar command
                (eglot-typescript-preset--resolve-executable (car command))))
      command))
   (t
    (user-error "Unsupported `rass` tool entry: %S" tool))))

(defun eglot-typescript-preset--rass-tool-kind (command)
  "Return the supported tool kind for COMMAND, or nil."
  (eglot-typescript-preset--tool-kind-from-name (car command)))

(defun eglot-typescript-preset--rass-json-string (object)
  "Serialize OBJECT to JSON.
Handles `:json-false' by serializing nil as false."
  (decode-coding-string
   (json-serialize object :false-object :json-false) 'utf-8))

(defun eglot-typescript-preset--rass-python-literal (object)
  "Serialize OBJECT to a Python-compatible literal string.

Like JSON but with True/False/None instead of true/false/null."
  (let ((json (eglot-typescript-preset--rass-json-string object)))
    (setq json (replace-regexp-in-string "\\btrue\\b" "True" json t))
    (setq json (replace-regexp-in-string "\\bfalse\\b" "False" json t))
    (replace-regexp-in-string "\\bnull\\b" "None" json t)))

(defun eglot-typescript-preset--rass-generated-dir ()
  "Return the directory used for generated `rass` presets."
  (expand-file-name "eglot-typescript-preset/" user-emacs-directory))

(defun eglot-typescript-preset--library-dir ()
  "Return directory containing the installed library."
  (file-name-directory
   (or load-file-name
       byte-compile-current-file
       (locate-library "eglot-typescript-preset")
       default-directory)))

(defun eglot-typescript-preset--path-in-directory-p (path dir)
  "Return non-nil if PATH is inside DIR."
  (when (and path dir)
    (let ((path (file-truename path))
          (dir (file-name-as-directory (file-truename dir))))
      (string-prefix-p dir path))))

(defvar eglot-typescript-preset--template-cache (make-hash-table :test 'equal)
  "Cache for package template contents.")

(defun eglot-typescript-preset--template-string (name)
  "Return template NAME from the installed package."
  (let* ((path (expand-file-name
                name (expand-file-name
                      "templates"
                      (eglot-typescript-preset--library-dir))))
         (attrs (file-attributes path))
         (mtime (file-attribute-modification-time attrs))
         (cached (gethash name eglot-typescript-preset--template-cache)))
    (if (and cached
             (equal (plist-get cached :path) path)
             (equal (plist-get cached :mtime) mtime))
        (plist-get cached :content)
      (let ((content
             (with-temp-buffer
               (insert-file-contents path)
               (buffer-string))))
        (puthash name
                 (list :content content :mtime mtime :path path)
                 eglot-typescript-preset--template-cache)
        content))))

(defun eglot-typescript-preset--render-template (name replacements)
  "Render template NAME using REPLACEMENTS.

REPLACEMENTS is an alist mapping literal placeholder strings to values."
  (let ((template (eglot-typescript-preset--template-string name)))
    (dolist (replacement replacements template)
      (setq template
            (replace-regexp-in-string
             (regexp-quote (car replacement))
             (cdr replacement)
             template
             t t)))))

(defun eglot-typescript-preset--rass-tool-label (tool)
  "Return a stable filename label for `rass` TOOL."
  (let* ((text (cond
                ((symbolp tool)
                 (symbol-name tool))
                ((vectorp tool)
                 (let* ((command (append tool nil))
                        (program (file-name-sans-extension
                                  (file-name-nondirectory (car command))))
                        (base (if (string-empty-p program)
                                  "tool"
                                program)))
                   (if (= (length command) 1)
                       base
                     (format "%s-argv-%s"
                             base
                             (substring (secure-hash 'sha256
                                                     (prin1-to-string tool))
                                        0 12)))))
                (t
                 (user-error "Unsupported `rass` tool entry: %S" tool)))))
    (string-trim
     (replace-regexp-in-string
      "-+"
      "-"
      (replace-regexp-in-string "[^[:alnum:]]+" "-" (downcase text)))
     "-"
     "-")))

(defun eglot-typescript-preset--rass-shared-preset-path (tools)
  "Return the stable shared preset path for TOOLS."
  (let* ((labels (mapcar #'eglot-typescript-preset--rass-tool-label tools))
         (slug (string-join labels "-"))
         (hash (substring (secure-hash 'sha256 (prin1-to-string tools))
                          0 12)))
    (expand-file-name
     (format "rass-preset-shared-%s-%s.py" slug hash)
     (eglot-typescript-preset--rass-generated-dir))))

(defun eglot-typescript-preset--rass-contextual-preset-path (hash-input)
  "Return the contextual preset path for HASH-INPUT."
  (expand-file-name
   (format "rass-preset-contextual-%s.py"
           (secure-hash 'sha256 hash-input))
   (eglot-typescript-preset--rass-generated-dir)))

(defun eglot-typescript-preset--rass-tool-spec (tool)
  "Return metadata for `rass` TOOL."
  (let* ((command (eglot-typescript-preset--rass-tool-command tool))
         (kind (eglot-typescript-preset--rass-tool-kind command))
         (program (car command)))
    (list :tool tool
          :command command
          :kind kind
          :local-node-modules-sensitive
          (and kind
               (stringp program)
               (when-let* ((bin-dir
                            (eglot-typescript-preset--node-modules-bin-dir)))
                 (eglot-typescript-preset--path-in-directory-p
                  program bin-dir))))))

(defun eglot-typescript-preset--write-file-if-changed (path content)
  "Write CONTENT to PATH only when it differs from the existing file."
  (make-directory (file-name-directory path) t)
  (unless (and (file-exists-p path)
               (with-temp-buffer
                 (insert-file-contents path)
                 (string= (buffer-string) content)))
    (with-temp-file path
      (insert content))))

(defun eglot-typescript-preset--cleanup-rass-contextual-presets
    (&optional preserve-path)
  "Delete older contextual generated `rass` presets, preserving PRESERVE-PATH."
  (when-let* (((integerp eglot-typescript-preset-rass-max-contextual-presets))
              ((> eglot-typescript-preset-rass-max-contextual-presets 0))
              (dir (eglot-typescript-preset--rass-generated-dir))
              ((file-directory-p dir)))
    (let ((files (directory-files dir t "^rass-preset-contextual-.*\\.py\\'")))
      (setq files
            (sort files
                  (lambda (a b)
                    (time-less-p
                     (file-attribute-modification-time (file-attributes b))
                     (file-attribute-modification-time (file-attributes a))))))
      (when preserve-path
        (setq files
              (cons preserve-path
                    (delete preserve-path files))))
      (let ((overflow
             (nthcdr eglot-typescript-preset-rass-max-contextual-presets
                     files)))
        (dolist (file overflow)
          (when (file-exists-p file)
            (delete-file file)))))))

(defun eglot-typescript-preset--astro-init-options ()
  "Return initializationOptions for the Astro language server."
  (let ((tsdk (eglot-typescript-preset--find-tsdk)))
    (if tsdk
        `(:contentIntellisense t :typescript (:tsdk ,tsdk))
      '(:contentIntellisense t))))

(defun eglot-typescript-preset--vue-init-options ()
  "Return initializationOptions for the Vue language server."
  (let ((tsdk (eglot-typescript-preset--find-tsdk)))
    (if tsdk
        `(:typescript (:tsdk ,tsdk) :vue (:hybridMode t))
      '(:vue (:hybridMode t)))))

(defun eglot-typescript-preset--find-vue-ts-plugin ()
  "Find the @vue/typescript-plugin directory.
Walk up from the buffer's directory looking for node_modules that
contain the plugin.  Fall back to resolving via the
vue-language-server binary."
  (or (when-let* ((file (or (buffer-file-name) default-directory))
                  (start (file-name-directory (expand-file-name file)))
                  (nm (locate-dominating-file
                       start
                       (lambda (d)
                         (file-directory-p
                          (expand-file-name
                           "node_modules/@vue/typescript-plugin" d)))))
                  (dir (expand-file-name
                        "node_modules/@vue/typescript-plugin" nm))
                  ((file-directory-p dir)))
        dir)
      (when-let* ((bin (eglot-typescript-preset--resolve-executable
                        "vue-language-server"))
                  ((not (string= bin "vue-language-server")))
                  (real (file-truename bin))
                  (nm (locate-dominating-file
                       (file-name-directory real)
                       (lambda (d)
                         (file-directory-p
                          (expand-file-name
                           "@vue/typescript-plugin" d)))))
                  (dir (expand-file-name "@vue/typescript-plugin" nm))
                  ((file-directory-p dir)))
        dir)))

(defun eglot-typescript-preset--write-rass-preset (path commands
                                                        init-options
                                                        eslint-logic-p
                                                        vue-ts-plugin)
  "Write a generated `rass` preset to PATH.

COMMANDS is the list of server commands.
INIT-OPTIONS, when non-nil, is a plist to inject into `initialize'.
ESLINT-LOGIC-P, when non-nil, enables ESLint workspace/configuration logic.
VUE-TS-PLUGIN, when non-nil, is the path to @vue/typescript-plugin."
  (eglot-typescript-preset--write-file-if-changed
   path
   (eglot-typescript-preset--render-template
    "rass-preset.tpl.py"
    `(("__SERVERS__"
       . ,(eglot-typescript-preset--rass-json-string
           (vconcat (mapcar #'vconcat commands))))
      ("__INIT_OPTIONS__"
       . ,(if init-options
              (eglot-typescript-preset--rass-python-literal init-options)
            "None"))
      ("__ESLINT_LOGIC__"
       . ,(if eslint-logic-p "True" "False"))
      ("__VUE_TS_PLUGIN__"
       . ,(if vue-ts-plugin
              (format "%S" vue-ts-plugin)
            "None"))))))

(defun eglot-typescript-preset--rass-preset-path (tools rass-command)
  "Return the generated `rass` preset path for TOOLS.

RASS-COMMAND, when non-nil, means use it verbatim instead.
Returns the preset path, or nil when RASS-COMMAND is set."
  (unless rass-command
    (eglot-typescript-preset--rass-preset-path-1 tools)))

(defun eglot-typescript-preset--rass-init-options-for-tools (commands)
  "Return merged initializationOptions for COMMANDS, or nil."
  (let ((has-astro (seq-some (lambda (cmd)
                               (eq (eglot-typescript-preset--rass-tool-kind cmd)
                                   'astro-ls))
                             commands))
        (has-vue (seq-some (lambda (cmd)
                             (eq (eglot-typescript-preset--rass-tool-kind cmd)
                                 'vue-language-server))
                           commands)))
    (cond
     (has-astro (eglot-typescript-preset--astro-init-options))
     (has-vue (eglot-typescript-preset--vue-init-options)))))

(defun eglot-typescript-preset--rass-vue-ts-plugin-for-tools (commands)
  "Return the @vue/typescript-plugin path when COMMANDS need it."
  (let ((has-vue (seq-some (lambda (cmd)
                             (eq (eglot-typescript-preset--rass-tool-kind cmd)
                                 'vue-language-server))
                           commands))
        (has-ts (seq-some (lambda (cmd)
                            (eq (eglot-typescript-preset--rass-tool-kind cmd)
                                'typescript-language-server))
                          commands)))
    (when (and has-vue has-ts)
      (eglot-typescript-preset--find-vue-ts-plugin))))

(defun eglot-typescript-preset--rass-preset-path-1 (tools)
  "Generate and return the `rass` preset path for TOOLS."
  (let* ((tool-specs (mapcar #'eglot-typescript-preset--rass-tool-spec tools))
         (commands (mapcar (lambda (tool-spec)
                             (plist-get tool-spec :command))
                           tool-specs))
         (init-options
          (eglot-typescript-preset--rass-init-options-for-tools commands))
         (vue-ts-plugin
          (eglot-typescript-preset--rass-vue-ts-plugin-for-tools commands))
         (has-eslint (seq-some (lambda (command)
                                 (eq (eglot-typescript-preset--rass-tool-kind
                                      command)
                                     'eslint))
                               commands))
         (contextual-p (or init-options
                           vue-ts-plugin
                           (seq-some
                            (lambda (tool-spec)
                              (plist-get
                               tool-spec :local-node-modules-sensitive))
                            tool-specs)))
         (path (if contextual-p
                   (eglot-typescript-preset--rass-contextual-preset-path
                    (mapconcat #'identity
                               (delq nil
                                     (list
                                      (eglot-typescript-preset--rass-json-string
                                       (vconcat (mapcar #'vconcat commands)))
                                      (when init-options
                                        (eglot-typescript-preset--rass-json-string
                                         init-options))
                                      vue-ts-plugin))
                               "\0"))
                 (eglot-typescript-preset--rass-shared-preset-path tools))))
    (eglot-typescript-preset--write-rass-preset
     path commands init-options has-eslint vue-ts-plugin)
    (when contextual-p
      (eglot-typescript-preset--cleanup-rass-contextual-presets path))
    path))

(defun eglot-typescript-preset--in-indirect-md-buffer-p ()
  "Return non-nil if buffer is an indirect buffer from a markdown buffer."
  (when-let* ((buf (buffer-base-buffer))
              ((buffer-live-p buf)))
    (with-current-buffer buf
      (derived-mode-p 'markdown-mode))))

(defun eglot-typescript-preset--js-project-root-p (dir)
  "Return non-nil if DIR has a JS/TS project marker file."
  (seq-some (lambda (file)
              (file-exists-p (expand-file-name file dir)))
            eglot-typescript-preset-js-project-markers))

(defvar eglot-lsp-context)

(defun eglot-typescript-preset--project-find (dir)
  "Project detection for JavaScript and TypeScript files.

Returns (js-project . ROOT) if DIR is inside a JS/TS project.
Only activates when `eglot-lsp-context' is non-nil so that
`project-find-file' and other project.el commands fall through to
the VC backend, which respects .gitignore."
  (when (and (bound-and-true-p eglot-lsp-context)
             (not (eglot-typescript-preset--in-indirect-md-buffer-p)))
    (when-let* ((root (locate-dominating-file
                       dir
                       #'eglot-typescript-preset--js-project-root-p)))
      (cons 'js-project root))))

(defun eglot-typescript-preset--project-root ()
  "Return the current buffer's project root."
  (when-let* ((file (buffer-file-name))
              (root (locate-dominating-file
                     (file-name-directory file)
                     #'eglot-typescript-preset--js-project-root-p)))
    (file-name-as-directory root)))

(cl-defmethod project-root ((project (head js-project)))
  "Return root directory of PROJECT."
  (cdr project))

(defun eglot-typescript-preset--server-contact (_interactive)
  "Return the server contact spec for TypeScript/JavaScript LSP."
  (pcase eglot-typescript-preset-lsp-server
    ('rass
     (if eglot-typescript-preset-rass-command
         (append eglot-typescript-preset-rass-command nil)
       (list (eglot-typescript-preset--resolve-executable
              eglot-typescript-preset-rass-program)
             (eglot-typescript-preset--rass-preset-path
              eglot-typescript-preset-rass-tools
              eglot-typescript-preset-rass-command))))
    ('deno
     `(,(eglot-typescript-preset--resolve-executable "deno") "lsp"
       :initializationOptions (:enable t :lint t)))
    ('typescript-language-server
     (list (eglot-typescript-preset--resolve-executable
            "typescript-language-server")
           "--stdio"))))

(defun eglot-typescript-preset--astro-server-contact (_interactive)
  "Return the server contact spec for Astro LSP."
  (pcase eglot-typescript-preset-astro-lsp-server
    ('rass
     (if eglot-typescript-preset-astro-rass-command
         (append eglot-typescript-preset-astro-rass-command nil)
       (list (eglot-typescript-preset--resolve-executable
              eglot-typescript-preset-rass-program)
             (eglot-typescript-preset--rass-preset-path
              eglot-typescript-preset-astro-rass-tools
              eglot-typescript-preset-astro-rass-command))))
    ('astro-ls
     (let* ((init-options (eglot-typescript-preset--astro-init-options))
            (command (list (eglot-typescript-preset--resolve-executable
                            "astro-ls")
                           "--stdio")))
       (if init-options
           `(,@command :initializationOptions ,init-options)
         command)))))

(defun eglot-typescript-preset--vue-server-contact (_interactive)
  "Return the server contact spec for Vue LSP."
  (pcase eglot-typescript-preset-vue-lsp-server
    ('rass
     (if eglot-typescript-preset-vue-rass-command
         (append eglot-typescript-preset-vue-rass-command nil)
       (list (eglot-typescript-preset--resolve-executable
              eglot-typescript-preset-rass-program)
             (eglot-typescript-preset--rass-preset-path
              eglot-typescript-preset-vue-rass-tools
              eglot-typescript-preset-vue-rass-command))))
    ('vue-language-server
     (let* ((init-options (eglot-typescript-preset--vue-init-options))
            (command (list (eglot-typescript-preset--resolve-executable
                            "vue-language-server")
                           "--stdio")))
       (if init-options
           `(,@command :initializationOptions ,init-options)
         command)))))

(defun eglot-typescript-preset--workspace-configuration-plist-a
    (orig-fn server &optional path)
  "Advice to merge ESLint configuration into workspace configuration.

Calls ORIG-FN with SERVER and PATH arguments, then merges ESLint
configuration when the server is an ESLint language server."
  (let ((base-config (funcall orig-fn server path)))
    (if-let* (((eq eglot-typescript-preset-lsp-server
                   'typescript-language-server))
              (buf (car (eglot--managed-buffers server)))
              ((with-current-buffer buf
                 (apply #'derived-mode-p
                        eglot-typescript-preset-js-modes))))
        base-config
      base-config)))

(defun eglot-typescript-preset--css-server-contact (_interactive)
  "Return the server contact spec for CSS LSP."
  (pcase eglot-typescript-preset-css-lsp-server
    ('rass
     (if eglot-typescript-preset-css-rass-command
         (append eglot-typescript-preset-css-rass-command nil)
       (list (eglot-typescript-preset--resolve-executable
              eglot-typescript-preset-rass-program)
             (eglot-typescript-preset--rass-preset-path
              eglot-typescript-preset-css-rass-tools
              eglot-typescript-preset-css-rass-command))))
    ('vscode-css-language-server
     (list (eglot-typescript-preset--resolve-executable
            "vscode-css-language-server")
           "--stdio"))))

;;;###autoload
(defun eglot-typescript-preset-setup ()
  "Set up Eglot to support TypeScript, JavaScript, CSS, Astro, and Vue modes.

Adds hooks for project detection and Eglot configuration.
Configures `eglot-server-programs' based on the preset settings.
Call this after loading Eglot."
  (interactive)
  (add-to-list 'eglot-server-programs
               `(,eglot-typescript-preset-js-modes
                 . eglot-typescript-preset--server-contact))
  (when eglot-typescript-preset-astro-lsp-server
    (add-to-list 'eglot-server-programs
                 `(,eglot-typescript-preset-astro-modes
                   . eglot-typescript-preset--astro-server-contact)))
  (when eglot-typescript-preset-css-lsp-server
    (add-to-list 'eglot-server-programs
                 `(,eglot-typescript-preset-css-modes
                   . eglot-typescript-preset--css-server-contact)))
  (when eglot-typescript-preset-vue-lsp-server
    (add-to-list 'eglot-server-programs
                 `(,eglot-typescript-preset-vue-modes
                   . eglot-typescript-preset--vue-server-contact)))
  (add-hook 'project-find-functions
            #'eglot-typescript-preset--project-find))

(provide 'eglot-typescript-preset)
;;; eglot-typescript-preset.el ends here
