<#
.SYNOPSIS
    Removes the Ceres installation this script is part of: its directory, its entry in PATH and CERES_PATH when it
    names this directory.

.PARAMETER Yes
    Do not ask before removing.

.PARAMETER Pause
    Wait for Enter before closing (uninstall.cmd passes it).
#>
[CmdletBinding()]
param(
    [switch]$Yes,
    [switch]$Pause
)

$ErrorActionPreference = 'Stop'
$failed = $false
try {
    $directory = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
    if (-not (Test-Path -LiteralPath (Join-Path $directory 'ceres.exe'))) { throw "$directory is not a Ceres installation" }
    if (-not $Yes) {
        $answer = Read-Host "Remove Ceres from $directory, with everything in that directory? y to remove"
        if ($answer -notmatch '^\s*(y|yes)\s*$') { Write-Host 'Nothing was removed.'; return }
    }

    $same = { param($a) [string]::Equals([Environment]::ExpandEnvironmentVariables($a).TrimEnd('\'), $directory, [StringComparison]::OrdinalIgnoreCase) }

    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    try {
        $path = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $entries = @($path -split ';' | Where-Object { $_ -ne '' })
        $kept = @($entries | Where-Object { -not (& $same $_) })
        if ($kept.Count -ne $entries.Count) {
            $key.SetValue('Path', ($kept -join ';'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
            Write-Host "Removed $directory from your PATH"
        }
    }
    finally { $key.Close() }
    $ceresPath = [Environment]::GetEnvironmentVariable('CERES_PATH', 'User')
    if ($ceresPath -and (& $same $ceresPath)) {
        # Also tells every window the environment changed, PATH included.
        [Environment]::SetEnvironmentVariable('CERES_PATH', $null, 'User')
        Write-Host 'Removed CERES_PATH'
    }

    Set-Location ([System.IO.Path]::GetTempPath())
    Remove-Item -LiteralPath $directory -Recurse -Force
    Write-Host "Removed $directory"
}
catch {
    $failed = $true
    Write-Host "Ceres was not removed: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    if ($Pause) { [void](Read-Host 'Press Enter to close') }
}
if ($failed) { exit 1 }
