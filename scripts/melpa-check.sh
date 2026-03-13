#!/bin/bash

set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"/include.sh

"$(get_topdir)"/scripts/byte-compile.sh --check
"$(get_topdir)"/scripts/checkdoc.sh
"$(get_topdir)"/scripts/package-lint.sh
"$(get_topdir)"/scripts/melpa-build-install-check.sh
