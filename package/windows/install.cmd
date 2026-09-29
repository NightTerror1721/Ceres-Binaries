@echo off
rem Installs Ceres for the current user (install.ps1 says how): double-click it, or run it with install.ps1's options.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Pause %*
