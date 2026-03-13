# eglot-typescript-preset

Configures TypeScript, JavaScript, and Astro LSP support for Emacs using
[Eglot](https://github.com/joaotavora/eglot), with optional linter and formatter
integration via [rassumfrassum](https://github.com/joaotavora/rassumfrassum).

This package configures Eglot to work with TypeScript and JavaScript files using
[typescript-language-server](https://github.com/typescript-language-server/typescript-language-server)
or [rassumfrassum](https://github.com/joaotavora/rassumfrassum) as the language
server frontend. It supports combining multiple tools -- ESLint, Biome, oxlint,
and oxfmt -- through generated `rass` presets, and includes Astro support via
[@astrojs/language-server](https://github.com/withastro/language-tools).

## Prerequisites

- Emacs 30.2 or later
- One of the following for TypeScript/JavaScript:
  - [typescript-language-server](https://github.com/typescript-language-server/typescript-language-server)
    -- the standard TypeScript LSP
  - [rassumfrassum](https://github.com/joaotavora/rassumfrassum) (>= v0.3.3) --
    optional stdio multiplexer for combining multiple tools
- Optional linters and formatters (used with `rass` backend):
  - [biome](https://biomejs.dev/) -- linter and formatter
  - [eslint](https://eslint.org/) via `vscode-eslint-language-server`
  - [oxfmt](https://oxc.rs/docs/guide/usage/formatter.html) -- fast formatter
  - [oxlint](https://oxc.rs/docs/guide/usage/linter.html) -- fast linter
- Optional for Astro:
  - [@astrojs/language-server](https://github.com/withastro/language-tools)
    (provides the `astro-ls` command)

## Installation

Choose one of the following ways to install. After that, opening TypeScript,
JavaScript, or Astro files will automatically start the LSP server using Eglot.

### From MELPA (recommended)

```elisp
(use-package eglot-typescript-preset
  :ensure t
  :after eglot
  :config
  (eglot-typescript-preset-setup))
```

### Manual installation

Clone this repository and add to your Emacs configuration:

```bash
mkdir -p ~/devel
git clone https://github.com/mwolson/eglot-typescript-preset ~/devel/eglot-typescript-preset
```

```elisp
(add-to-list 'load-path (expand-file-name "~/devel/eglot-typescript-preset"))
(require 'eglot-typescript-preset)
(eglot-typescript-preset-setup)
```

## Usage

### Standard TypeScript/JavaScript Projects

For standard projects (those with `package.json`, `tsconfig.json`, or
`jsconfig.json`), the package automatically detects the project root and starts
Eglot with appropriate configuration.

### Astro Projects

When `eglot-typescript-preset-astro-lsp-server` is set (default: `astro-ls`),
the package also configures Eglot for `astro-ts-mode` buffers, including
automatic TypeScript SDK detection for the Astro language server.

## Configuration

### `eglot-typescript-preset-lsp-server`

Choose which language server to use for TypeScript/JavaScript:

```elisp
(setopt eglot-typescript-preset-lsp-server 'typescript-language-server) ; default
;; or
(setopt eglot-typescript-preset-lsp-server 'rass)
```

### `eglot-typescript-preset-astro-lsp-server`

Choose which language server to use for Astro:

```elisp
(setopt eglot-typescript-preset-astro-lsp-server 'astro-ls) ; default
;; or
(setopt eglot-typescript-preset-astro-lsp-server 'rass)
;; or
(setopt eglot-typescript-preset-astro-lsp-server nil) ; disable Astro support
```

### `eglot-typescript-preset-rass-tools`

When using the `rass` backend, this list controls the generated preset for
TypeScript/JavaScript files. Supported tools get local `node_modules` executable
resolution:

```elisp
(setopt eglot-typescript-preset-rass-tools
        '(typescript-language-server eslint)) ; default
```

Available symbolic tools: `typescript-language-server`, `eslint`, `biome`,
`oxlint`, `oxfmt`, `astro-ls`.

You can also pass literal command vectors:

```elisp
(setopt eglot-typescript-preset-rass-tools
        '(typescript-language-server
          biome
          ["custom-lsp" "--stdio"]))
```

### `eglot-typescript-preset-astro-rass-tools`

Same as above, but for Astro files:

```elisp
(setopt eglot-typescript-preset-astro-rass-tools
        '(astro-ls eslint)) ; default
```

### `eglot-typescript-preset-rass-command`

Bypass the generated preset entirely with an exact `rass` command vector:

```elisp
(setopt eglot-typescript-preset-rass-command ["rass" "tslint"])
```

### `eglot-typescript-preset-astro-rass-command`

Same as above, but for Astro files:

```elisp
(setopt eglot-typescript-preset-astro-rass-command ["rass" "tslint"])
```

### `eglot-typescript-preset-tsdk`

Path to the TypeScript SDK `lib` directory. When nil (default), the package
attempts to find it automatically via `npm root -g`:

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

### `eglot-typescript-preset-astro-modes`

Major modes for Astro files:

```elisp
(setopt eglot-typescript-preset-astro-modes '(astro-ts-mode)) ; default
```

### `eglot-typescript-preset-rass-max-contextual-presets`

Contextual `rass` presets are the ones that embed project-local state, such as a
TypeScript SDK path or a project-local `node_modules` executable path. Older
contextual presets are pruned automatically:

```elisp
(setopt eglot-typescript-preset-rass-max-contextual-presets 50) ; default
```

## Troubleshooting

- Eglot publishes diagnostics through Flymake. If you are using Flycheck, you
  will need separate bridge or integration configuration in your Emacs setup.
- If `typescript-language-server` or other tools are installed only in a
  project-local `node_modules`, the package will prefer those executables
  automatically.
- If you use the `rass` backend, the package generates a preset under your Emacs
  directory and updates it as needed. Context-free presets are reused across
  buffers, while project-local `node_modules` and Astro TSDK cases keep separate
  generated files.

## Notes

- For standard projects, the package prefers executables from a project-root
  `node_modules/.bin` and otherwise falls back to PATH. The same resolution is
  used for supported tools in generated `rass` presets.
- The Astro language server requires a TypeScript SDK path. The package tries to
  detect it via `npm root -g`, or you can set `eglot-typescript-preset-tsdk`
  explicitly.
