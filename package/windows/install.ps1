<#
.SYNOPSIS
    Installs Ceres for the current user: copies it into a directory, sets CERES_PATH to that directory and puts it
    on PATH.

.DESCRIPTION
    Run it from the unpacked package (install.cmd does), or let the setup program run it: that one unpacks a
    payload.zip next to this script, and the package is taken from there. Nothing needs administrator rights: the
    directory is the user's (by default), and so are the variables.

    A directory that holds an earlier installation is replaced whole. One that holds anything else is refused.
    Installing into the directory the package already is in only sets the variables.

    The variables are written to the user's environment (HKCU\Environment), PATH keeping its %VARIABLE%
    references, and every program started afterwards sees them - a terminal that was already open does not.

.PARAMETER Destination
    Where to install. The default is %LOCALAPPDATA%\Programs\Ceres.

.PARAMETER NoEnvironment
    Leave CERES_PATH and PATH alone: the tools still work, from their own directory.

.PARAMETER Yes
    Do not ask before installing.

.PARAMETER Pause
    Wait for Enter before closing (install.cmd and the setup program pass it, for a window of their own).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File install.ps1
    powershell -ExecutionPolicy Bypass -File install.ps1 -Destination D:\Tools\Ceres -Yes
#>
[CmdletBinding()]
param(
    [string]$Destination = (Join-Path $env:LOCALAPPDATA 'Programs\Ceres'),
    [switch]$NoEnvironment,
    [switch]$Yes,
    [switch]$Pause
)

$ErrorActionPreference = 'Stop'

# What a package holds, and so what an earlier installation is made of: all of it is removed before copying.
$PackageItems = @('ceres.exe', 'ceresc.exe', 'SDL3.dll', 'shell', 'stdlib', 'licenses', 'README.txt', 'LICENSE.txt',
    'VERSION', 'install.ps1', 'install.cmd', 'uninstall.ps1', 'uninstall.cmd')

function Get-FullPath([string]$path) { return [System.IO.Path]::GetFullPath($path).TrimEnd('\') }

# PATH as it is stored - REG_EXPAND_SZ, with its %VARIABLE% references unexpanded - so writing it back loses nothing.
function Get-UserPath {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
    try { return [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
    finally { $key.Close() }
}
function Set-UserPath([string]$value) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    try { $key.SetValue('Path', $value, [Microsoft.Win32.RegistryValueKind]::ExpandString) }
    finally { $key.Close() }
}
function Test-SameDirectory([string]$a, [string]$b) {
    return [string]::Equals([Environment]::ExpandEnvironmentVariables($a).TrimEnd('\'), $b.TrimEnd('\'),
        [StringComparison]::OrdinalIgnoreCase)
}

$temp = $null
$failed = $false
try {
    # ---- the package: this directory, or the payload the setup program unpacked beside this script ----
    $source = $PSScriptRoot
    $payload = Join-Path $PSScriptRoot 'payload.zip'
    if (Test-Path -LiteralPath $payload) {
        $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("ceres-install-" + [guid]::NewGuid().ToString('N'))
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($payload, $temp)
        $source = Join-Path $temp 'Ceres'
    }
    foreach ($needed in 'ceres.exe', 'ceresc.exe', 'shell\shell.cres', 'shell\shell-small.cres', 'stdlib\include') {
        if (-not (Test-Path -LiteralPath (Join-Path $source $needed))) { throw "this is not a whole Ceres package: $needed is missing from $source" }
    }
    $version = if (Test-Path -LiteralPath (Join-Path $source 'VERSION')) { (Get-Content -LiteralPath (Join-Path $source 'VERSION') -TotalCount 1).Trim() } else { '' }
    $source = Get-FullPath $source
    $Destination = Get-FullPath $Destination

    if (-not $Yes) {
        Write-Host "Ceres $version will be installed into $Destination"
        if (-not $NoEnvironment) { Write-Host "CERES_PATH will name that directory, and it will be added to your PATH." }
        $answer = Read-Host "Enter to install there, another directory to install in it instead, or n to cancel"
        if ($answer -match '^\s*(n|no)\s*$') { Write-Host 'Nothing was installed.'; return }
        if ($answer.Trim()) { $Destination = Get-FullPath $answer.Trim().Trim('"') }
    }

    # ---- the files ----
    if (Test-SameDirectory $Destination $source) {
        Write-Host "Using Ceres where it is, in $Destination"
    }
    else {
        if (Test-Path -LiteralPath $Destination -PathType Leaf) { throw "$Destination is a file" }
        if (Test-Path -LiteralPath $Destination) {
            $present = @(Get-ChildItem -LiteralPath $Destination -Force)
            if ($present.Count -gt 0 -and -not (Test-Path -LiteralPath (Join-Path $Destination 'ceres.exe'))) {
                throw "$Destination is not empty and holds no Ceres installation: choose another directory"
            }
            foreach ($item in $PackageItems) {
                $old = Join-Path $Destination $item
                if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Recurse -Force }
            }
        }
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
        foreach ($item in Get-ChildItem -LiteralPath $source -Force) {
            if ($item.Name -eq 'payload.zip') { continue }
            Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force
        }
        Write-Host "Installed Ceres $version into $Destination"
    }

    # ---- the environment ----
    if (-not $NoEnvironment) {
        $userPath = Get-UserPath
        $entries = @($userPath -split ';' | Where-Object { $_ -ne '' })
        if (-not ($entries | Where-Object { Test-SameDirectory $_ $Destination })) {
            Set-UserPath ((@($entries) + $Destination) -join ';')
            Write-Host "Added $Destination to your PATH"
        }
        # Set last: it tells every window the environment changed, PATH included.
        [Environment]::SetEnvironmentVariable('CERES_PATH', $Destination, 'User')
        Write-Host "CERES_PATH is $Destination"
        Write-Host "Open a new terminal, then: ceres run    or    ceresc prog.c --stdlib --run"
    }
    else {
        Write-Host "The environment was left alone: run $(Join-Path $Destination 'ceres.exe') by its path, or set CERES_PATH yourself."
    }
}
catch {
    $failed = $true
    Write-Host "Ceres was not installed: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    if ($temp -and (Test-Path -LiteralPath $temp)) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
    if ($Pause) { [void](Read-Host 'Press Enter to close') }
}
if ($failed) { exit 1 }
