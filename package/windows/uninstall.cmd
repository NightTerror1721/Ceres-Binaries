@echo off
rem Removes this Ceres installation (uninstall.ps1 says how). "(goto)" first: this file is deleted with the rest, and
rem cmd.exe must not try to read on from it.
(goto) 2>nul & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" -Pause %*
