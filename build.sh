#!/usr/bin/env bash
# Builds Ceres for Linux or macOS - the virtual machine (ceres), the C compiler (ceresc), the C library and the
# shell - and packages it: a .tar.gz that installs itself, and a self-extracting installer.
#
#   ./build.sh                     everything, from the sources under sources/ (git submodules, fetched if missing)
#   ./build.sh --prebuilt          ... and copy the packages into prebuilt/<platform>
#   ./build.sh --ceres-asm DIR --ceres-c DIR --stdlib DIR      from other checkouts
#   ./build.sh --build-dir DIR     where to build (default build/<platform>; a native file system is much faster
#                                  than a Windows drive under WSL)
#   ./build.sh --no-sdl            a ceres without the window
#   ./build.sh --clean             build everything again from nothing
#
# Each repository is built in <build-dir>: CeresASM's ceres (Release, link-time optimization, SDL3 built from source
# and linked statically), Ceres-C's ceresc (Release, link-time optimization), and the STDLIB at -O2 with those two,
# whose build leaves stdlib/ and shell/shell.cres laid out as they go in the installation. They are put together in
# <build-dir>/stage/Ceres, the directory Ceres is installed as (CERES_PATH):
#
#   ceres  ceresc  shell/shell.cres  stdlib/include  stdlib/lib  licenses/  README.txt  LICENSE.txt  VERSION
#   install.sh  uninstall.sh
#
# A smoke test runs from there (a C program compiled with --stdlib and run, with no CERES_PATH, and the shell
# started and ended), and then, in dist/:
#
#   ceres-<version>-<platform>.tar.gz          the directory; ./install.sh in it installs it
#   ceres-<version>-<platform>-installer.sh    the same, as one script: sh ceres-...-installer.sh [install.sh's options]
#
# Needs CMake 3.28+, a C and C++23 compiler (GCC 13+ or Clang 17+), git, and make or Ninja. With the window, SDL3's
# build wants the development files of the system's video and audio (X11 or Wayland, ALSA or PulseAudio on Linux).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
CERES_ASM="$ROOT/sources/CeresASM"
CERES_C="$ROOT/sources/Ceres-C"
STDLIB="$ROOT/sources/Ceres-STDLIB"
BUILD_DIR=""
OUT_DIR="$ROOT/dist"
SDL=ON
PREBUILT=0
CLEAN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --ceres-asm) CERES_ASM=$2; shift ;;
        --ceres-c) CERES_C=$2; shift ;;
        --stdlib) STDLIB=$2; shift ;;
        --build-dir) BUILD_DIR=$2; shift ;;
        --out-dir) OUT_DIR=$2; shift ;;
        --no-sdl) SDL=OFF ;;
        --prebuilt) PREBUILT=1 ;;
        --clean) CLEAN=1 ;;
        -h|--help) sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "build.sh: unknown option '$1' (--help lists them)" >&2; exit 2 ;;
    esac
    shift
done

step() { printf '\033[36m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[31mbuild.sh: %s\033[0m\n' "$*" >&2; exit 1; }

case "$(uname -s)" in
    Linux) OS=linux ;;
    Darwin) OS=macos ;;
    *) fail "this is $(uname -s): build.sh is for Linux and macOS (build.ps1 is for Windows)" ;;
esac
case "$(uname -m)" in
    x86_64|amd64) ARCH=x64 ;;
    aarch64|arm64) ARCH=arm64 ;;
    *) ARCH=$(uname -m) ;;
esac
PLATFORM="$OS-$ARCH"
VERSION=$(head -n 1 "$ROOT/VERSION" | tr -d '[:space:]')
NAME="ceres-$VERSION-$PLATFORM"
BUILD_DIR=${BUILD_DIR:-"$ROOT/build/$PLATFORM"}
PACKAGE="$ROOT/package"
export CERES_HEADLESS=1          # nothing the build runs opens a window

# ---- the sources and the tools ----

for tool in cmake git; do
    command -v "$tool" >/dev/null || fail "$tool is not on PATH"
done
if ! [ -f "$CERES_ASM/Ceres/CMakeLists.txt" ] || ! [ -f "$CERES_C/CMakeLists.txt" ] || ! [ -f "$STDLIB/CMakeLists.txt" ]; then
    step "fetching the sources (git submodule update --init)"
    git -C "$ROOT" submodule update --init
fi
[ -f "$CERES_ASM/Ceres/CMakeLists.txt" ] || fail "CeresASM is not in $CERES_ASM"
[ -f "$CERES_C/CMakeLists.txt" ] || fail "Ceres-C is not in $CERES_C"
[ -f "$STDLIB/CMakeLists.txt" ] || fail "the Ceres STDLIB is not in $STDLIB"

if command -v ninja >/dev/null; then
    GENERATOR=(-G "Ninja Multi-Config")
else
    GENERATOR=(-G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release)
fi
JOBS=$( (nproc || sysctl -n hw.ncpu || echo 4) 2>/dev/null | head -n 1)
# The C++ runtime inside the executables on Linux, so they do not depend on the system's libstdc++ version. macOS's
# libc++ is part of the system.
LINK=()
if [ "$OS" = linux ]; then
    LINK=(-DCMAKE_EXE_LINKER_FLAGS="-static-libstdc++ -static-libgcc")
fi

[ "$CLEAN" = 1 ] && rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUT_DIR"

# The newest file called $2 under $1, outside CMake's own directories and the fetched dependencies.
find_one() {
    local found
    found=$(find "$1" -type f -name "$2" -not -path '*/_deps/*' -not -path '*/CMakeFiles/*' -print 2>/dev/null | head -n 1)
    [ -n "$found" ] || fail "the build left no $2 in $1"
    printf '%s\n' "$found"
}

# ---- ceres ----

step "ceres (CeresASM)"
cmake -S "$CERES_ASM/Ceres" -B "$BUILD_DIR/ceres" "${GENERATOR[@]}" "${LINK[@]}" \
    -DCERES_ENABLE_SDL=$SDL -DCERES_ENABLE_IPO=ON -DCERES_BUILD_TESTS=OFF -DSDL_SHARED=OFF -DSDL_STATIC=ON
cmake --build "$BUILD_DIR/ceres" --config Release --target ceres --parallel "$JOBS"
CERES=$(find_one "$BUILD_DIR/ceres" ceres)

# ---- ceresc ----

step "ceresc (Ceres-C)"
cmake -S "$CERES_C" -B "$BUILD_DIR/ceresc" "${GENERATOR[@]}" "${LINK[@]}" -DCERESC_ENABLE_IPO=ON -DCERESC_BUILD_TESTS=OFF
cmake --build "$BUILD_DIR/ceresc" --config Release --target ceresc --parallel "$JOBS"
CERESC=$(find_one "$BUILD_DIR/ceresc" ceresc)

# ---- the C library and the shell ----

step "the C library and the shell (Ceres STDLIB, -O2)"
if command -v ninja >/dev/null; then LIB_GENERATOR=(-G Ninja); else LIB_GENERATOR=(-G "Unix Makefiles"); fi
cmake -S "$STDLIB" -B "$BUILD_DIR/stdlib" "${LIB_GENERATOR[@]}" -DCERES="$CERES" -DCERESC="$CERESC" -DCERES_OPT_LEVEL=2
cmake --build "$BUILD_DIR/stdlib" --parallel "$JOBS"

# ---- the installation directory ----

step "putting $NAME together"
STAGE="$BUILD_DIR/stage/Ceres"
rm -rf "$BUILD_DIR/stage"
mkdir -p "$STAGE/shell" "$STAGE/licenses"
cp "$CERES" "$CERESC" "$STAGE/"
cp "$BUILD_DIR/stdlib/shell/shell.cres" "$STAGE/shell/"
cp -R "$BUILD_DIR/stdlib/stdlib" "$STAGE/"
cp "$PACKAGE/unix/install.sh" "$PACKAGE/unix/uninstall.sh" "$STAGE/"
chmod +x "$STAGE/ceres" "$STAGE/ceresc" "$STAGE/install.sh" "$STAGE/uninstall.sh"
cp "$ROOT/LICENSE" "$STAGE/LICENSE.txt"
cp "$CERES_ASM/LICENSE" "$STAGE/licenses/CeresASM.txt"
cp "$CERES_C/LICENSE" "$STAGE/licenses/Ceres-C.txt"
if [ "$SDL" = ON ] && [ -f "$BUILD_DIR/ceres/_deps/sdl3-src/LICENSE.txt" ]; then
    cp "$BUILD_DIR/ceres/_deps/sdl3-src/LICENSE.txt" "$STAGE/licenses/SDL3.txt"
fi
printf '%s\n' "$VERSION" > "$STAGE/VERSION"
SOURCES=""
for repo in "CeresASM:$CERES_ASM" "Ceres-C:$CERES_C" "Ceres-STDLIB:$STDLIB"; do
    commit=$(git -C "${repo#*:}" rev-parse --short HEAD 2>/dev/null || echo "(not a git checkout)")
    SOURCES="$SOURCES  ${repo%%:*} $commit"$'\n'
done
readme=$(tr -d '\r' < "$PACKAGE/README.txt")
readme=${readme//@VERSION@/$VERSION}
readme=${readme//@PLATFORM@/$PLATFORM}
readme=${readme//@SOURCES@/${SOURCES%$'\n'}}
printf '%s\n' "$readme" > "$STAGE/README.txt"

# ---- the smoke test ----

step "smoke test"
SMOKE="$BUILD_DIR/smoke"
rm -rf "$SMOKE"
mkdir -p "$SMOKE"
cp "$PACKAGE/smoke/hello.c" "$PACKAGE/smoke/shell.type" "$SMOKE/"
(
    cd "$SMOKE"
    unset CERES_PATH             # the tools must find what they need beside themselves
    "$STAGE/ceresc" hello.c --stdlib -O2 --run --run-arg --transcript --run-arg hello.txt -- smoke >/dev/null \
        || fail "the smoke test program ended with $?"
    cmp -s hello.txt "$PACKAGE/smoke/hello.expected" || fail "the smoke test printed '$(cat hello.txt)'"
    status=0
    "$STAGE/ceres" run --headless --type shell.type --transcript shell.txt >/dev/null || status=$?
    [ "$status" = 7 ] || fail "the shell ended with $status, not 7"
    grep -q "Ceres shell" shell.txt || fail "the shell did not start"
)
echo "    ok: a program compiled with --stdlib and run, and the shell"

# ---- the packages ----

step "packages"
TARBALL="$OUT_DIR/$NAME.tar.gz"
INSTALLER="$OUT_DIR/$NAME-installer.sh"
tar -czf "$TARBALL" -C "$BUILD_DIR/stage" Ceres
{
    sed -e "s/@VERSION@/$VERSION/g" -e "s/@PLATFORM@/$PLATFORM/g" "$PACKAGE/unix/installer-header.sh"
    cat "$TARBALL"
} > "$INSTALLER"
chmod +x "$INSTALLER"
echo "    $TARBALL"
echo "    $INSTALLER"

if [ "$PREBUILT" = 1 ]; then
    KEEP="$ROOT/prebuilt/$PLATFORM"
    mkdir -p "$KEEP"
    rm -f "$KEEP"/ceres-*
    cp "$TARBALL" "$INSTALLER" "$KEEP/"
    echo "    copied into $KEEP"
fi
step "done: Ceres $VERSION for $PLATFORM"
