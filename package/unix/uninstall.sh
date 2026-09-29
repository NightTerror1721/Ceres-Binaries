#!/bin/sh
# Removes the Ceres installation this script is part of: the links install.sh made to it, its block in the shell's
# startup files, and its directory.
#
#   ./uninstall.sh [--yes]
set -eu

prefix=$(cd "$(dirname "$0")" && pwd)
yes=0
case "${1:-}" in --yes|-y) yes=1 ;; esac
[ -f "$prefix/ceres" ] || { echo "$prefix is not a Ceres installation" >&2; exit 1; }
if [ "$yes" = 0 ]; then
    printf 'Remove Ceres from %s, with everything in that directory? [y/N] ' "$prefix"
    read -r answer || answer=n
    case "$answer" in [yY]*) ;; *) echo "Nothing was removed."; exit 1 ;; esac
fi

bindir=""
files=""
if [ -f "$prefix/.install" ]; then
    bindir=$(sed -n 's/^bindir=//p' "$prefix/.install")
    files=$(sed -n 's/^files=//p' "$prefix/.install")
fi
for tool in ceres ceresc; do
    link="$bindir/$tool"
    if [ -n "$bindir" ] && [ -L "$link" ] && [ "$(readlink "$link")" = "$prefix/$tool" ]; then
        rm -f "$link"
        echo "Removed $link"
    fi
done
for file in $files; do
    [ -f "$file" ] || continue
    if [ "$file" = /etc/profile.d/ceres.sh ]; then
        rm -f "$file"
    else
        awk '/^# >>> ceres >>>$/ { skip = 1 } !skip { print } /^# <<< ceres <<<$/ { skip = 0 }' "$file" > "$file.ceres-tmp"
        cat "$file.ceres-tmp" > "$file"
        rm -f "$file.ceres-tmp"
    fi
    echo "Removed CERES_PATH from $file"
done
cd /
rm -rf "$prefix"
echo "Removed $prefix"
