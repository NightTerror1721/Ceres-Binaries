<#
.SYNOPSIS
    Builds Ceres for Windows x64 - the virtual machine (ceres), the C compiler (ceresc), the C library and the shell -
    and packages it: a zip that installs itself, and a setup program.

.DESCRIPTION
    The sources are the three repositories under sources/ (git submodules, fetched here when they are missing), or
    the checkouts -CeresAsm, -CeresC and -Stdlib name. Each is built in build\windows-x64:

      ceres     CeresASM, Release, with the SDL3 window (fetched and built by its CMake) and link-time optimization;
                linked statically, so it needs no MinGW runtime DLL - only SDL3.dll, which goes beside it
      ceresc    Ceres-C, Release, with link-time optimization, statically linked
      stdlib    the Ceres STDLIB at -O2, built with the ceres and ceresc above: its build leaves stdlib\ and
                shell\shell.cres laid out as they go in the installation

    and put together in build\windows-x64\stage\Ceres, the directory Ceres is installed as (CERES_PATH):

      ceres.exe  ceresc.exe  SDL3.dll  shell\shell.cres  stdlib\include  stdlib\lib  licenses\
      README.txt  LICENSE.txt  VERSION  install.cmd  install.ps1  uninstall.cmd  uninstall.ps1

    A smoke test runs from there before anything is packaged: a C program compiled with --stdlib and run, with no
    CERES_PATH (so the tools find each other and the library through their own directory), and the shell started
    and ended. Then, in dist\:

      ceres-<version>-windows-x64.zip         the directory; install.cmd in it installs it
      ceres-<version>-windows-x64-setup.exe   the setup program: Inno Setup's (package\windows\ceres.iss) when
                                              ISCC.exe is found, else an IExpress one that runs install.ps1

    -Prebuilt copies both into prebuilt\windows-x64 as well, where the repository keeps them.

    Needs CMake 3.28+, Ninja, git, and GCC with C++23 (MSYS2's mingw64 is what it is built with) on PATH.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build.ps1
    powershell -ExecutionPolicy Bypass -File build.ps1 -Prebuilt
    powershell -ExecutionPolicy Bypass -File build.ps1 -CeresAsm D:\Projects\CeresASM -CeresC D:\Projects\Ceres-C -Stdlib "D:\Projects\Ceres Projects\Ceres STDLIB"
#>
[CmdletBinding()]
param(
    [string]$CeresAsm,       # default: sources\CeresASM
    [string]$CeresC,         # default: sources\Ceres-C
    [string]$Stdlib,         # default: sources\Ceres-STDLIB
    [string]$BuildDir,       # default: build\windows-x64
    [string]$OutDir,         # default: dist
    [switch]$NoSdl,          # a ceres without the window (no SDL3.dll)
    [switch]$NoSetup,        # the zip alone
    [switch]$Prebuilt,       # also copy the packages into prebuilt\windows-x64
    [switch]$Clean           # build everything again from nothing
)

$ErrorActionPreference = 'Stop'
# Windows PowerShell leaves $PSScriptRoot empty in the defaults of param(), so they are filled in here.
if (-not $CeresAsm) { $CeresAsm = Join-Path $PSScriptRoot 'sources\CeresASM' }
if (-not $CeresC) { $CeresC = Join-Path $PSScriptRoot 'sources\Ceres-C' }
if (-not $Stdlib) { $Stdlib = Join-Path $PSScriptRoot 'sources\Ceres-STDLIB' }
if (-not $BuildDir) { $BuildDir = Join-Path $PSScriptRoot 'build\windows-x64' }
if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot 'dist' }
$Platform = 'windows-x64'
$Version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -TotalCount 1).Trim()
$Name = "ceres-$Version-$Platform"
$Package = Join-Path $PSScriptRoot 'package'
$env:CERES_HEADLESS = '1'     # nothing the build runs opens a window

function Step([string]$text) { Write-Host "==> $text" -ForegroundColor Cyan }

# Runs a native program and stops the build when it fails. Its stderr is not an error by itself (CMake warns there).
function Invoke-Native([string]$exe, [string[]]$arguments) {
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $exe @arguments } finally { $ErrorActionPreference = $saved }
    if ($LASTEXITCODE -ne 0) { throw "failed ($LASTEXITCODE): $exe $($arguments -join ' ')" }
}

function Find-One([string]$directory, [string]$name) {
    $found = Get-ChildItem -LiteralPath $directory -Recurse -Filter $name -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\_deps\\|\\CMakeFiles\\' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $found) { throw "the build left no $name in $directory" }
    return $found.FullName
}

# ---- the sources and the tools ------------------------------------------------------------------------------------

foreach ($tool in 'cmake', 'ninja', 'g++', 'gcc', 'git') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is not on PATH (CMake, Ninja, git, and MSYS2's mingw64 GCC are needed)" }
}
$sources = @{ CeresASM = $CeresAsm; 'Ceres-C' = $CeresC; 'Ceres-STDLIB' = $Stdlib }
$markers = @{ CeresASM = 'Ceres\CMakeLists.txt'; 'Ceres-C' = 'CMakeLists.txt'; 'Ceres-STDLIB' = 'CMakeLists.txt' }
if (($sources.Keys | Where-Object { -not (Test-Path -LiteralPath (Join-Path $sources[$_] $markers[$_])) }) ) {
    Step 'fetching the sources (git submodule update --init)'
    Invoke-Native git @('-C', $PSScriptRoot, 'submodule', 'update', '--init')
}
foreach ($repo in $sources.Keys) {
    if (-not (Test-Path -LiteralPath (Join-Path $sources[$repo] $markers[$repo]))) { throw "$repo is not in $($sources[$repo])" }
}

if ($Clean -and (Test-Path -LiteralPath $BuildDir)) { Remove-Item -LiteralPath $BuildDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $BuildDir, $OutDir | Out-Null
$sdl = if ($NoSdl) { 'OFF' } else { 'ON' }

# ---- ceres ----------------------------------------------------------------------------------------------------------

Step 'ceres (CeresASM)'
$asmBuild = Join-Path $BuildDir 'ceres'
Invoke-Native cmake @('-S', (Join-Path $CeresAsm 'Ceres'), '-B', $asmBuild, '-G', 'Ninja Multi-Config',
    '-DCMAKE_C_COMPILER=gcc', '-DCMAKE_CXX_COMPILER=g++', "-DCERES_ENABLE_SDL=$sdl", '-DCERES_ENABLE_IPO=ON',
    '-DCERES_BUILD_TESTS=OFF', '-DCMAKE_EXE_LINKER_FLAGS=-static')
Invoke-Native cmake @('--build', $asmBuild, '--config', 'Release', '--target', 'ceres')
$ceresExe = Find-One $asmBuild 'ceres.exe'

# ---- ceresc ---------------------------------------------------------------------------------------------------------

Step 'ceresc (Ceres-C)'
$ccBuild = Join-Path $BuildDir 'ceresc'
Invoke-Native cmake @('-S', $CeresC, '-B', $ccBuild, '-G', 'Ninja Multi-Config', '-DCMAKE_CXX_COMPILER=g++',
    '-DCERESC_ENABLE_IPO=ON', '-DCERESC_BUILD_TESTS=OFF', '-DCMAKE_EXE_LINKER_FLAGS=-static')
Invoke-Native cmake @('--build', $ccBuild, '--config', 'Release', '--target', 'ceresc')
$cerescExe = Find-One $ccBuild 'ceresc.exe'

# ---- the C library and the shell ------------------------------------------------------------------------------------

Step 'the C library and the shell (Ceres STDLIB, -O2)'
$libBuild = Join-Path $BuildDir 'stdlib'
Invoke-Native cmake @('-S', $Stdlib, '-B', $libBuild, '-G', 'Ninja', "-DCERES=$ceresExe", "-DCERESC=$cerescExe", '-DCERES_OPT_LEVEL=2')
Invoke-Native cmake @('--build', $libBuild)

# ---- the installation directory -------------------------------------------------------------------------------------

Step "putting $Name together"
$stage = Join-Path $BuildDir 'stage\Ceres'
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage, "$stage\shell", "$stage\licenses" | Out-Null
Copy-Item -LiteralPath $ceresExe, $cerescExe -Destination $stage
if (-not $NoSdl) { Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $ceresExe) 'SDL3.dll') -Destination $stage }
Copy-Item -LiteralPath (Join-Path $libBuild 'shell\shell.cres') -Destination "$stage\shell"
Copy-Item -LiteralPath (Join-Path $libBuild 'stdlib') -Destination $stage -Recurse
foreach ($file in 'install.ps1', 'install.cmd', 'uninstall.ps1', 'uninstall.cmd') { Copy-Item -LiteralPath (Join-Path $Package "windows\$file") -Destination $stage }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'LICENSE') -Destination "$stage\LICENSE.txt"
Copy-Item -LiteralPath (Join-Path $CeresAsm 'LICENSE') -Destination "$stage\licenses\CeresASM.txt"
Copy-Item -LiteralPath (Join-Path $CeresC 'LICENSE') -Destination "$stage\licenses\Ceres-C.txt"
if (-not $NoSdl) {
    $sdlLicense = Get-ChildItem -LiteralPath (Join-Path $asmBuild '_deps') -Recurse -Filter 'LICENSE.txt' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -match 'sdl3-src$' } | Select-Object -First 1
    if ($sdlLicense) { Copy-Item -LiteralPath $sdlLicense.FullName -Destination "$stage\licenses\SDL3.txt" }
}
Set-Content -LiteralPath "$stage\VERSION" -Value $Version -Encoding Ascii
$built = foreach ($repo in 'CeresASM', 'Ceres-C', 'Ceres-STDLIB') {
    $commit = (& git -C $sources[$repo] rev-parse --short HEAD 2>$null)
    "  $repo $(if ($commit) { $commit } else { '(not a git checkout)' })"
}
$readme = (Get-Content -LiteralPath (Join-Path $Package 'README.txt') -Raw).Replace('@VERSION@', $Version).Replace('@PLATFORM@', $Platform).Replace('@SOURCES@', ($built -join "`r`n"))
Set-Content -LiteralPath "$stage\README.txt" -Value $readme -Encoding Ascii -NoNewline

# The runtime a statically linked build must not need.
$objdump = Get-Command objdump -ErrorAction SilentlyContinue
if ($objdump) {
    foreach ($exe in "$stage\ceres.exe", "$stage\ceresc.exe") {
        $dlls = & $objdump.Source -p $exe | Select-String 'DLL Name: (.+)$' | ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() }
        $foreign = @($dlls | Where-Object { $_ -match '^(libstdc\+\+|libgcc|libwinpthread)' })
        if ($foreign.Count -gt 0) { throw "$exe still needs $($foreign -join ', ')" }
    }
}

# ---- the smoke test -------------------------------------------------------------------------------------------------

Step 'smoke test'
$smoke = Join-Path $BuildDir 'smoke'
if (Test-Path -LiteralPath $smoke) { Remove-Item -LiteralPath $smoke -Recurse -Force }
New-Item -ItemType Directory -Force -Path $smoke | Out-Null
Copy-Item -LiteralPath (Join-Path $Package 'smoke\hello.c'), (Join-Path $Package 'smoke\shell.type') -Destination $smoke
$savedCeresPath = $env:CERES_PATH
Remove-Item Env:CERES_PATH -ErrorAction SilentlyContinue     # the tools must find what they need beside themselves
Push-Location $smoke
$ErrorActionPreference = 'Continue'     # what the tools write to stderr is judged by their exit status
try {
    & "$stage\ceresc.exe" hello.c --stdlib -O2 --run --run-arg --transcript --run-arg hello.txt -- smoke | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "the smoke test program ended with $LASTEXITCODE" }
    $expected = [System.IO.File]::ReadAllText((Join-Path $Package 'smoke\hello.expected')).Replace("`r`n", "`n")
    $got = [System.IO.File]::ReadAllText((Join-Path $smoke 'hello.txt')).Replace("`r`n", "`n")
    if ($got -ne $expected) { throw "the smoke test printed '$got', not '$expected'" }
    & "$stage\ceres.exe" run --headless --type shell.type --transcript shell.txt | Out-Null
    if ($LASTEXITCODE -ne 7) { throw "the shell ended with $LASTEXITCODE, not 7" }
    if (-not ([System.IO.File]::ReadAllText((Join-Path $smoke 'shell.txt')) -match 'Ceres shell')) { throw 'the shell did not start' }
}
finally {
    $ErrorActionPreference = 'Stop'
    Pop-Location
    if ($null -ne $savedCeresPath) { $env:CERES_PATH = $savedCeresPath }
}
Write-Host '    ok: a program compiled with --stdlib and run, and the shell'

# ---- the packages ---------------------------------------------------------------------------------------------------

Step 'packages'
$zip = Join-Path $OutDir "$Name.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $true)
Write-Host "    $zip"
$packages = @($zip)

if (-not $NoSetup) {
    $setup = Join-Path $OutDir "$Name-setup.exe"
    if (Test-Path -LiteralPath $setup) { Remove-Item -LiteralPath $setup -Force }
    $iscc = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    $isccPath = if ($iscc) { $iscc.Source } else {
        @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") |
            Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    }
    if ($isccPath) {
        Invoke-Native $isccPath @('/Q', "/DAppVersion=$Version", "/DStageDir=$stage", "/DOutputDir=$OutDir", "/DOutputName=$Name-setup",
            (Join-Path $Package 'windows\ceres.iss'))
    }
    else {
        # IExpress, which every Windows has: a self-extracting program that unpacks the zip and install.ps1 into a
        # temporary directory and runs install.cmd there.
        $work = Join-Path $BuildDir 'iexpress'
        if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $work | Out-Null
        Copy-Item -LiteralPath $zip -Destination (Join-Path $work 'payload.zip')
        Copy-Item -LiteralPath (Join-Path $Package 'windows\install.ps1'), (Join-Path $Package 'windows\install.cmd') -Destination $work
        $sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuietInstCmd=%AdminQuietInstCmd%
UserQuietInstCmd=%UserQuietInstCmd%
SourceFiles=SourceFiles
[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$setup
FriendlyName=Ceres $Version
AppLaunched=cmd /c install.cmd
PostInstallCmd=<None>
AdminQuietInstCmd=cmd /c install.cmd -Yes
UserQuietInstCmd=cmd /c install.cmd -Yes
FILE0="payload.zip"
FILE1="install.ps1"
FILE2="install.cmd"
[SourceFiles]
SourceFiles0=$work\
[SourceFiles0]
%FILE0%=
%FILE1%=
%FILE2%=
"@
        $sedFile = Join-Path $work 'ceres.sed'
        Set-Content -LiteralPath $sedFile -Value $sed -Encoding Ascii
        $process = Start-Process -FilePath "$env:SystemRoot\System32\iexpress.exe" -ArgumentList '/N', '/Q', $sedFile -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $setup)) { throw "IExpress did not make $setup (exit $($process.ExitCode))" }
    }
    Write-Host "    $setup"
    $packages += $setup
}

if ($Prebuilt) {
    $keep = Join-Path $PSScriptRoot "prebuilt\$Platform"
    if (Test-Path -LiteralPath $keep) { Get-ChildItem -LiteralPath $keep -File | Where-Object { $_.Name -like 'ceres-*' } | Remove-Item -Force }
    New-Item -ItemType Directory -Force -Path $keep | Out-Null
    Copy-Item -LiteralPath $packages -Destination $keep
    Write-Host "    copied into $keep"
}
Step "done: Ceres $Version for $Platform"
