$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot

$Dist = Join-Path $Root "dist\blutter"

Write-Host ""
Write-Host "=============================================="
Write-Host "       BLUTTER WINDOWS BUILD"
Write-Host "=============================================="
Write-Host ""

# ------------------------------------------------
# Clean
# ------------------------------------------------

Write-Host "[1/8] Cleaning distribution..."

if (Test-Path $Dist) {
    Remove-Item $Dist -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $Dist | Out-Null


# ------------------------------------------------
# Build native Windows CLI
# ------------------------------------------------

Write-Host "[2/8] Building blutter.exe..."

dotnet publish `
    "$Root\launcher\Blutter.Cli.csproj" `
    --configuration Release `
    --runtime win-x64 `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:PublishTrimmed=false `
    -o "$Dist"


# ------------------------------------------------
# Copy Blutter source
# ------------------------------------------------

Write-Host "[3/8] Copying Blutter source..."

$BlutterDist = Join-Path $Dist "blutter"

New-Item `
    -ItemType Directory `
    -Force `
    -Path $BlutterDist | Out-Null


$Files = @(
    "blutter.py",
    "dartvm_fetch_build.py",
    "extract_dart_info.py"
)

foreach ($File in $Files) {

    $Source = Join-Path $Root $File

    if (!(Test-Path $Source)) {
        throw "Required file missing: $Source"
    }

    Copy-Item `
        $Source `
        (Join-Path $BlutterDist $File) `
        -Force
}


# ------------------------------------------------
# Copy directories
# ------------------------------------------------

Write-Host "[4/8] Copying Blutter directories..."

$Directories = @(
    "blutter",
    "scripts",
    "bin",
    "packages",
    "external"
)

foreach ($Directory in $Directories) {

    $Source = Join-Path $Root $Directory

    if (Test-Path $Source) {

        Copy-Item `
            $Source `
            (Join-Path $BlutterDist $Directory) `
            -Recurse `
            -Force

    }
}


# ------------------------------------------------
# Download standalone Python
# ------------------------------------------------

Write-Host "[5/8] Downloading standalone Python..."

$PythonDir = Join-Path $Dist "runtime\python"

New-Item `
    -ItemType Directory `
    -Force `
    -Path $PythonDir | Out-Null


$PythonVersion = "3.12.10"
$PythonBuild = "20260718"

$PythonArchive = `
    "cpython-$PythonVersion+$PythonBuild" +
    "-x86_64-pc-windows-msvc-shared-install_only.tar.gz"

$PythonUrl = `
    "https://github.com/astral-sh/python-build-standalone/releases/" +
    "download/$PythonBuild/$PythonArchive"

$PythonTar = Join-Path `
    $env:TEMP `
    "python-blutter.tar.gz"

Write-Host "Downloading:"
Write-Host $PythonUrl

Invoke-WebRequest `
    -Uri $PythonUrl `
    -OutFile $PythonTar


# ------------------------------------------------
# Extract Python
# ------------------------------------------------

Write-Host "[6/8] Extracting Python..."

$PythonTemp = Join-Path `
    $env:TEMP `
    "blutter-python"

if (Test-Path $PythonTemp) {
    Remove-Item $PythonTemp -Recurse -Force
}

New-Item `
    -ItemType Directory `
    -Force `
    -Path $PythonTemp | Out-Null


tar `
    -xzf $PythonTar `
    -C $PythonTemp


$PythonRoot = Get-ChildItem `
    $PythonTemp `
    -Directory |
    Select-Object -First 1

if ($null -eq $PythonRoot) {
    throw "Could not find extracted Python directory."
}

Copy-Item `
    "$($PythonRoot.FullName)\*" `
    $PythonDir `
    -Recurse `
    -Force


# ------------------------------------------------
# Install Python packages into bundled runtime
# ------------------------------------------------

Write-Host "[7/8] Installing Python dependencies..."

$BundledPython = Join-Path `
    $PythonDir `
    "python.exe"

if (!(Test-Path $BundledPython)) {
    throw "Bundled Python executable was not found."
}

& $BundledPython `
    -m pip install `
    --upgrade `
    pyelftools `
    requests


# ------------------------------------------------
# Verify
# ------------------------------------------------

Write-Host "[8/8] Verifying package..."

$Cli = Join-Path `
    $Dist `
    "blutter.exe"

if (!(Test-Path $Cli)) {
    throw "blutter.exe was not generated."
}

Write-Host ""
Write-Host "Testing CLI..."
Write-Host ""

& $Cli --version

if ($LASTEXITCODE -ne 0) {
    throw "CLI version test failed."
}

& $Cli --help

if ($LASTEXITCODE -ne 0) {
    throw "CLI help test failed."
}


# ------------------------------------------------
# Create README
# ------------------------------------------------

@"
BLUTTER WINDOWS
===============

Usage:

    blutter.exe libapp.so output

IMPORTANT:

Place libflutter.so beside libapp.so.

Example:

    C:\APK\
        libapp.so
        libflutter.so

Then:

    blutter.exe C:\APK\libapp.so C:\APK\output


Requirements:

- Windows 10/11 x64
- Android ARM64 Flutter application
- libapp.so
- libflutter.so

The package contains its own Python runtime.
No Python installation is required.
No Visual Studio installation is required.
No CMake installation is required.
"@ | Set-Content `
    (Join-Path $Dist "README.txt") `
    -Encoding UTF8


Write-Host ""
Write-Host "=============================================="
Write-Host "             BUILD SUCCESSFUL"
Write-Host "=============================================="
Write-Host ""

Get-ChildItem `
    $Dist `
    -Recurse |
    Select-Object FullName, Length |
    Format-Table -AutoSize
