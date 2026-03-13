#!/bin/bash

function qpopd() {
    popd > /dev/null
}

function qpushd() {
    pushd "$1" > /dev/null
}

export _TOPDIR=

function get_topdir() {
    if [[ -n "${_TOPDIR}" ]]; then
        echo "${_TOPDIR}"
    else
        qpushd "$(dirname "${BASH_SOURCE[0]}")/.."
        echo "$PWD"
        qpopd
    fi
}

export _TOPDIR="$(get_topdir)"

function get_parent_tmpdir() {
    local topdir
    topdir="$(get_topdir)"
    echo "$(dirname "$topdir")/tmp/$(basename "$topdir")"
}

function get_melpa_recipe_file() {
    echo "$(get_topdir)/eglot-typescript-preset.recipe"
}

function emacs_script() {
    emacs --script "$@" 2>&1 | grep -v '^Loading '
}

function byte_compile() {
    if [[ -d "$2" ]]; then
        rm -f "$2"/*.elc
    elif [[ -f "$2" ]]; then
        rm -f "${2}c"
    else
        echo "Warning: unknown type for $2"
    fi

    emacs_script "$(get_topdir)"/scripts/byte-compile-local.el "$@"
}
