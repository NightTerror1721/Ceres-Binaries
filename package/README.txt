Ceres @VERSION@ (@PLATFORM@)
============================

Ceres is a virtual machine with its own assembler, a C compiler for it and a C library. This directory is a whole
installation of it:

  ceres           the virtual machine, assembler, linker and debugger (ceres run, ceres asm, ceres link...)
  ceresc          the C compiler
  shell/          the Ceres shell, shell.cres: what `ceres run` starts when it is given no program
  stdlib/         the C library: include/ (its headers) and lib/ (libceres.car, and the optional modules)
  licenses/       the licenses of what is inside

The tools find everything else through the directory Ceres is installed in: the one the CERES_PATH environment
variable names or, when it is not set, the one they are in themselves. The installer sets CERES_PATH and puts this
directory on PATH.

  ceres run                              the shell, in the current directory
  ceres run game.cres                    a program
  ceresc prog.c --stdlib -O2 --run       compile a program against the C library, and run it
  ceresc prog.c --stdlib -lceres_irq --run    ... with an optional module (irq, fault, mmu)

Installing
----------
Windows:        run install.cmd (or: powershell -ExecutionPolicy Bypass -File install.ps1 [-Destination <dir>])
                uninstall.cmd, in the installed directory, removes it again.
Linux, macOS:   ./install.sh [--prefix <dir>] [--bindir <dir>] [--no-env]
                uninstall.sh, in the installed directory, removes it again.

Or use it where it is: the tools work from this directory without being installed.

Built from:
@SOURCES@
