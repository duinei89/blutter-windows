$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot
$Dist = Join-Path $Root "dist"
$Package = Join-Path $Dist "blutter"

$LauncherSource =
    Join-Path $Root "launcher\launcher.cpp"

$LauncherExe =
    Join-Path $Package "blutter.exe"

$Tools =
    Join-Path $Package "tools"

$CompilerRoot =
    Join-Path $Tools "llvm-mingw"

$CompilerBin =
    Join-Path $CompilerRoot "bin"

Write-Host ""
Write-Host "============================================================"
Write-Host "                 BLUTTER WINDOWS BUILD"
Write-Host "============================================================"
Write-Host ""

# ============================================================
# CLEAN
# ============================================================

Write-Host "[1/10] Cleaning..."

if (Test-Path $Dist) {
    Remove-Item $Dist -Recurse -Force
}

New-Item `
    -ItemType Directory `
    -Path $Package `
    -Force | Out-Null

New-Item `
    -ItemType Directory `
    -Path $Tools `
    -Force | Out-Null

# ============================================================
# MSVC
# ============================================================

Write-Host ""
Write-Host "[2/10] Checking MSVC..."

$cl = Get-Command cl.exe -ErrorAction SilentlyContinue

if (!$cl) {
    throw "MSVC cl.exe was not found."
}

Write-Host "MSVC:"
Write-Host $cl.Source

# Do NOT run `cl.exe` by itself.
# It intentionally returns exit code 1 when displaying usage.

# ============================================================
# BUILD LAUNCHER
# ============================================================

Write-Host ""
Write-Host "[3/10] Building launcher..."

if (!(Test-Path $LauncherSource)) {
    throw "Launcher source not found: $LauncherSource"
}

$compileArgs = @(
    "/nologo"
    "/std:c++17"
    "/O2"
    "/EHsc"
    "/MT"
    "/DUNICODE"
    "/D_UNICODE"
    "/Fe:$LauncherExe"
    $LauncherSource
    "/link"
    "/SUBSYSTEM:CONSOLE"
)

Write-Host ""
Write-Host "Compiling launcher..."

& cl.exe @compileArgs

$compileExit = $LASTEXITCODE

if ($compileExit -ne 0) {
    throw "launcher.cpp compilation failed with exit code $compileExit."
}

if (!(Test-Path $LauncherExe)) {
    throw "Launcher was not generated."
}

Write-Host "Launcher built:"
Write-Host $LauncherExe

# ============================================================
# COPY BLUTTER
# ============================================================

Write-Host ""
Write-Host "[4/10] Copying Blutter source..."

$Files = @(
    "blutter.py"
    "dartvm_fetch_build.py"
    "extract_dart_info.py"
    "README.md"
    "LICENSE"
)

foreach ($File in $Files) {

    $Source =
        Join-Path $Root $File

    if (Test-Path $Source) {

        Copy-Item `
            $Source `
            $Package `
            -Force

        Write-Host "Copied: $File"
    }
}

$Directories = @(
    "blutter"
    "scripts"
)

foreach ($Directory in $Directories) {

    $Source =
        Join-Path $Root $Directory

    if (!(Test-Path $Source)) {
        throw "Missing directory: $Source"
    }

    Copy-Item `
        $Source `
        (Join-Path $Package $Directory) `
        -Recurse `
        -Force

    Write-Host "Copied: $Directory"
}

# ============================================================
# DOWNLOAD LLVM-MINGW
# ============================================================

Write-Host ""
Write-Host "[5/10] Downloading portable LLVM-MinGW..."

$Headers = @{
    "User-Agent" = "blutter-windows-builder"
    "Accept" = "application/vnd.github+json"
}

$Api =
    "https://api.github.com/repos/mstorsjo/llvm-mingw/releases/latest"

Write-Host "Querying:"
Write-Host $Api

$Release = Invoke-RestMethod `
    -Uri $Api `
    -Headers $Headers `
    -Method Get

Write-Host ""
Write-Host "LLVM-MinGW release:"
Write-Host $Release.tag_name

$Asset = $Release.assets |
    Where-Object {
        $_.name -match `
        "^llvm-mingw-.*-ucrt-x86_64\.zip$"
    } |
    Select-Object -First 1

if (!$Asset) {

    Write-Host ""
    Write-Host "Available assets:"

    $Release.assets |
        ForEach-Object {
            Write-Host $_.name
        }

    throw "Could not find Windows x64 LLVM-MinGW archive."
}

Write-Host ""
Write-Host "Selected:"
Write-Host $Asset.name

$CompilerArchive =
    Join-Path $env:TEMP "llvm-mingw.zip"

if (Test-Path $CompilerArchive) {
    Remove-Item $CompilerArchive -Force
}

curl.exe `
    --location `
    --fail `
    --retry 10 `
    --retry-delay 5 `
    --retry-all-errors `
    --connect-timeout 30 `
    --max-time 1200 `
    --output "$CompilerArchive" `
    "$($Asset.browser_download_url)"

if ($LASTEXITCODE -ne 0) {
    throw "LLVM-MinGW download failed."
}

if (!(Test-Path $CompilerArchive)) {
    throw "LLVM-MinGW archive was not downloaded."
}

# ============================================================
# EXTRACT LLVM-MINGW
# ============================================================

Write-Host ""
Write-Host "Extracting LLVM-MinGW..."

$CompilerTemp =
    Join-Path $env:TEMP "blutter-llvm-mingw"

if (Test-Path $CompilerTemp) {
    Remove-Item `
        $CompilerTemp `
        -Recurse `
        -Force
}

New-Item `
    -ItemType Directory `
    -Path $CompilerTemp `
    -Force | Out-Null

Expand-Archive `
    -Path $CompilerArchive `
    -DestinationPath $CompilerTemp `
    -Force

$ExtractedCompiler =
    Get-ChildItem `
        $CompilerTemp `
        -Directory |
        Select-Object -First 1

if (!$ExtractedCompiler) {
    throw "Could not find extracted LLVM-MinGW directory."
}

Write-Host "Extracted:"
Write-Host $ExtractedCompiler.FullName

New-Item `
    -ItemType Directory `
    -Path $CompilerRoot `
    -Force | Out-Null

Get-ChildItem `
    $ExtractedCompiler.FullName `
    -Force |
    ForEach-Object {

        Copy-Item `
            $_.FullName `
            $CompilerRoot `
            -Recurse `
            -Force
    }

Remove-Item `
    $CompilerTemp `
    -Recurse `
    -Force

Remove-Item `
    $CompilerArchive `
    -Force

$Clang =
    Join-Path $CompilerBin "clang.exe"

$ClangXX =
    Join-Path $CompilerBin "clang++.exe"

$LLD =
    Join-Path $CompilerBin "ld.lld.exe"

$LLVMAr =
    Join-Path $CompilerBin "llvm-ar.exe"

$LLVMTar =
    Join-Path $CompilerBin "llvm-ranlib.exe"

if (!(Test-Path $Clang)) {
    throw "clang.exe missing from LLVM-MinGW package."
}

if (!(Test-Path $ClangXX)) {
    throw "clang++.exe missing from LLVM-MinGW package."
}

Write-Host ""
Write-Host "LLVM-MinGW ready:"
Write-Host $CompilerBin

# ============================================================
# DOWNLOAD PYTHON
# ============================================================

Write-Host ""
Write-Host "[6/10] Downloading standalone Python..."

$PythonDir =
    Join-Path $Package "python"

New-Item `
    -ItemType Directory `
    -Path $PythonDir `
    -Force | Out-Null

$PythonApi =
    "https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest"

$PythonRelease =
    Invoke-RestMethod `
        -Uri $PythonApi `
        -Headers $Headers `
        -Method Get

$PythonAsset =
    $PythonRelease.assets |
    Where-Object {
        $_.name -match `
        "^cpython-3\.12\.[0-9]+\+.*-x86_64-pc-windows-msvc-install_only\.tar\.gz$"
    } |
    Select-Object -First 1

if (!$PythonAsset) {
    throw "Could not find standalone CPython 3.12 x64."
}

Write-Host "Python:"
Write-Host $PythonAsset.name

$PythonArchive =
    Join-Path $env:TEMP "blutter-python.tar.gz"

if (Test-Path $PythonArchive) {
    Remove-Item $PythonArchive -Force
}

curl.exe `
    --location `
    --fail `
    --retry 10 `
    --retry-delay 5 `
    --retry-all-errors `
    --connect-timeout 30 `
    --max-time 900 `
    --output "$PythonArchive" `
    "$($PythonAsset.browser_download_url)"

if ($LASTEXITCODE -ne 0) {
    throw "Python download failed."
}

$PythonTemp =
    Join-Path $env:TEMP "blutter-python-extract"

if (Test-Path $PythonTemp) {
    Remove-Item `
        $PythonTemp `
        -Recurse `
        -Force
}

New-Item `
    -ItemType Directory `
    -Path $PythonTemp `
    -Force | Out-Null

tar.exe `
    -xzf `
    "$PythonArchive" `
    -C `
    "$PythonTemp"

if ($LASTEXITCODE -ne 0) {
    throw "Python extraction failed."
}

$ExtractedPython =
    Get-ChildItem `
        $PythonTemp `
        -Directory |
        Select-Object -First 1

if (!$ExtractedPython) {
    throw "Could not locate extracted Python."
}

Get-ChildItem `
    $ExtractedPython.FullName `
    -Force |
    ForEach-Object {

        Copy-Item `
            $_.FullName `
            $PythonDir `
            -Recurse `
            -Force
    }

Remove-Item `
    $PythonTemp `
    -Recurse `
    -Force

Remove-Item `
    $PythonArchive `
    -Force

$PythonExe =
    Join-Path $PythonDir "python.exe"

if (!(Test-Path $PythonExe)) {
    throw "Bundled Python was not created."
}

& $PythonExe --version

if ($LASTEXITCODE -ne 0) {
    throw "Bundled Python failed."
}

# ============================================================
# PYTHON DEPENDENCIES
# ============================================================

Write-Host ""
Write-Host "[7/10] Installing Python dependencies..."

& $PythonExe `
    -m pip install `
    --upgrade pip `
    --disable-pip-version-check

if ($LASTEXITCODE -ne 0) {
    throw "pip upgrade failed."
}

& $PythonExe `
    -m pip install `
    requests `
    pyelftools `
    --disable-pip-version-check

if ($LASTEXITCODE -ne 0) {
    throw "Python dependencies failed."
}

# ============================================================
# COPY COMPILER ENVIRONMENT
# ============================================================

Write-Host ""
Write-Host "[8/10] Configuring bundled compiler..."

$env:PATH =
    "$CompilerBin;$env:PATH"

$env:CC =
    $Clang

$env:CXX =
    $ClangXX

if (Test-Path $LLVMAr) {
    $env:AR = $LLVMAr
}

if (Test-Path $LLVMTar) {
    $env:RANLIB = $LLVMTar
}

Write-Host ""
Write-Host "CC:"
Write-Host $env:CC

Write-Host ""
Write-Host "CXX:"
Write-Host $env:CXX

Write-Host ""
Write-Host "Testing compiler..."

& $Clang --version

if ($LASTEXITCODE -ne 0) {
    throw "Bundled clang failed."
}

& $ClangXX --version

if ($LASTEXITCODE -ne 0) {
    throw "Bundled clang++ failed."
}

# ============================================================
# INITIALIZE BLUTTER
# ============================================================

Write-Host ""
Write-Host "[9/10] Initializing Blutter..."

$InitScript =
    Join-Path $Package "scripts\init_env_win.py"

if (!(Test-Path $InitScript)) {
    throw "init_env_win.py not found."
}

Push-Location $Package

try {

    & $PythonExe `
        $InitScript

    $InitExitCode =
        $LASTEXITCODE

    if ($InitExitCode -ne 0) {
        throw `
            "init_env_win.py failed with exit code $InitExitCode."
    }

}
finally {

    Pop-Location
}

# ============================================================
# VERIFY PACKAGE
# ============================================================

Write-Host ""
Write-Host "[10/10] Verifying package..."

$RequiredFiles = @(
    "$Package\blutter.exe"
    "$Package\blutter.py"
    "$Package\python\python.exe"
    "$Package\tools\llvm-mingw\bin\clang.exe"
    "$Package\tools\llvm-mingw\bin\clang++.exe"
)

foreach ($File in $RequiredFiles) {

    if (!(Test-Path $File)) {

        Write-Host ""
        Write-Host "MISSING:"
        Write-Host $File

        throw "Required package file is missing."
    }
}

$RequiredDirectories = @(
    "$Package\blutter"
    "$Package\scripts"
    "$Package\tools\llvm-mingw"
)

foreach ($Directory in $RequiredDirectories) {

    if (!(Test-Path $Directory)) {
        throw `
            "Required directory is missing: $Directory"
    }
}

Write-Host ""
Write-Host "============================================================"
Write-Host "                    BUILD SUCCESSFUL"
Write-Host "============================================================"
Write-Host ""

Write-Host "Executable:"
Write-Host $LauncherExe

Write-Host ""
Write-Host "Python:"
Write-Host $PythonExe

Write-Host ""
Write-Host "Compiler:"
Write-Host $CompilerBin

Write-Host ""
Write-Host "Package:"
Write-Host $Package

Write-Host ""
Write-Host "Usage:"
Write-Host ""
Write-Host "  blutter.exe libapp.so output"
Write-Host ""
