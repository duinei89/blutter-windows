$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot

$Dist = Join-Path $Root "dist"
$Package = Join-Path $Dist "blutter"

Write-Host ""
Write-Host "=================================================="
Write-Host "        BLUTTER WINDOWS BUILD"
Write-Host "=================================================="
Write-Host ""


# ==========================================================
# 1/8 CLEAN
# ==========================================================

Write-Host "[1/8] Cleaning distribution..."

if (Test-Path $Dist) {
    Remove-Item `
        $Dist `
        -Recurse `
        -Force
}

New-Item `
    -ItemType Directory `
    -Path $Package `
    -Force | Out-Null


# ==========================================================
# 2/8 BUILD SELF-CONTAINED BLUTTER.EXE
# ==========================================================

Write-Host "[2/8] Building self-contained blutter.exe..."

$Project = Join-Path `
    $Root `
    "launcher\Blutter.Cli.csproj"

if (!(Test-Path $Project)) {
    throw "Blutter.Cli.csproj not found: $Project"
}

dotnet publish `
    $Project `
    -c Release `
    -r win-x64 `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:PublishTrimmed=false `
    -p:EnableCompressionInSingleFile=true `
    -o $Package

if ($LASTEXITCODE -ne 0) {
    throw "Failed to build blutter.exe"
}


# ==========================================================
# VERIFY EXECUTABLE
# ==========================================================

$Exe = Join-Path `
    $Package `
    "blutter.exe"

if (!(Test-Path $Exe)) {
    throw "blutter.exe was not generated."
}

Write-Host ""
Write-Host "blutter.exe created:"
Get-Item $Exe

Write-Host ""
Write-Host "blutter.exe size:"
Write-Host "$((Get-Item $Exe).Length) bytes"


# ==========================================================
# 3/8 COPY BLUTTER SOURCE
# ==========================================================

Write-Host ""
Write-Host "[3/8] Copying Blutter source..."

$SourceFiles = @(
    "blutter.py",
    "pubspec.yaml",
    "README.md",
    "LICENSE"
)

foreach ($file in $SourceFiles) {

    $source = Join-Path `
        $Root `
        $file

    if (Test-Path $source) {

        Write-Host "Copying $file"

        Copy-Item `
            $source `
            $Package `
            -Force
    }
}


# ==========================================================
# 4/8 COPY BLUTTER DIRECTORIES
# ==========================================================

Write-Host ""
Write-Host "[4/8] Copying Blutter directories..."

$Directories = @(
    "blutter",
    "scripts",
    "bin",
    "external"
)

foreach ($directory in $Directories) {

    $source = Join-Path `
        $Root `
        $directory

    if (Test-Path $source) {

        $destination = Join-Path `
            $Package `
            $directory

        Write-Host "Copying $directory"

        Copy-Item `
            $source `
            $destination `
            -Recurse `
            -Force
    }
}


# ==========================================================
# 5/8 DOWNLOAD STANDALONE PYTHON
# ==========================================================

Write-Host ""
Write-Host "[5/8] Downloading standalone Python..."

$PythonDir = Join-Path `
    $Package `
    "python"

if (Test-Path $PythonDir) {

    Remove-Item `
        $PythonDir `
        -Recurse `
        -Force
}

New-Item `
    -ItemType Directory `
    -Path $PythonDir `
    -Force | Out-Null


# ----------------------------------------------------------
# Python Build Standalone API
# ----------------------------------------------------------

$ReleaseApi = `
    "https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest"

Write-Host ""
Write-Host "Querying:"
Write-Host $ReleaseApi
Write-Host ""

$headers = @{
    "User-Agent" = "blutter-windows-builder"
}

$Release = Invoke-RestMethod `
    -Uri $ReleaseApi `
    -Headers $headers `
    -Method Get

if (!$Release) {
    throw "Unable to query python-build-standalone releases."
}

Write-Host "Latest standalone Python release:"
Write-Host $Release.tag_name
Write-Host ""


# ----------------------------------------------------------
# Find CPython 3.12 Windows x64 install_only
# ----------------------------------------------------------

$Asset = $Release.assets |
    Where-Object {
        $_.name -match `
        "^cpython-3\.12\.[0-9]+\+.*-x86_64-pc-windows-msvc-install_only\.tar\.gz$"
    } |
    Select-Object -First 1


if (!$Asset) {

    Write-Host ""
    Write-Host "Available CPython 3.12 Windows x64 assets:"
    Write-Host ""

    $Release.assets |
        Where-Object {
            $_.name -match `
            "^cpython-3\.12.*x86_64-pc-windows-msvc"
        } |
        ForEach-Object {
            Write-Host $_.name
        }

    throw `
        "Could not find CPython 3.12 Windows x64 install_only archive."
}


Write-Host ""
Write-Host "Selected Python asset:"
Write-Host $Asset.name
Write-Host ""

Write-Host "Download URL:"
Write-Host $Asset.browser_download_url
Write-Host ""


# ----------------------------------------------------------
# Download Python
# ----------------------------------------------------------

$PythonArchive = Join-Path `
    $env:TEMP `
    "blutter-python.tar.gz"

if (Test-Path $PythonArchive) {

    Remove-Item `
        $PythonArchive `
        -Force
}

& curl.exe `
    --location `
    --fail `
    --retry 10 `
    --retry-delay 5 `
    --retry-all-errors `
    --connect-timeout 30 `
    --max-time 600 `
    --output "$PythonArchive" `
    "$($Asset.browser_download_url)"

if ($LASTEXITCODE -ne 0) {

    throw `
        "Standalone Python download failed. curl exit code: $LASTEXITCODE"
}

if (!(Test-Path $PythonArchive)) {
    throw "Python archive was not downloaded."
}


$PythonArchiveSize = `
    (Get-Item $PythonArchive).Length

Write-Host ""
Write-Host "Python archive size:"
Write-Host "$PythonArchiveSize bytes"
Write-Host ""

if ($PythonArchiveSize -lt 1000000) {

    throw `
        "Python archive is suspiciously small."
}


# ==========================================================
# EXTRACT PYTHON
# ==========================================================

Write-Host "Extracting standalone Python..."

tar.exe `
    -xzf `
    "$PythonArchive" `
    -C `
    "$PythonDir"

if ($LASTEXITCODE -ne 0) {
    throw "Failed to extract standalone Python."
}

Remove-Item `
    $PythonArchive `
    -Force


# ----------------------------------------------------------
# Find python.exe
# ----------------------------------------------------------

$PythonExe = Get-ChildItem `
    $PythonDir `
    -Filter "python.exe" `
    -Recurse `
    -File |
    Select-Object -First 1

if (!$PythonExe) {
    throw "python.exe was not found inside standalone Python."
}

$PythonRoot = $PythonExe.Directory.FullName

Write-Host ""
Write-Host "Standalone Python:"
Write-Host $PythonRoot
Write-Host ""


# ==========================================================
# VERIFY PYTHON
# ==========================================================

Write-Host "Python version:"

& $PythonExe.FullName --version

if ($LASTEXITCODE -ne 0) {
    throw "Standalone Python does not work."
}


# ==========================================================
# INSTALL PYTHON DEPENDENCIES
# ==========================================================

Write-Host ""
Write-Host "Installing Python dependencies..."

& $PythonExe.FullName `
    -m pip install `
    --upgrade pip

if ($LASTEXITCODE -ne 0) {
    throw "Failed to upgrade pip."
}

& $PythonExe.FullName `
    -m pip install `
    requests `
    pyelftools

if ($LASTEXITCODE -ne 0) {
    throw "Failed to install Python dependencies."
}


# ==========================================================
# CREATE PYTHON LAUNCHER
# ==========================================================

Write-Host ""
Write-Host "Creating Python launcher..."

$Launcher = Join-Path `
    $Package `
    "run_blutter.py"

$LauncherContent = @'
import os
import sys
import runpy

ROOT = os.path.dirname(os.path.abspath(__file__))

sys.path.insert(0, ROOT)

SCRIPT = os.path.join(ROOT, "blutter.py")

if not os.path.isfile(SCRIPT):
    raise FileNotFoundError(
        f"Blutter Python entry point not found: {SCRIPT}"
    )

runpy.run_path(
    SCRIPT,
    run_name="__main__"
)
'@

Set-Content `
    -Path $Launcher `
    -Value $LauncherContent `
    -Encoding UTF8


# ==========================================================
# CREATE ENVIRONMENT CONFIG
# ==========================================================

Write-Host ""
Write-Host "Creating environment configuration..."

$Config = Join-Path `
    $Package `
    "blutter-env.json"

$ConfigContent = @{
    python   = "python\python.exe"
    launcher = "run_blutter.py"
} |
    ConvertTo-Json `
        -Depth 5

Set-Content `
    -Path $Config `
    -Value $ConfigContent `
    -Encoding UTF8


# ==========================================================
# VERIFY PACKAGE CONTENT
# ==========================================================

Write-Host ""
Write-Host "=================================================="
Write-Host "VERIFYING PACKAGE"
Write-Host "=================================================="
Write-Host ""

Write-Host "Executable:"
Get-Item $Exe

Write-Host ""
Write-Host "Python:"
Get-Item $PythonExe.FullName

Write-Host ""
Write-Host "Python launcher:"
Get-Item $Launcher

Write-Host ""
Write-Host "Blutter source:"

$BlutterPy = Join-Path `
    $Package `
    "blutter.py"

if (!(Test-Path $BlutterPy)) {
    throw "blutter.py is missing from package."
}

Get-Item $BlutterPy


# ==========================================================
# PACKAGE SIZE
# ==========================================================

Write-Host ""
Write-Host "Calculating package size..."

$PackageSize = Get-ChildItem `
    $Package `
    -Recurse `
    -File |
    Measure-Object `
        -Property Length `
        -Sum

Write-Host ""
Write-Host "Package size:"
Write-Host "$($PackageSize.Sum) bytes"


# ==========================================================
# FINAL
# ==========================================================

Write-Host ""
Write-Host "=================================================="
Write-Host "        BUILD COMPLETE"
Write-Host "=================================================="
Write-Host ""

Write-Host "Package:"
Write-Host $Package

Write-Host ""

Write-Host "Executable:"
Write-Host $Exe

Write-Host ""

Write-Host "Run:"
Write-Host "blutter.exe libapp.so output"

Write-Host ""
