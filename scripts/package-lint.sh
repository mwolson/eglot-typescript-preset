#!/bin/bash

set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"/include.sh

TARGET_FILE="${1:-eglot-typescript-preset.el}"

emacs_script "$(get_topdir)"/scripts/package-lint-local.el \
    "$(get_topdir)" \
    "${TARGET_FILE}"
