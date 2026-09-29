#!/bin/sh
# Installs Ceres: copies this package into a directory, links ceres and ceresc into a directory on PATH, and sets
# CERES_PATH to the installation in the shell's startup files.
#
#   ./install.sh [--prefix <dir>] [--bindir <dir>] [--no-env] [--yes]
#
#   --prefix <dir>   where Ceres goes: ~/.local/share/ceres, or /opt/ceres when run as root
#   --bindir <dir>   where the links to ceres and ceresc go: ~/.local/bin, or /usr/local/bin as root
#   --no-env         leave the startup files alone (the tools still find everything from their own directory)
#   --yes            do not ask
#
# A directory that holds an earlier installation is replaced whole; one that holds anything else is refused. The
# startup files get a block between "# >>> ceres >>>" and "# <<< ceres <<<" (replaced, not added again, on a later
# install): ~/.profile, and ~/.bash_profile, ~/.zprofile or ~/.zshrc when they exist (on macOS ~/.zprofile is
# always written, zsh being its shell). As root, /etc/profile.d/ceres.sh instead. uninstall.sh, in the installed
# directory, takes all of it away again.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
if [ "$(id -u)" = 0 ]; then
    prefix=/opt/ceres
    bindir=/usr/local/bin
else
    prefix="$HOME/.local/share/ceres"
    bindir="$HOME/.local/bin"
fi
env=1
yes=0
while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) prefix=$2; shift ;;
        --bindir) bindir=$2; shift ;;
        --no-env) env=0 ;;
        --yes|-y) yes=1 ;;
        -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "install.sh: unknown option '$1' (--help lists them)" >&2; exit 2 ;;
    esac
    shift
done

fail() { echo "Ceres was not installed: $*" >&2; exit 1; }
for needed in ceres ceresc shell/shell.cres shell/shell-small.cres stdlib/include; do
    [ -e "$here/$needed" ] || fail "this is not a whole Ceres package: $needed is missing from $here"
done
version=$(head -n 1 "$here/VERSION" 2>/dev/null || echo "")
mkdir -p "$(dirname "$prefix")"
case "$prefix" in /*) ;; *) prefix="$(cd "$(dirname "$prefix")" && pwd)/$(basename "$prefix")" ;; esac

if [ "$yes" = 0 ]; then
    echo "Ceres $version will be installed into $prefix, with ceres and ceresc linked into $bindir."
    if [ "$env" = 1 ]; then echo "CERES_PATH will name it in your shell's startup files."; fi
    printf 'Install? [Y/n] '
    read -r answer || answer=n
    case "$answer" in [nN]*) echo "Nothing was installed."; exit 1 ;; esac
fi

# ---- the files ----
if [ "$prefix" != "$here" ]; then
    if [ -e "$prefix" ] && [ ! -d "$prefix" ]; then fail "$prefix is a file"; fi
    if [ -d "$prefix" ] && [ -n "$(ls -A "$prefix")" ]; then
        [ -f "$prefix/ceres" ] || fail "$prefix is not empty and holds no Ceres installation: choose another --prefix"
        for item in ceres ceresc shell stdlib licenses README.txt LICENSE.txt VERSION install.sh uninstall.sh .install; do
            rm -rf "${prefix:?}/$item"
        done
    fi
    mkdir -p "$prefix"
    cp -R "$here/." "$prefix/"
    echo "Installed Ceres $version into $prefix"
fi

# ---- the links ----
mkdir -p "$bindir"
for tool in ceres ceresc; do
    if [ -e "$bindir/$tool" ] && [ ! -L "$bindir/$tool" ]; then
        echo "  $bindir/$tool is there already and is not a link: left alone" >&2
    else
        ln -sf "$prefix/$tool" "$bindir/$tool"
    fi
done
echo "Linked ceres and ceresc into $bindir"

# ---- the environment ----
files=""
if [ "$env" = 1 ]; then
    block="# >>> ceres >>>
export CERES_PATH=\"$prefix\"
case \":\$PATH:\" in *\":$bindir:\"*) ;; *) export PATH=\"$bindir:\$PATH\" ;; esac
# <<< ceres <<<"
    write_block() {
        file=$1
        if [ -f "$file" ]; then
            awk '/^# >>> ceres >>>$/ { skip = 1 } !skip { print } /^# <<< ceres <<<$/ { skip = 0 }' "$file" > "$file.ceres-tmp"
            cat "$file.ceres-tmp" > "$file"
            rm -f "$file.ceres-tmp"
        fi
        printf '\n%s\n' "$block" >> "$file"
        files="$files $file"
    }
    if [ "$(id -u)" = 0 ] && [ -d /etc/profile.d ]; then
        printf '%s\n' "$block" > /etc/profile.d/ceres.sh
        files=/etc/profile.d/ceres.sh
    else
        write_block "$HOME/.profile"
        if [ -f "$HOME/.bash_profile" ]; then write_block "$HOME/.bash_profile"; fi
        if [ -f "$HOME/.zprofile" ] || [ "$(uname -s)" = Darwin ]; then write_block "$HOME/.zprofile"; fi
        if [ -f "$HOME/.zshrc" ]; then write_block "$HOME/.zshrc"; fi
    fi
    echo "CERES_PATH is $prefix, in:$files"
    echo "Open a new terminal (or: . ~/.profile), then: ceres run    or    ceresc prog.c --stdlib --run"
fi

# What uninstall.sh has to undo.
{
    echo "bindir=$bindir"
    echo "files=$files"
} > "$prefix/.install"
