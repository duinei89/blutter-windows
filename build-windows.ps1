$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot
$Dist = Join-Path $Root "dist"
$Package = Join-Path $Dist "blutter"

$LauncherSource = Join-Path $Root "launcher\launcher.cpp"
$LauncherExe = Join-Path $Package "blutter.exe"

Write-Host ""
Write-Host "============================================================"
Write-Host "              BLUTTER WINDOWS BUILD"
Write-Host "============================================================"
Write-Host ""


# ============================================================
# 1. CLEAN
# ============================================================

Write-Host "[1/8] Cleaning distribution..."

if (Test-Path $Dist) {
    Remove-Item $Dist -Recurse -Force
}

New-Item `
    -ItemType Directory `
    -Path $Package `
    -Force | Out-Null


# ============================================================
# 2. VERIFY MSVC
# ============================================================

Write-Host ""
Write-Host "[2/8] Checking MSVC..."

$cl = Get-Command cl.exe -ErrorAction SilentlyContinue

if (!$cl) {
    throw "cl.exe was not found. MSVC environment is not initialized."
}

Write-Host "cl.exe:"
Write-Host $cl.Source


# ============================================================
# 3. BUILD NATIVE LAUNCHER
# ============================================================

Write-Host ""
Write-Host "[3/8] Building blutter.exe..."

if (!(Test-Path $LauncherSource)) {
    throw "Launcher source not found: $LauncherSource"
}

if (Test-Path $LauncherExe) {
    Remove-Item $LauncherExe -Force
}

Write-Host ""
Write-Host "Source:"
Write-Host $LauncherSource

Write-Host ""
Write-Host "Output:"
Write-Host $LauncherExe

Write-Host ""
Write-Host "Compiling..."

$CompileCommand = @"
cl.exe /nologo /std:c++17 /O2 /EHsc /MT /DUNICODE /D_UNICODE /Fe:"$LauncherExe" "$LauncherSource" /link /SUBSYSTEM:CONSOLE
"@

Write-Host $CompileCommand
Write-Host ""

cmd.exe /d /s /c $CompileCommand

$CompileExitCode = $LASTEXITCODE

Write-Host ""
Write-Host "MSVC exit code: $CompileExitCode"

if ($CompileExitCode -ne 0) {
    throw "launcher.cpp compilation failed with exit code $CompileExitCode."
}

if (!(Test-Path $LauncherExe)) {
    throw "MSVC succeeded but blutter.exe was not created."
}

Write-Host "Native launcher built successfully."


# ============================================================
# 4. COPY BLUTTER SOURCE
# ============================================================

Write-Host ""
Write-Host "[4/8] Copying Blutter source..."

$Files = @(
    "blutter.py",
    "dartvm_fetch_build.py",
    "extract_dart_info.py",
    "README.md",
    "LICENSE"
)

foreach ($File in $Files) {

    $Source = Join-Path $Root $File

    if (Test-Path $Source) {

        Copy-Item `
            $Source `
            $Package `
            -Force

        Write-Host "Copied: $File"
    }
}

$Directories = @(
    "blutter",
    "scripts"
)

foreach ($Directory in $Directories) {

    $Source = Join-Path $Root $Directory
    $Destination = Join-Path $Package $Directory

    if (!(Test-Path $Source)) {
        throw "Required directory missing: $Source"
    }

    Copy-Item `
        $Source `
        $Destination `
        -Recurse `
        -Force

    Write-Host "Copied: $Directory"
}


# ============================================================
# 5. DOWNLOAD STANDALONE PYTHON
# ============================================================

Write-Host ""
Write-Host "[5/8] Downloading standalone Python..."

$PythonDir = Join-Path $Package "python"

New-Item `
    -ItemType Directory `
    -Path $PythonDir `
    -Force | Out-Null


$Headers = @{
    "User-Agent" = "blutter-windows-builder"
    "Accept" = "application/vnd.github+json"
}

$PythonApi = `
    "https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest"

Write-Host "Querying:"
Write-Host $PythonApi

$PythonRelease = Invoke-RestMethod `
    -Uri $PythonApi `
    -Headers $Headers `
    -Method Get


Write-Host ""
Write-Host "Latest standalone Python release:"
Write-Host $PythonRelease.tag_name


$PythonAsset = $PythonRelease.assets |
    Where-Object {
        $_.name -match `
        "^cpython-3\.12\.[0-9]+\+.*-x86_64-pc-windows-msvc-install_only\.tar\.gz$"
    } |
    Select-Object -First 1


if (!$PythonAsset) {

    Write-Host ""
    Write-Host "Available x64 Windows Python 3.12 assets:"
    Write-Host ""

    $PythonRelease.assets |
        Where-Object {
            $_.name -match `
            "cpython-3\.12.*x86_64-pc-windows-msvc"
        } |
        ForEach-Object {
            Write-Host $_.name
        }

    throw "Could not find CPython 3.12 Windows x64 install_only archive."
}


Write-Host ""
Write-Host "Selected Python:"
Write-Host $PythonAsset.name
Write-Host ""


$PythonArchive = Join-Path `
    $env:TEMP `
    "blutter-python.tar.gz"


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

if (!(Test-Path $PythonArchive)) {
    throw "Python archive was not downloaded."
}


# ============================================================
# EXTRACT PYTHON
# ============================================================

Write-Host ""
Write-Host "Extracting Python..."

$PythonTemp = Join-Path `
    $env:TEMP `
    "blutter-python-extract"

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


# ============================================================
# FLATTEN PYTHON DIRECTORY
# ============================================================

Write-Host ""
Write-Host "Installing Python into package..."

$ExtractedPythonRoot = Get-ChildItem `
    $PythonTemp `
    -Directory |
    Select-Object -First 1


if (!$ExtractedPythonRoot) {
    throw "Could not find extracted Python directory."
}


Write-Host "Extracted root:"
Write-Host $ExtractedPythonRoot.FullName


# Copy the CONTENTS of the extracted directory into:
#
# dist\blutter\python\
#
# instead of creating:
#
# dist\blutter\python\python\

Get-ChildItem `
    $ExtractedPythonRoot.FullName `
    -Force |
    ForEach-Object {

        Copy-Item `
            $_.FullName `
            $PythonDir `
            -Recurse `
            -Force
    }


# Cleanup temporary files

Remove-Item `
    $PythonTemp `
    -Recurse `
    -Force

Remove-Item `
    $PythonArchive `
    -Force


# ============================================================
# FIND PYTHON
# ============================================================

$PythonExe = Join-Path `
    $PythonDir `
    "python.exe"


if (!(Test-Path $PythonExe)) {

    Write-Host ""
    Write-Host "Python package contents:"
    
    Get-ChildItem `
        $PythonDir `
        -Recurse `
        -File |
        Select-Object FullName |
        Format-Table -AutoSize

    throw "python.exe was not installed at $PythonExe"
}


Write-Host ""
Write-Host "Bundled Python:"
Write-Host $PythonExe
Write-Host ""

& $PythonExe --version

if ($LASTEXITCODE -ne 0) {
    throw "Bundled Python failed to execute."
}


# ============================================================
# 6. PYTHON DEPENDENCIES
# ============================================================

Write-Host ""
Write-Host "[6/8] Installing Python dependencies..."

& $PythonExe `
    -m pip install `
    --upgrade pip

if ($LASTEXITCODE -ne 0) {
    throw "pip upgrade failed."
}


& $PythonExe `
    -m pip install `
    requests `
    pyelftools

if ($LASTEXITCODE -ne 0) {
    throw "Python dependency installation failed."
}


# ============================================================
# 7. INITIALIZE BLUTTER
# ============================================================

Write-Host ""
Write-Host "[7/8] Initializing Blutter..."

$InitScript = Join-Path `
    $Package `
    "scripts\init_env_win.py"


if (!(Test-Path $InitScript)) {
    throw "init_env_win.py was not found."
}


Push-Location $Package

try {

    & $PythonExe `
        $InitScript

    $InitExitCode = $LASTEXITCODE

    if ($InitExitCode -ne 0) {
        throw "init_env_win.py failed with exit code $InitExitCode."
    }

}
finally {

    Pop-Location
}


# ============================================================
# 8. VERIFY PACKAGE
# ============================================================

Write-Host ""
Write-Host "[8/8] Verifying package..."

$RequiredFiles = @(
    "$Package\blutter.exe",
    "$Package\blutter.py",
    "$Package\python\python.exe"
)

foreach ($RequiredFile in $RequiredFiles) {

    if (!(Test-Path $RequiredFile)) {

        Write-Host ""
        Write-Host "MISSING:"
        Write-Host $RequiredFile

        throw "Required package file is missing."
    }
}


$RequiredDirectories = @(
    "$Package\blutter",
    "$Package\scripts"
)

foreach ($RequiredDirectory in $RequiredDirectories) {

    if (!(Test-Path $RequiredDirectory)) {

        throw "Required package directory is missing: $RequiredDirectory"
    }
}


# ============================================================
# FINAL PACKAGE INFORMATION
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "                 BUILD SUCCESSFUL"
Write-Host "============================================================"
Write-Host ""

Write-Host "Executable:"
Write-Host $LauncherExe

Write-Host ""
Write-Host "Python:"
Write-Host $PythonExe

Write-Host ""
Write-Host "Package:"
Write-Host $Package

Write-Host ""
Write-Host "Final layout:"
Write-Host ""

Get-ChildItem `
    $Package `
    -Directory |
    Select-Object Name |
    Format-Table -AutoSize

Write-Host ""
Write-Host "Usage:"
Write-Host ""
Write-Host "  blutter.exe libapp.so output"
Write-Host ""

Write-Host "============================================================"
