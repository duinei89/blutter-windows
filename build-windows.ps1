$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot
$Dist = Join-Path $Root "dist"
$Package = Join-Path $Dist "blutter"

$LauncherSource = Join-Path $Root "launcher\launcher.cpp"
$LauncherExe = Join-Path $Package "blutter.exe"

$External = Join-Path $Root "external"

$Tools = Join-Path $Package "tools"
$Bin = Join-Path $Package "bin"
$PythonDir = Join-Path $Package "python"
$LLVMDir = Join-Path $Package "llvm"
$Sysroot = Join-Path $Package "sysroot"

$Temp = Join-Path $Root ".build-temp"

Write-Host ""
Write-Host "============================================================"
Write-Host "              BLUTTER WINDOWS BUILD"
Write-Host "============================================================"
Write-Host ""

# ============================================================
# Configuration
# ============================================================

$PythonVersion = "3.12"

$ICUUrl =
    "https://github.com/unicode-org/icu/releases/download/release-73-2/icu4c-73_2-Win64-MSVC2019.zip"

$CapstoneUrl =
    "https://github.com/capstone-engine/capstone/releases/download/4.0.2/capstone-4.0.2-win64.zip"

$LLVMReleaseApi =
    "https://api.github.com/repos/llvm/llvm-project/releases/latest"

# ============================================================
# Helpers
# ============================================================

function Ensure-Directory($Path) {
    if (!(Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Remove-Directory($Path) {
    if (Test-Path $Path) {
        Remove-Item $Path -Recurse -Force
    }
}

function Download-File($Url, $OutFile) {

    Write-Host ""
    Write-Host "Downloading:"
    Write-Host $Url
    Write-Host ""

    $maxAttempts = 6

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {

        try {

            if (Test-Path $OutFile) {
                Remove-Item $OutFile -Force
            }

            Invoke-WebRequest `
                -Uri $Url `
                -OutFile $OutFile `
                -UseBasicParsing `
                -TimeoutSec 300

            if (!(Test-Path $OutFile)) {
                throw "Download did not create output file."
            }

            $size = (Get-Item $OutFile).Length

            if ($size -lt 1024) {
                throw "Downloaded file is unexpectedly small."
            }

            Write-Host "Download successful:"
            Write-Host "$size bytes"

            return
        }
        catch {

            Write-Warning "Download attempt $attempt failed."
            Write-Warning $_.Exception.Message

            if ($attempt -eq $maxAttempts) {
                throw
            }

            Start-Sleep -Seconds (5 * $attempt)
        }
    }
}

function Expand-TarGz($Archive, $Destination) {

    Ensure-Directory $Destination

    $tar = Get-Command tar.exe -ErrorAction SilentlyContinue

    if (!$tar) {
        throw "tar.exe is required but was not found."
    }

    & tar.exe -xzf $Archive -C $Destination

    if ($LASTEXITCODE -ne 0) {
        throw "tar extraction failed."
    }
}

function Find-FileRecursive($RootPath, $Name) {

    $result = Get-ChildItem `
        -Path $RootPath `
        -Recurse `
        -File `
        -Filter $Name `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($result) {
        return $result.FullName
    }

    return $null
}

# ============================================================
# Clean
# ============================================================

Write-Host "[1/12] Cleaning..."

Remove-Directory $Dist
Remove-Directory $Temp

Ensure-Directory $Package
Ensure-Directory $External
Ensure-Directory $Tools
Ensure-Directory $Bin

# ============================================================
# MSVC for building launcher only
# ============================================================

Write-Host ""
Write-Host "[2/12] Checking MSVC build environment..."

$cl = Get-Command cl.exe -ErrorAction SilentlyContinue

if (!$cl) {
    throw "cl.exe was not found. GitHub Actions must initialize MSVC."
}

Write-Host "MSVC:"
Write-Host $cl.Source

# ============================================================
# Native launcher
# ============================================================

Write-Host ""
Write-Host "[3/12] Building native blutter.exe..."

if (!(Test-Path $LauncherSource)) {
    throw "Launcher source not found: $LauncherSource"
}

$compileCommand = @"
cl.exe /nologo /std:c++17 /O2 /EHsc /MT /DUNICODE /D_UNICODE /Fe:"$LauncherExe" "$LauncherSource" /link /SUBSYSTEM:CONSOLE
"@

Write-Host $compileCommand
Write-Host ""

cmd.exe /d /s /c $compileCommand

$compileExit = $LASTEXITCODE

if ($compileExit -ne 0) {
    throw "launcher.cpp compilation failed with exit code $compileExit."
}

if (!(Test-Path $LauncherExe)) {
    throw "Native launcher was not created."
}

Write-Host "Native launcher created:"
Write-Host $LauncherExe

# ============================================================
# Copy Blutter source
# ============================================================

Write-Host ""
Write-Host "[4/12] Copying Blutter source..."

$FilesToCopy = @(
    "blutter.py",
    "README.md",
    "LICENSE",
    "dartvm_fetch_build.py",
    "extract_dart_info.py"
)

foreach ($file in $FilesToCopy) {

    $source = Join-Path $Root $file

    if (Test-Path $source) {
        Copy-Item `
            $source `
            (Join-Path $Package $file) `
            -Force
    }
}

$DirectoriesToCopy = @(
    "blutter",
    "scripts"
)

foreach ($dir in $DirectoriesToCopy) {

    $source = Join-Path $Root $dir

    if (Test-Path $source) {

        Copy-Item `
            $source `
            (Join-Path $Package $dir) `
            -Recurse `
            -Force
    }
}

# ============================================================
# Python
# ============================================================

Write-Host ""
Write-Host "[5/12] Downloading standalone Python..."

Ensure-Directory $PythonDir

$PythonApi =
    "https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest"

$headers = @{
    "User-Agent" = "blutter-windows-build"
}

$pythonRelease = Invoke-RestMethod `
    -Uri $PythonApi `
    -Headers $headers

$pythonAsset = $pythonRelease.assets |
    Where-Object {
        $_.name -match "^cpython-$PythonVersion\." -and
        $_.name -match "x86_64-pc-windows-msvc-install_only\.tar\.gz$"
    } |
    Select-Object -First 1

if (!$pythonAsset) {
    throw "Could not find standalone Python $PythonVersion Windows x64 asset."
}

Write-Host "Selected Python:"
Write-Host $pythonAsset.name

$PythonArchive =
    Join-Path $External $pythonAsset.name

Download-File `
    $pythonAsset.browser_download_url `
    $PythonArchive

$PythonExtract =
    Join-Path $Temp "python"

Remove-Directory $PythonExtract
Ensure-Directory $PythonExtract

Expand-TarGz `
    $PythonArchive `
    $PythonExtract

$PythonExeSource =
    Find-FileRecursive $PythonExtract "python.exe"

if (!$PythonExeSource) {
    throw "python.exe was not found in standalone Python archive."
}

$PythonRootSource =
    Split-Path $PythonExeSource -Parent

Copy-Item `
    "$PythonRootSource\*" `
    $PythonDir `
    -Recurse `
    -Force

$BundledPython =
    Join-Path $PythonDir "python.exe"

if (!(Test-Path $BundledPython)) {
    throw "Bundled Python installation failed."
}

Write-Host "Bundled Python:"
& $BundledPython --version

# ============================================================
# Python dependencies
# ============================================================

Write-Host ""
Write-Host "[6/12] Installing Python dependencies..."

& $BundledPython -m pip install --upgrade pip

if ($LASTEXITCODE -ne 0) {
    throw "pip upgrade failed."
}

& $BundledPython -m pip install `
    requests `
    pyelftools

if ($LASTEXITCODE -ne 0) {
    throw "Python dependencies failed."
}

# ============================================================
# CMake
# ============================================================

Write-Host ""
Write-Host "[7/12] Downloading CMake..."

$CMakeApi =
    "https://api.github.com/repos/Kitware/CMake/releases/latest"

$cmakeRelease = Invoke-RestMethod `
    -Uri $CMakeApi `
    -Headers $headers

$cmakeAsset = $cmakeRelease.assets |
    Where-Object {
        $_.name -match "windows-x86_64\.zip$"
    } |
    Select-Object -First 1

if (!$cmakeAsset) {
    throw "Could not find Windows x64 CMake archive."
}

$CMakeArchive =
    Join-Path $External $cmakeAsset.name

Download-File `
    $cmakeAsset.browser_download_url `
    $CMakeArchive

$CMakeExtract =
    Join-Path $Temp "cmake"

Remove-Directory $CMakeExtract
Ensure-Directory $CMakeExtract

Expand-Archive `
    $CMakeArchive `
    $CMakeExtract `
    -Force

$CMakeExeSource =
    Find-FileRecursive $CMakeExtract "cmake.exe"

if (!$CMakeExeSource) {
    throw "cmake.exe was not found."
}

$CMakeRootSource =
    Split-Path `
        (Split-Path $CMakeExeSource -Parent) `
        -Parent

Ensure-Directory (Join-Path $Tools "cmake")

Copy-Item `
    "$CMakeRootSource\*" `
    (Join-Path $Tools "cmake") `
    -Recurse `
    -Force

# ============================================================
# Ninja
# ============================================================

Write-Host ""
Write-Host "[8/12] Downloading Ninja..."

$NinjaApi =
    "https://api.github.com/repos/ninja-build/ninja/releases/latest"

$ninjaRelease = Invoke-RestMethod `
    -Uri $NinjaApi `
    -Headers $headers

$ninjaAsset = $ninjaRelease.assets |
    Where-Object {
        $_.name -eq "ninja-win.zip"
    } |
    Select-Object -First 1

if (!$ninjaAsset) {
    throw "Could not find ninja-win.zip."
}

$NinjaArchive =
    Join-Path $External "ninja-win.zip"

Download-File `
    $ninjaAsset.browser_download_url `
    $NinjaArchive

$NinjaExtract =
    Join-Path $Temp "ninja"

Remove-Directory $NinjaExtract
Ensure-Directory $NinjaExtract

Expand-Archive `
    $NinjaArchive `
    $NinjaExtract `
    -Force

$NinjaExe =
    Find-FileRecursive $NinjaExtract "ninja.exe"

if (!$NinjaExe) {
    throw "ninja.exe was not found."
}

Copy-Item `
    $NinjaExe `
    (Join-Path $Tools "ninja.exe") `
    -Force

# ============================================================
# Git
# ============================================================

Write-Host ""
Write-Host "[9/12] Downloading Git..."

$GitApi =
    "https://api.github.com/repos/git-for-windows/git/releases/latest"

$gitRelease = Invoke-RestMethod `
    -Uri $GitApi `
    -Headers $headers

$gitAsset = $gitRelease.assets |
    Where-Object {
        $_.name -match "MinGit-.*-64-bit\.zip$"
    } |
    Select-Object -First 1

if (!$gitAsset) {
    throw "Could not find Git for Windows MinGit x64 archive."
}

$GitArchive =
    Join-Path $External "mingit.zip"

Download-File `
    $gitAsset.browser_download_url `
    $GitArchive

$GitExtract =
    Join-Path $Temp "git"

Remove-Directory $GitExtract
Ensure-Directory $GitExtract

Expand-Archive `
    $GitArchive `
    $GitExtract `
    -Force

$GitRootSource =
    Get-ChildItem `
        $GitExtract `
        -Directory |
        Select-Object -First 1

if (!$GitRootSource) {
    throw "Git extraction failed."
}

Ensure-Directory (Join-Path $Tools "git")

Copy-Item `
    "$($GitRootSource.FullName)\*" `
    (Join-Path $Tools "git") `
    -Recurse `
    -Force

# ============================================================
# LLVM / Clang
# ============================================================

Write-Host ""
Write-Host "[10/12] Downloading LLVM / Clang..."

$llvmRelease = Invoke-RestMethod `
    -Uri $LLVMReleaseApi `
    -Headers $headers

$llvmAsset = $llvmRelease.assets |
    Where-Object {
        $_.name -match "^LLVM-.*-win64\.zip$"
    } |
    Select-Object -First 1

if (!$llvmAsset) {

    $llvmAsset = $llvmRelease.assets |
        Where-Object {
            $_.name -match "LLVM-.*-win64\.exe$"
        } |
        Select-Object -First 1
}

if (!$llvmAsset) {
    throw "Could not find an official LLVM Windows x64 release asset."
}

Write-Host "Selected LLVM:"
Write-Host $llvmAsset.name

$LLVMArchive =
    Join-Path $External $llvmAsset.name

Download-File `
    $llvmAsset.browser_download_url `
    $LLVMArchive

$LLVMExtract =
    Join-Path $Temp "llvm"

Remove-Directory $LLVMExtract
Ensure-Directory $LLVMExtract

if ($llvmAsset.name.EndsWith(".zip")) {

    Expand-Archive `
        $LLVMArchive `
        $LLVMExtract `
        -Force
}
else {
    throw "LLVM installer was selected. Use an official Windows x64 archive release."
}

$LLVMBinSource =
    Find-FileRecursive $LLVMExtract "clang-cl.exe"

if (!$LLVMBinSource) {
    throw "clang-cl.exe was not found in LLVM package."
}

$LLVMRootSource =
    Split-Path `
        (Split-Path $LLVMBinSource -Parent) `
        -Parent

Copy-Item `
    "$LLVMRootSource\*" `
    $LLVMDir `
    -Recurse `
    -Force

$BundledClang =
    Join-Path $LLVMDir "bin\clang-cl.exe"

$BundledLLD =
    Join-Path $LLVMDir "bin\lld-link.exe"

if (!(Test-Path $BundledClang)) {
    throw "Bundled clang-cl.exe is missing."
}

if (!(Test-Path $BundledLLD)) {
    throw "Bundled lld-link.exe is missing."
}

# ============================================================
# xwin
# ============================================================

Write-Host ""
Write-Host "Building Windows CRT / SDK sysroot..."

$XwinDir =
    Join-Path $Temp "xwin"

Remove-Directory $XwinDir
Ensure-Directory $XwinDir

$Cargo = Get-Command cargo.exe -ErrorAction SilentlyContinue

if (!$Cargo) {
    throw "cargo.exe was not found. GitHub Actions runner must provide Rust."
}

Write-Host "Installing xwin..."

cargo install xwin --locked

if ($LASTEXITCODE -ne 0) {
    throw "xwin installation failed."
}

$xwinExe =
    Join-Path $env:USERPROFILE ".cargo\bin\xwin.exe"

if (!(Test-Path $xwinExe)) {

    $xwinCommand =
        Get-Command xwin.exe -ErrorAction SilentlyContinue

    if ($xwinCommand) {
        $xwinExe = $xwinCommand.Source
    }
}

if (!(Test-Path $xwinExe)) {
    throw "xwin.exe was not found after installation."
}

Write-Host "xwin:"
Write-Host $xwinExe

Write-Host ""
Write-Host "Downloading Microsoft CRT / Windows SDK..."
Write-Host ""

& $xwinExe `
    --arch x86_64 `
    --accept-license `
    splat `
    --use-winsysroot-style `
    --preserve-ms-arch-notation `
    --disable-symlinks `
    --output $Sysroot

if ($LASTEXITCODE -ne 0) {
    throw "xwin failed to create the Windows sysroot."
}

if (!(Test-Path (Join-Path $Sysroot "crt"))) {
    throw "xwin sysroot is missing CRT."
}

if (!(Test-Path (Join-Path $Sysroot "sdk"))) {
    throw "xwin sysroot is missing Windows SDK."
}

# ============================================================
# Compiler environment
# ============================================================

Write-Host ""
Write-Host "Configuring bundled compiler..."

$LLVMBin =
    Join-Path $LLVMDir "bin"

$ClangCl =
    Join-Path $LLVMBin "clang-cl.exe"

$LLDLink =
    Join-Path $LLVMBin "lld-link.exe"

$PathValue =
    "$LLVMBin;" +
    "$Bin;" +
    "$Tools;" +
    "$(Join-Path $Tools 'cmake\bin');" +
    "$env:PATH"

$env:PATH = $PathValue

$env:CC = $ClangCl
$env:CXX = $ClangCl
$env:LINK = $LLDLink

$env:CL =
    "/winsysroot `"$Sysroot`" -fuse-ld=lld-link"

$env:CMAKE_C_COMPILER = $ClangCl
$env:CMAKE_CXX_COMPILER = $ClangCl

Write-Host ""
Write-Host "Compiler:"
& $ClangCl --version

Write-Host ""
Write-Host "Linker:"
& $LLDLink --version

# ============================================================
# Compiler smoke test
# ============================================================

Write-Host ""
Write-Host "Running bundled compiler smoke test..."

$SmokeDir =
    Join-Path $Temp "compiler-test"

Remove-Directory $SmokeDir
Ensure-Directory $SmokeDir

$SmokeSource =
    Join-Path $SmokeDir "main.cpp"

$SmokeExe =
    Join-Path $SmokeDir "compiler-test.exe"

@"
#include <windows.h>
#include <iostream>

int main()
{
    std::cout << "Bundled Blutter Windows compiler OK" << std::endl;
    return 0;
}
"@ | Set-Content `
    -Path $SmokeSource `
    -Encoding UTF8

& $ClangCl `
    /nologo `
    /std:c++20 `
    /O2 `
    /EHsc `
    "/winsysroot:$Sysroot" `
    "-fuse-ld=lld-link" `
    "/Fe:$SmokeExe" `
    $SmokeSource

if ($LASTEXITCODE -ne 0) {
    throw "Bundled Clang/Windows sysroot smoke test failed."
}

if (!(Test-Path $SmokeExe)) {
    throw "Compiler smoke test did not create executable."
}

Write-Host ""
Write-Host "Running smoke test..."
& $SmokeExe

if ($LASTEXITCODE -ne 0) {
    throw "Compiler smoke test executable failed."
}

# ============================================================
# ICU
# ============================================================

Write-Host ""
Write-Host "Installing ICU..."

$ICUArchive =
    Join-Path $External "icu-windows.zip"

Download-File `
    $ICUUrl `
    $ICUArchive

$ICUDir =
    Join-Path $Package "external\icu"

Remove-Directory $ICUDir
Ensure-Directory $ICUDir

Expand-Archive `
    $ICUArchive `
    $ICUDir `
    -Force

# ============================================================
# Capstone
# ============================================================

Write-Host ""
Write-Host "Installing Capstone..."

$CapstoneArchive =
    Join-Path $External "capstone-windows.zip"

Download-File `
    $CapstoneUrl `
    $CapstoneArchive

$CapstoneDir =
    Join-Path $Package "external\capstone"

Remove-Directory $CapstoneDir
Ensure-Directory $CapstoneDir

Expand-Archive `
    $CapstoneArchive `
    $CapstoneDir `
    -Force

# ============================================================
# Existing Blutter Windows initialization
# ============================================================

Write-Host ""
Write-Host "[11/12] Initializing Blutter..."

$env:PATH =
    "$LLVMBin;" +
    "$Bin;" +
    "$Tools;" +
    "$(Join-Path $Tools 'cmake\bin');" +
    "$env:PATH"

$env:CC = $ClangCl
$env:CXX = $ClangCl
$env:LINK = $LLDLink
$env:CL =
    "/winsysroot `"$Sysroot`" -fuse-ld=lld-link"

& $BundledPython scripts\init_env_win.py

if ($LASTEXITCODE -ne 0) {
    throw "Blutter Windows environment initialization failed."
}

# ============================================================
# Final package validation
# ============================================================

Write-Host ""
Write-Host "[12/12] Verifying final package..."

$RequiredFiles = @(
    (Join-Path $Package "blutter.exe"),
    (Join-Path $Package "blutter.py"),
    (Join-Path $Package "python\python.exe"),
    (Join-Path $Package "llvm\bin\clang-cl.exe"),
    (Join-Path $Package "llvm\bin\lld-link.exe")
)

foreach ($file in $RequiredFiles) {

    if (!(Test-Path $file)) {
        throw "Required package file is missing: $file"
    }

    Write-Host "OK:"
    Write-Host "  $file"
}

$RequiredDirectories = @(
    (Join-Path $Package "sysroot\crt"),
    (Join-Path $Package "sysroot\sdk"),
    (Join-Path $Package "tools")
)

foreach ($directory in $RequiredDirectories) {

    if (!(Test-Path $directory)) {
        throw "Required package directory is missing: $directory"
    }
}

Write-Host ""
Write-Host "Testing bundled Python..."
& $BundledPython --version

if ($LASTEXITCODE -ne 0) {
    throw "Bundled Python test failed."
}

Write-Host ""
Write-Host "Testing native launcher..."

& $LauncherExe

# No arguments should show help and exit non-zero.
# That is expected.

Write-Host ""
Write-Host "============================================================"
Write-Host "             BLUTTER WINDOWS BUILD COMPLETE"
Write-Host "============================================================"
Write-Host ""
Write-Host "Package:"
Write-Host $Package
Write-Host ""
