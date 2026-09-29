#!/bin/sh
# Ceres @VERSION@ for @PLATFORM@: a self-extracting installer. It unpacks the package that follows this script into a
# temporary directory and runs its install.sh with the same arguments:
#
#   sh ceres-@VERSION@-@PLATFORM@-installer.sh [--prefix <dir>] [--bindir <dir>] [--no-env] [--yes]
#
# (sh ... --help shows install.sh's own help.)
set -e
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ceres-install.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM
line=$(awk '/^__CERES_PACKAGE_FOLLOWS__$/ { print NR + 1; exit }' "$0")
tail -n +"$line" "$0" | tar -xzf - -C "$tmp"
status=0
"$tmp/Ceres/install.sh" "$@" || status=$?
exit $status
__CERES_PACKAGE_FOLLOWS__
