# Ceres Binaries

Builds and packages **Ceres** whole - the virtual machine, the C compiler, the C library and the shell - into
installers for Windows, Linux and macOS. The ready-made Windows packages are in [prebuilt/](prebuilt).

| Part | Repository | What goes in the package |
| --- | --- | --- |
| The virtual machine, assembler, linker and debugger | [CeresASM](https://github.com/NightTerror1721/Ceres-VM) | `ceres` (and `SDL3.dll` on Windows) |
| The C compiler | [Ceres-C](https://github.com/NightTerror1721/Ceres-C) | `ceresc` |
| The C library and the shell | [Ceres STDLIB](https://github.com/NightTerror1721/Ceres-Standard-Library) | `stdlib/`, `shell/shell.cres`, `shell/shell-small.cres` |

They are git submodules under `sources/`, pinned to the commits a package is built from.

## The installation

Ceres lives in one directory, and the `CERES_PATH` environment variable names it:

```
<CERES_PATH>/
  ceres, ceresc            the tools (ceres.exe, ceresc.exe and SDL3.dll on Windows)
  shell/shell.cres         the shell: what `ceres run` starts when it is given no program
  shell/shell-small.cres   the same shell, small: for the machines shell.cres does not fit (micro)
  stdlib/include/          the C library's headers
  stdlib/lib/              libceres.car, libceres.decls.casm and the optional modules (libceres_irq.cobj, ...)
  licenses/  README.txt  LICENSE.txt  VERSION  and the uninstaller
```

- `ceres run` looks for the shell in `CERES_PATH/shell/`, and then beside itself: `shell.cres`, or `shell-small.cres`
  on a machine the first does not fit.
- `ceresc prog.c --stdlib --run` compiles against `CERES_PATH/stdlib` (or the `stdlib/` beside `ceresc`) and links
  `libceres.car`. `ceresc` finds `ceres` in `CERES_PATH`, then beside itself, then on `PATH`.

So an unpacked package works where it is, without installing it or setting anything. The installers copy it into
place, set `CERES_PATH` and put the tools on `PATH`.

## Installing a package

**Windows** (`prebuilt/windows-x64/`, or `dist/` after a build): run `ceres-<version>-windows-x64-setup.exe`. It
installs for the current user, without administrator rights, into `%LOCALAPPDATA%\Programs\Ceres` (it asks, and
takes another directory), sets `CERES_PATH` and adds the directory to the user's `PATH`. Or unpack
`ceres-<version>-windows-x64.zip` and run `install.cmd` in it, which does the same:

```bat
install.cmd                                   :: asks where
install.cmd -Destination D:\Tools\Ceres -Yes  :: or says so
install.cmd -NoEnvironment                    :: copies it, and leaves CERES_PATH and PATH alone
```

`uninstall.cmd`, in the installed directory, removes it again, with its `PATH` entry and `CERES_PATH`.

**Linux and macOS**: `sh ceres-<version>-<platform>-installer.sh`, or unpack the `.tar.gz` and run `./install.sh`
in it:

```sh
./install.sh                       # ~/.local/share/ceres, with ceres and ceresc linked into ~/.local/bin
./install.sh --prefix /opt/ceres   # elsewhere (as root the defaults are /opt/ceres and /usr/local/bin)
./install.sh --no-env --yes        # without touching the shell's startup files, and without asking
```

It sets `CERES_PATH` in `~/.profile` (and in `~/.bash_profile`, `~/.zprofile` and `~/.zshrc` when they are there),
in a block of its own. `uninstall.sh`, in the installed directory, removes it again.

Then, in a new terminal:

```sh
ceres run                             # the shell, in the current directory
ceresc hello.c --stdlib -O2 --run     # a C program against the C library
```

## Building the packages

```sh
git clone --recursive https://github.com/NightTerror1721/Ceres-Binaries.git
```

(or `git submodule update --init` in a clone; the build scripts do it when the sources are missing).

**Windows** - CMake 3.28+, Ninja, git and GCC with C++23 on `PATH` (MSYS2's `mingw64`):

```bat
powershell -ExecutionPolicy Bypass -File build.ps1              :: dist\ceres-<version>-windows-x64.zip and -setup.exe
powershell -ExecutionPolicy Bypass -File build.ps1 -Prebuilt    :: ... and copy them into prebuilt\windows-x64
```

The executables are linked statically (they need no MinGW DLL), `ceres` with the SDL3 window, which CeresASM's CMake
fetches and builds (`SDL3.dll` goes beside it). The setup program is Inno Setup's when `ISCC.exe` is installed
([package/windows/ceres.iss](package/windows/ceres.iss)), with an entry in Settings > Apps to uninstall it;
otherwise it is made with IExpress, which every Windows has, and runs `install.ps1`.

**Linux and macOS** - CMake 3.28+, GCC 13+ or Clang 17+, git, make or Ninja, and for the window the development
files SDL3 needs (on Linux: X11 or Wayland, ALSA or PulseAudio):

```sh
./build.sh                  # dist/ceres-<version>-<platform>.tar.gz and -installer.sh
./build.sh --prebuilt       # ... and copy them into prebuilt/<platform>
./build.sh --no-sdl         # a ceres without the window
```

On Linux the C++ runtime is linked into the executables, and SDL3 is linked statically on both.

Both scripts build each repository, put the installation together in `build/<platform>/stage/Ceres`, and run a
smoke test from there before packaging it: [package/smoke/hello.c](package/smoke/hello.c) compiled with `--stdlib`
and run, with no `CERES_PATH`, and the shell started and ended. Other checkouts can stand in for the submodules:
`build.ps1 -CeresAsm <dir> -CeresC <dir> -Stdlib <dir>`, `build.sh --ceres-asm <dir> --ceres-c <dir> --stdlib <dir>`.

The version of a package is [VERSION](VERSION).

## Making a release

1. Move the submodules to the commits to ship: `git -C sources/CeresASM checkout <commit>` (and the others), or
   `git submodule update --remote` for the newest.
2. Raise `VERSION` if it is a new one.
3. `build.ps1 -Prebuilt` on Windows (and `build.sh --prebuilt` on Linux and macOS), and commit the submodules, the
   version and `prebuilt/` together.

## Layout of this repository

| Path | What it is |
| --- | --- |
| `build.ps1`, `build.sh` | The builds: Windows, and Linux and macOS. |
| `sources/` | The three repositories, as submodules. |
| `package/README.txt` | The README of a package. |
| `package/windows/` | `install.ps1`/`install.cmd`, `uninstall.ps1`/`uninstall.cmd`, and `ceres.iss` for Inno Setup. |
| `package/unix/` | `install.sh`, `uninstall.sh`, and the header of the self-extracting installer. |
| `package/smoke/` | The smoke test. |
| `prebuilt/<platform>/` | The packages of the last release. |
| `build/`, `dist/` | What a build makes (not kept). |
