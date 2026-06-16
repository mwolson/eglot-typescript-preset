# eglot-typescript-preset

[![MELPA](https://melpa.org/packages/eglot-typescript-preset-badge.svg)](https://melpa.org/#/eglot-typescript-preset)
![Made for GNU Emacs](assets/badges/made-for-gnu-emacs.svg)

Configures TypeScript, JavaScript, CSS, Astro, Vue, and Svelte LSP support for
Emacs using [Eglot](https://github.com/joaotavora/eglot), with optional linter
and formatter integration via
[rassumfrassum](https://github.com/joaotavora/rassumfrassum).

This package configures Eglot to work with TypeScript and JavaScript files using
[typescript-language-server](https://github.com/typescript-language-server/typescript-language-server),
[deno](https://deno.land/), or
[rassumfrassum](https://github.com/joaotavora/rassumfrassum) as the language
server frontend. It supports combining multiple tools -- ESLint, Biome, oxlint,
and oxfmt -- through generated `rass` presets, and includes CSS, Astro, Vue, and
Svelte support via their respective language servers.

See also [eglot-python-preset](https://github.com/mwolson/eglot-python-preset)
for Python support.

## Why to use this library

- You want TypeScript/JavaScript LSP support in Emacs that just works, without
  spending time configuring it yourself.
- You maintain an [Emacs starter kit](https://github.com/mwolson/emacs-shared)
  and want reliable LSP defaults for your users.
- You use monorepos, where project root detection matters; this is nontrivial to
  get right for LSPs.
- You work in (or browse) quite a few different projects, each needing a
  slightly different tool setup, and you want easy per-project configuration via
  `.dir-locals.el` or `dir-locals-set-directory-class`.
- You want to combine multiple tools (ESLint, Biome, oxlint, oxfmt, Tailwind
  CSS) through a single Eglot connection, without writing `rass` presets by
  hand - it's especially neat to be able to combine ESLint and oxlint (with
  `eslint-plugin-oxlint` enabled in your ESLint settings) so that oxlint can
  gradually take over responsibilities from ESLint in your projects.
- You want project-local `node_modules/.bin` executables to be found
  automatically, with a fallback to globally installed tools.
- You work with frameworks like Astro, Vue, or Svelte that each need TypeScript
  SDK paths and framework-specific initialization options wired up correctly.
- You use non-standard major modes (like the `jtsx-*` family) and want language
  IDs mapped correctly so that servers like `vscode-eslint-language-server`
  accept your files.
- You'd rather have someone else find all the edge cases and fix them in
  advance, with tests to prevent them from recurring.

## Why not to use it

- You use just one language server at a time and already know how to configure
  each one for Eglot.
- You have simple projects, or just one kind of setup across all your projects,
  and you've already found something that works for you.
- You prefer [lsp-mode](https://emacs-lsp.github.io/lsp-mode/) over Eglot.

## Prerequisites

- Emacs 30.2 or later
- One of the following for TypeScript/JavaScript:
  - [typescript-language-server](https://github.com/typescript-language-server/typescript-language-server)
    -- the standard TypeScript LSP
  - [deno](https://deno.land/) -- Deno's built-in LSP (`deno lsp`)
  - [rassumfrassum](https://github.com/joaotavora/rassumfrassum) (>= v0.3.3) --
    optional stdio multiplexer for combining multiple tools
- Optional linters and formatters (used with `rass` backend):
  - [biome](https://biomejs.dev/) -- linter and formatter
  - [eslint](https://eslint.org/) and its VSCode language server from
    [vscode-langservers-extracted](https://www.npmjs.com/package/vscode-langservers-extracted)
    or a less well-known but up-to-date (as of April 2026) fork like
    [@t1ckbase/vscode-langservers-extracted](https://www.npmjs.com/package/@t1ckbase/vscode-langservers-extracted)
  - [oxfmt](https://oxc.rs/docs/guide/usage/formatter.html) -- fast formatter
  - [oxlint](https://oxc.rs/docs/guide/usage/linter.html) -- fast linter
  - [@tailwindcss/language-server](https://www.npmjs.com/package/@tailwindcss/language-server)
    -- Tailwind CSS support
  - VSCode's CSS language server from
    [vscode-langservers-extracted](https://www.npmjs.com/package/vscode-langservers-extracted)
    or a less well-known but up-to-date (as of April 2026) fork like
    [@t1ckbase/vscode-langservers-extracted](https://www.npmjs.com/package/@t1ckbase/vscode-langservers-extracted)
- Optional for Astro:
  - [@astrojs/language-server](https://www.npmjs.com/@astrojs/language-server)
    (provides the `astro-ls` command)
- Optional for Svelte:
  - [svelte-language-server](https://www.npmjs.com/svelte-language-server)
    (provides the `svelteserver` command)
- Optional for Vue:
  - [@vue/language-server](https://www.npmjs.com/@vue/language-server) (provides
    the `vue-language-server` command)
  - [@vue/typescript-plugin](https://www.npmjs.com/package/@vue/typescript-plugin)
    for TypeScript completions and type checking inside `.vue` files

## Installation

Choose one of the following ways to install. After that, opening TypeScript,
JavaScript, CSS, Astro, Vue, or Svelte files will automatically start the LSP
server using Eglot.

### Using package-vc (recommended)

For Emacs 30.2+, use the built-in `package-vc` via `use-package`:

```elisp
(use-package eglot-typescript-preset
  :vc (:url "https://github.com/mwolson/eglot-typescript-preset"
       :main-file "eglot-typescript-preset.el"))
```

This will download and install the package automatically if it is not already
installed. By default, `:vc` installs the latest release rather than the latest
commit.

To track the development version instead, use `:rev :newest`:

```elisp
(use-package eglot-typescript-preset
  :vc (:url "https://github.com/mwolson/eglot-typescript-preset"
       :main-file "eglot-typescript-preset.el"
       :rev :newest))
```

The package sets up Eglot integration automatically when Eglot loads, so no
explicit setup call is needed.

If you're interested in trying out some beta software to improve `package-vc`
further, take a look at [vcupp](https://github.com/mwolson/vcupp).

### Manual installation

Clone this repository:

```bash
mkdir -p ~/devel
git clone https://github.com/mwolson/eglot-typescript-preset ~/devel/eglot-typescript-preset
```

Then add it to your Emacs configuration:

```elisp
(add-to-list 'load-path (expand-file-name "~/devel/eglot-typescript-preset"))
(require 'eglot-typescript-preset)
```

or:

```elisp
(use-package eglot-typescript-preset
  :load-path "/path/to/eglot-typescript-preset")
```

### From MELPA

```elisp
(use-package eglot-typescript-preset
  :ensure t)
```

## Installing Language Servers

The language servers used by this package are installed separately. You can
install them globally (so the commands are available on your PATH) or locally in
each project (the package resolves project-local `node_modules/.bin`
automatically). The examples below use `bun`; substitute `npm`, `pnpm`, or
`yarn` as needed.

### TypeScript/JavaScript

```bash
bun install -g typescript typescript-language-server
```

### CSS and ESLint

The `vscode-css-language-server` and `vscode-eslint-language-server` commands
are provided by the `vscode-langservers-extracted` package, which bundles
several language servers extracted from VS Code:

```bash
bun install -g vscode-langservers-extracted
```

Alternatively, there is a fork that tracks more recent VS Code releases as of
April 2026 (pinned here to be exactly the version I tested):

```bash
bun install -g @t1ckbase/vscode-langservers-extracted@1.0.2
```

### Tailwind CSS

```bash
bun install -g @tailwindcss/language-server
```

### Astro

```bash
bun install -g @astrojs/language-server
```

This provides the `astro-ls` command.

### Vue

```bash
bun install -g @vue/language-server
```

This provides the `vue-language-server` command.

### Svelte

```bash
bun install -g svelte-language-server
```

This provides the `svelteserver` command.

### Biome

```bash
bun install -g @biomejs/biome
```

### oxfmt

```bash
bun install -g oxfmt
```

### oxlint

```bash
bun install -g oxlint
```

## Usage

### Standard TypeScript/JavaScript Projects

For standard projects (those with `package.json`, `tsconfig.json`, or
`jsconfig.json`), the package automatically detects the project root and starts
Eglot with appropriate configuration. This behaves as if the following were set:

```elisp
(add-to-list 'eglot-server-programs
             '((js-mode js-ts-mode tsx-ts-mode typescript-ts-mode
                jtsx-jsx-mode jtsx-tsx-mode jtsx-typescript-mode)
               "typescript-language-server" "--stdio"))
```

### Deno Projects

Set the LSP server to `deno` for projects that use Deno instead of Node.js:

```elisp
(setopt eglot-typescript-preset-lsp-server 'deno)
```

This starts `deno lsp` with `enable` and `lint` enabled. Per-project
configuration via `.dir-locals.el` is also supported (see below). This behaves
as if the following were set:

```elisp
(add-to-list 'eglot-server-programs
             '((js-mode js-ts-mode tsx-ts-mode typescript-ts-mode
                jtsx-jsx-mode jtsx-tsx-mode jtsx-typescript-mode)
               "deno" "lsp"
               :initializationOptions (:enable t :lint t)))
```

### CSS Projects

When `eglot-typescript-preset-css-lsp-server` is set (default: `rass`), the
package configures Eglot for `css-mode` and `css-ts-mode` buffers. The default
`rass` backend combines `vscode-css-language-server` (for standard CSS language
features) with `tailwindcss-language-server` (for Tailwind CSS diagnostics and
completions). This behaves as if the following were set:

```elisp
;; With rass backend (default), combining these tools:
(setopt eglot-typescript-preset-css-lsp-server 'rass)
(setopt eglot-typescript-preset-css-rass-tools
        '(vscode-css-language-server tailwindcss-language-server))

;; With standalone vscode-css-language-server:
(add-to-list 'eglot-server-programs
             '((css-mode css-ts-mode)
               "vscode-css-language-server" "--stdio"))
```

### Astro Projects

When `eglot-typescript-preset-astro-lsp-server` is set (default: `rass`), the
package configures Eglot for `astro-ts-mode` buffers, including automatic
TypeScript SDK detection for the Astro language server. This behaves as if the
following were set:

```elisp
;; With rass backend (default), combining these tools:
(setopt eglot-typescript-preset-astro-lsp-server 'rass)
(setopt eglot-typescript-preset-astro-rass-tools
        '(astro-ls eslint tailwindcss-language-server))

;; With standalone astro-ls:
(add-to-list 'eglot-server-programs
             '(astro-ts-mode "astro-ls" "--stdio"
               :initializationOptions
               (:contentIntellisense t
                :typescript (:tsdk "/path/to/typescript/lib"))))
```

### Vue Projects

When `eglot-typescript-preset-vue-lsp-server` is set (default: `rass`), the
package configures Eglot for `vue-mode` and `vue-ts-mode` buffers. In hybrid
mode, `vue-language-server` handles Vue-specific features (template errors)
while `typescript-language-server` with `@vue/typescript-plugin` provides
TypeScript semantics (type checking, completions). The Vue language server
receives TypeScript SDK path and `vue.hybridMode` initialization options
automatically. With the default `rass` backend, this behaves as if the following
were set:

```elisp
;; With rass backend (default), combining these tools:
(setopt eglot-typescript-preset-vue-lsp-server 'rass)
(setopt eglot-typescript-preset-vue-rass-tools
        '(vue-language-server typescript-language-server
          tailwindcss-language-server))

;; With standalone vue-language-server:
(add-to-list 'eglot-server-programs
             '((vue-mode vue-ts-mode)
               "vue-language-server" "--stdio"
               :initializationOptions
               (:typescript (:tsdk "/path/to/typescript/lib")
                :vue (:hybridMode t))))
```

### Svelte Projects

When `eglot-typescript-preset-svelte-lsp-server` is set (default: `rass`), the
package configures Eglot for `svelte-mode` and `svelte-ts-mode` buffers. The
`svelte-language-server` handles Svelte-specific features while
`typescript-language-server` provides TypeScript semantics for standalone `.ts`
files. The Svelte language server receives TypeScript SDK path initialization
options automatically when available. With the default `rass` backend, this
behaves as if the following were set:

```elisp
;; With rass backend (default), combining these tools:
(setopt eglot-typescript-preset-svelte-lsp-server 'rass)
(setopt eglot-typescript-preset-svelte-rass-tools
        '(svelte-language-server typescript-language-server
          tailwindcss-language-server))

;; With standalone svelte-language-server:
(add-to-list 'eglot-server-programs
             '((svelte-mode svelte-ts-mode)
               "svelteserver" "--stdio"
               :initializationOptions
               (:configuration
                (:typescript (:tsdk "/path/to/typescript/lib")))))
```

## Configuration

### `eglot-typescript-preset-auto-setup`

Controls whether Eglot integration is set up automatically when Eglot loads
(default: `t`). Set to `nil` before the package loads to suppress automatic
setup and call `eglot-typescript-preset-setup` manually instead:

```elisp
(use-package eglot-typescript-preset
  :vc (:url "https://github.com/mwolson/eglot-typescript-preset"
       :main-file "eglot-typescript-preset.el")
  :custom
  (eglot-typescript-preset-auto-setup nil)
  :config
  (eglot-typescript-preset-setup))
```

### `eglot-typescript-preset-lsp-server`

Choose which language server to use for TypeScript/JavaScript:

```elisp
(setopt eglot-typescript-preset-lsp-server 'typescript-language-server) ; default
;; or
(setopt eglot-typescript-preset-lsp-server 'deno)
;; or
(setopt eglot-typescript-preset-lsp-server 'rass)
```

### `eglot-typescript-preset-css-lsp-server`

Choose which language server to use for CSS:

```elisp
(setopt eglot-typescript-preset-css-lsp-server 'rass) ; default
;; or
(setopt eglot-typescript-preset-css-lsp-server 'vscode-css-language-server)
;; or
(setopt eglot-typescript-preset-css-lsp-server nil) ; disable CSS support
```

### `eglot-typescript-preset-astro-lsp-server`

Choose which language server to use for Astro:

```elisp
(setopt eglot-typescript-preset-astro-lsp-server 'rass) ; default
;; or
(setopt eglot-typescript-preset-astro-lsp-server 'astro-ls)
;; or
(setopt eglot-typescript-preset-astro-lsp-server nil) ; disable Astro support
```

### `eglot-typescript-preset-vue-lsp-server`

Choose which language server to use for Vue:

```elisp
(setopt eglot-typescript-preset-vue-lsp-server 'rass) ; default
;; or
(setopt eglot-typescript-preset-vue-lsp-server 'vue-language-server)
;; or
(setopt eglot-typescript-preset-vue-lsp-server nil) ; disable Vue support
```

### `eglot-typescript-preset-svelte-lsp-server`

Choose which language server to use for Svelte:

```elisp
(setopt eglot-typescript-preset-svelte-lsp-server 'rass) ; default
;; or
(setopt eglot-typescript-preset-svelte-lsp-server 'svelte-language-server)
;; or
(setopt eglot-typescript-preset-svelte-lsp-server nil) ; disable Svelte support
```

### `eglot-typescript-preset-rass-tools`

When using the `rass` backend, this list controls the generated preset for
TypeScript/JavaScript files. Supported tools get local `node_modules` executable
resolution:

```elisp
(setopt eglot-typescript-preset-rass-tools
        '(typescript-language-server eslint)) ; default
```

Available symbolic tools:

- `astro-ls`
- `biome`
- `eslint`
- `oxfmt`
- `oxlint`
- `svelte-language-server`
- `tailwindcss-language-server`
- `typescript-language-server`
- `vscode-css-language-server`
- `vue-language-server`

You can also pass literal command vectors:

```elisp
(setopt eglot-typescript-preset-rass-tools
        '(typescript-language-server
          biome
          ["custom-lsp" "--stdio"]))
```

### `eglot-typescript-preset-css-rass-tools`

Same as above, but for CSS files:

```elisp
(setopt eglot-typescript-preset-css-rass-tools
        '(vscode-css-language-server tailwindcss-language-server)) ; default
```

### `eglot-typescript-preset-astro-rass-tools`

Same as above, but for Astro files:

```elisp
(setopt eglot-typescript-preset-astro-rass-tools
        '(astro-ls eslint tailwindcss-language-server)) ; default
```

### `eglot-typescript-preset-vue-rass-tools`

Same as above, but for Vue files:

```elisp
(setopt eglot-typescript-preset-vue-rass-tools
        '(vue-language-server typescript-language-server
          tailwindcss-language-server)) ; default
```

### `eglot-typescript-preset-svelte-rass-tools`

Same as above, but for Svelte files:

```elisp
(setopt eglot-typescript-preset-svelte-rass-tools
        '(svelte-language-server typescript-language-server
          tailwindcss-language-server)) ; default
```

### `eglot-typescript-preset-rass-command`

Bypass the generated preset entirely with an exact `rass` command vector:

```elisp
(setopt eglot-typescript-preset-rass-command ["rass" "tslint"])
```

### `eglot-typescript-preset-css-rass-command`

Same as above, but for CSS files:

```elisp
(setopt eglot-typescript-preset-css-rass-command ["rass" "csstail"])
```

### `eglot-typescript-preset-astro-rass-command`

Same as above, but for Astro files:

```elisp
(setopt eglot-typescript-preset-astro-rass-command ["rass" "tslint"])
```

### `eglot-typescript-preset-vue-rass-command`

Same as above, but for Vue files:

```elisp
(setopt eglot-typescript-preset-vue-rass-command ["rass" "vuetail"])
```

### `eglot-typescript-preset-svelte-rass-command`

Same as above, but for Svelte files:

```elisp
(setopt eglot-typescript-preset-svelte-rass-command ["rass" "sveltetail"])
```

### `eglot-typescript-preset-rass-generated-directory`

Directory where generated `rass` presets are written:

```elisp
(setopt eglot-typescript-preset-rass-generated-directory
        (expand-file-name "eglot-typescript-preset/" user-emacs-directory)) ; default
```

### `eglot-typescript-preset-tsdk`

Fallback path to the TypeScript SDK `lib` directory, used by the Astro, Vue, and
Svelte language servers. The package resolves the SDK in this order:

1. Project-local `node_modules/typescript/lib` (if it exists)
2. This variable (when non-nil)
3. Global `npm root -g`

In most cases you can leave this nil and let project-local resolution handle it.
Set it as a fallback for projects that don't install TypeScript locally:

```elisp
(setopt eglot-typescript-preset-tsdk "/path/to/node_modules/typescript/lib")
```

### `eglot-typescript-preset-js-project-markers`

Files that indicate a JavaScript or TypeScript project root:

```elisp
(setopt eglot-typescript-preset-js-project-markers
        '("package.json" "tsconfig.json" "jsconfig.json")) ; default
```

### `eglot-typescript-preset-js-modes`

Major modes for JavaScript and TypeScript files:

```elisp
(setopt eglot-typescript-preset-js-modes
        '(jtsx-jsx-mode jtsx-tsx-mode jtsx-typescript-mode
          js-mode js-ts-mode typescript-ts-mode tsx-ts-mode)) ; default
```

### `eglot-typescript-preset-language-id-overrides`

Alist mapping major modes to LSP language ID strings. During setup, the
`eglot-language-id` property is set on each mode symbol so that Eglot sends the
correct `languageId` to language servers. This is needed because some modes
(like the `jtsx-*` family) have names that don't match standard LSP language
IDs, causing servers like `vscode-eslint-language-server` to reject files:

```elisp
(setopt eglot-typescript-preset-language-id-overrides
        '((js-mode . "javascript")
          (js-ts-mode . "javascript")
          (jtsx-jsx-mode . "javascriptreact")
          (jtsx-tsx-mode . "typescriptreact")
          (jtsx-typescript-mode . "typescript")
          (tsx-ts-mode . "typescriptreact"))) ; default
```

### `eglot-typescript-preset-css-modes`

Major modes for CSS files:

```elisp
(setopt eglot-typescript-preset-css-modes '(css-mode css-ts-mode)) ; default
```

### `eglot-typescript-preset-astro-modes`

Major modes for Astro files:

```elisp
(setopt eglot-typescript-preset-astro-modes '(astro-ts-mode)) ; default
```

### `eglot-typescript-preset-vue-modes`

Major modes for Vue files:

```elisp
(setopt eglot-typescript-preset-vue-modes '(vue-mode vue-ts-mode)) ; default
```

### `eglot-typescript-preset-svelte-modes`

Major modes for Svelte files:

```elisp
(setopt eglot-typescript-preset-svelte-modes
        '(svelte-mode svelte-ts-mode)) ; default
```

### `eglot-typescript-preset-rass-max-contextual-presets`

Contextual `rass` presets are the ones that embed project-local state, such as a
TypeScript SDK path or a project-local `node_modules` executable path. Older
contextual presets are pruned automatically:

```elisp
(setopt eglot-typescript-preset-rass-max-contextual-presets 50) ; default
```

### Per-project Configuration

Some projects may need different settings than your global defaults. There are
two approaches, depending on whether you want the settings stored in the project
itself.

#### Using `.dir-locals.el` (project-local file)

Create a `.dir-locals.el` file in the project root. The following variables are
recognized as safe with appropriate values, so Emacs will apply them without
prompting:

```elisp
;;; .dir-locals.el
((typescript-ts-mode
  . ((eglot-typescript-preset-lsp-server . rass)
     (eglot-typescript-preset-rass-tools . (typescript-language-server biome)))))
```

- `eglot-typescript-preset-lsp-server` accepts `typescript-language-server`,
  `deno`, or `rass`.
- `eglot-typescript-preset-astro-lsp-server` accepts `astro-ls`, `rass`, or
  `nil`.
- `eglot-typescript-preset-css-lsp-server` accepts `vscode-css-language-server`,
  `rass`, or `nil`.
- `eglot-typescript-preset-vue-lsp-server` accepts `vue-language-server`,
  `rass`, or `nil`.
- `eglot-typescript-preset-svelte-lsp-server` accepts `svelte-language-server`,
  `rass`, or `nil`.
- `eglot-typescript-preset-rass-tools`,
  `eglot-typescript-preset-astro-rass-tools`,
  `eglot-typescript-preset-css-rass-tools`,
  `eglot-typescript-preset-vue-rass-tools`, and
  `eglot-typescript-preset-svelte-rass-tools` accept lists of known tool symbols
  (`astro-ls`, `biome`, `eslint`, `oxfmt`, `oxlint`, `svelte-language-server`,
  `tailwindcss-language-server`, `typescript-language-server`,
  `vscode-css-language-server`, `vue-language-server`).
- `eglot-typescript-preset-js-project-markers` accepts lists of filename
  strings.
- `eglot-typescript-preset-language-id-overrides` accepts alists of (symbol .
  string) entries.

#### Using `dir-locals-set-directory-class` (init file, no project changes)

If you prefer not to add Emacs-specific files to the project, configure
per-directory settings from your init file instead:

```elisp
(dir-locals-set-class-variables
 'my-project-x
 '((typescript-ts-mode
    . ((eglot-typescript-preset-lsp-server . rass)
       (eglot-typescript-preset-rass-tools
        . (typescript-language-server biome))))))

(dir-locals-set-directory-class
 (expand-file-name "~/devel/project-x") 'my-project-x)
```

This uses the built-in Emacs directory-class mechanism. The settings take effect
whenever you visit files under that directory, without any files added to the
project.

## Troubleshooting

- Eglot publishes diagnostics through Flymake. If you are using Flycheck, you
  will need separate bridge or integration configuration in your Emacs setup.
- If `typescript-language-server` or other tools are installed only in a
  project-local `node_modules`, the package will prefer those executables
  automatically.
- If you use the `rass` backend, the package generates a preset under
  `eglot-typescript-preset-rass-generated-directory` and updates it as needed.
  Context-free presets are reused across buffers, while project-local
  `node_modules` and Astro/Vue/Svelte TSDK cases keep separate generated files.
- The CSS `rass` backend combines `vscode-css-language-server` with
  `tailwindcss-language-server` by default. If you do not use Tailwind CSS, set
  `eglot-typescript-preset-css-lsp-server` to `vscode-css-language-server` for
  standalone CSS support, or to `nil` to disable.

## Notes

- For standard projects, the package prefers executables from a project-root
  `node_modules/.bin` and otherwise falls back to PATH. The same resolution is
  used for supported tools in generated `rass` presets.
- The Astro, Vue, and Svelte language servers require a TypeScript SDK path. The
  package first checks for a project-local `node_modules/typescript/lib`, then
  falls back to `eglot-typescript-preset-tsdk`, then `npm root -g`.
- When using the `rass` backend, the package enables streaming diagnostics so
  that LSP servers using pull diagnostics (like `vscode-eslint-language-server`)
  work correctly with Eglot's push-based diagnostics model.
