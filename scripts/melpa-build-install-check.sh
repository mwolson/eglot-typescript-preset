#!/bin/bash

set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"/include.sh

TOPDIR="$(get_topdir)"
MELPA_ROOT="${MELPA_ROOT:-$(dirname "$(dirname "${TOPDIR}")")/github/melpa}"
TEMP_ROOT="$(get_parent_tmpdir)-melpa-check"
RECIPE_FILE="$(get_melpa_recipe_file)"
SNAPSHOT_REPO="${TEMP_ROOT}/snapshot-repo"

for command in emacs git tar; do
    if ! command -v "${command}" >/dev/null 2>&1; then
        echo "Error: ${command} is required" >&2
        exit 1
    fi
done

if [[ ! -f "${MELPA_ROOT}/package-build/package-build.el" ]]; then
    echo "Error: package-build not found under ${MELPA_ROOT}" >&2
    echo "Set MELPA_ROOT to your melpa checkout." >&2
    exit 1
fi

if [[ ! -f "${RECIPE_FILE}" ]]; then
    echo "Error: MELPA recipe file not found at ${RECIPE_FILE}" >&2
    exit 1
fi

rm -rf "${TEMP_ROOT}"
mkdir -p "${SNAPSHOT_REPO}"

tar -C "${TOPDIR}" \
    --exclude='./.git' \
    --exclude='./node_modules' \
    --exclude='./tmp' \
    -cf - . | tar -C "${SNAPSHOT_REPO}" -xf -

git -C "${SNAPSHOT_REPO}" init -q
git -C "${SNAPSHOT_REPO}" config user.email "melpa-check@example.invalid"
git -C "${SNAPSHOT_REPO}" config user.name "melpa-check"
git -C "${SNAPSHOT_REPO}" add -A
git -C "${SNAPSHOT_REPO}" commit -qm "snapshot"

emacs_script "${TOPDIR}"/scripts/melpa-build-install-check.el \
    "${TOPDIR}" \
    "${MELPA_ROOT}" \
    "${TEMP_ROOT}" \
    "${RECIPE_FILE}" \
    "${SNAPSHOT_REPO}"
