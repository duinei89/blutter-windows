$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot
$Dist = Join-Path $Root "dist"
$Package = Join-Path $Dist "blutter"

$LauncherSource = Join-Path $Root "launcher\launcher.cpp"
$LauncherExe = Join-Path $Package "blutter.exe"

Write-Host ""
Write-Host "============================================================"
Write-Host "              BLUTTER WINDOWS BUILDER"
Write-Host "============================================================"
Write-Host ""

# ============================================================
# 1. CLEAN
# ============================================================

Write-Host "[1/10] Cleaning..."

if (Test-Path $Dist) {
    Remove-Item $Dist -Recurse -Force
}

New-Item `
    -ItemType Directory `
    -Path $Package `
    -Force | Out-Null


# ============================================================
# 2. CHECK MSVC
# ============================================================

Write-Host "[2/10] Checking MSVC..."

$cl = Get-Command cl.exe -ErrorAction SilentlyContinue

if (!$cl) {
    throw "MSVC compiler cl.exe was not found."
}

Write-Host "MSVC:"
cl.exe 2>&1 | Select-Object -First 5


# ============================================================
# 3. BUILD NATIVE LAUNCHER
# ============================================================

Write-Host ""
Write-Host "[3/10] Building native blutter.exe..."

if (!(Test-Path $LauncherSource)) {
    throw "Launcher source not found: $LauncherSource"
}

Write-Host ""
Write-Host "Source:"
Write-Host $LauncherSource

Write-Host ""
Write-Host "Output:"
Write-Host $LauncherExe

# IMPORTANT:
# /Fe specifies the executable output.
# Do NOT additionally use /OUT.

cl.exe `
    /nologo `
    /std:c++20 `
    /O2 `
    /EHsc `
    /MT `
    /DUNICODE `
    /D_UNICODE `
    /Fe:"$LauncherExe" `
    "$LauncherSource" `
    /link `
    /SUBSYSTEM:CONSOLE

if ($LASTEXITCODE -ne 0) {
    throw "Native launcher compilation failed."
}

if (!(Test-Path $LauncherExe)) {
    throw "blutter.exe was not generated."
}

Write-Host ""
Write-Host "Native launcher created successfully:"
Write-Host $LauncherExe


# ============================================================
# 4. COPY BLUTTER SOURCE
# ============================================================

Write-Host ""
Write-Host "[4/10] Copying Blutter source..."

$Files = @(
    "blutter.py",
    "dartvm_fetch_build.py",
    "extract_dart_info.py",
    "LICENSE",
    "README.md"
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
    else {
        Write-Host "Optional file missing: $File"
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
        throw "Required directory missing: $Directory"
    }

    Copy-Item `
        $Source `
        $Destination `
        -Recurse `
        -Force

    Write-Host "Copied directory: $Directory"
}


# ============================================================
# 5. DOWNLOAD STANDALONE PYTHON
# ============================================================

Write-Host ""
Write-Host "[5/10] Downloading standalone Python..."

$PythonDir = Join-Path $Package "python"

New-Item `
    -ItemType Directory `
    -Path $PythonDir `
    -Force | Out-Null

$ApiUrl = `
    "https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest"

$Headers = @{
    "User-Agent" = "blutter-windows-builder"
}

Write-Host ""
Write-Host "Querying:"
Write-Host $ApiUrl

$Release = Invoke-RestMethod `
    -Uri $ApiUrl `
    -Headers $Headers `
    -Method Get


# Current releases use names such as:
#
# cpython-3.12.13+20260807-x86_64-pc-windows-msvc-install_only.tar.gz
#

$Asset = $Release.assets |
    Where-Object {
        $_.name -match `
        "^cpython-3\.12\.[0-9]+\+.*-x86_64-pc-windows-msvc-install_only\.tar\.gz$"
    } |
    Select-Object -First 1


if (!$Asset) {

    Write-Host ""
    Write-Host "Available x64 Windows Python assets:"

    $Release.assets |
        Where-Object {
            $_.name -match `
            "cpython-3\.12.*x86_64-pc-windows-msvc"
        } |
        ForEach-Object {
            Write-Host $_.name
        }

    throw `
        "Could not find CPython 3.12 Windows x64 install_only archive."
}


Write-Host ""
Write-Host "Selected Python:"
Write-Host $Asset.name


$PythonArchive = Join-Path `
    $env:TEMP `
    "blutter-python.tar.gz"

if (Test-Path $PythonArchive) {
    Remove-Item `
        $PythonArchive `
        -Force
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
    "$($Asset.browser_download_url)"

if ($LASTEXITCODE -ne 0) {
    throw "Python download failed."
}


Write-Host ""
Write-Host "Extracting Python..."

tar.exe `
    -xzf `
    "$PythonArchive" `
    -C `
    "$PythonDir"

if ($LASTEXITCODE -ne 0) {
    throw "Python extraction failed."
}

Remove-Item `
    $PythonArchive `
    -Force


$PythonExe = Get-ChildItem `
    $PythonDir `
    -Filter "python.exe" `
    -Recurse `
    -File |
    Select-Object -First 1


if (!$PythonExe) {
    throw "Bundled python.exe was not found."
}


Write-Host ""
Write-Host "Bundled Python:"
Write-Host $PythonExe.FullName

& $PythonExe.FullName --version

if ($LASTEXITCODE -ne 0) {
    throw "Bundled Python failed to execute."
}


# ============================================================
# 6. PYTHON DEPENDENCIES
# ============================================================

Write-Host ""
Write-Host "[6/10] Installing Python dependencies..."

& $PythonExe.FullName `
    -m pip install `
    --upgrade pip

if ($LASTEXITCODE -ne 0) {
    throw "pip upgrade failed."
}


& $PythonExe.FullName `
    -m pip install `
    requests `
    pyelftools

if ($LASTEXITCODE -ne 0) {
    throw "Python dependencies failed."
}


# ============================================================
# 7. INITIALIZE BLUTTER
# ============================================================

Write-Host ""
Write-Host "[7/10] Initializing Blutter environment..."

$InitScript = Join-Path `
    $Package `
    "scripts\init_env_win.py"


if (!(Test-Path $InitScript)) {
    throw "init_env_win.py was not found."
}


Push-Location $Package

try {

    & $PythonExe.FullName `
        $InitScript

    if ($LASTEXITCODE -ne 0) {
        throw "init_env_win.py failed."
    }

}
finally {

    Pop-Location
}


# ============================================================
# 8. PREPARE TOOLS
# ============================================================

Write-Host ""
Write-Host "[8/10] Preparing bundled tools..."

$Tools = Join-Path $Package "tools"

New-Item `
    -ItemType Directory `
    -Path $Tools `
    -Force | Out-Null


# ------------------------------------------------------------
# Ninja
# ------------------------------------------------------------

Write-Host ""
Write-Host "Downloading Ninja..."

$NinjaApi =
    "https://api.github.com/repos/ninja-build/ninja/releases/latest"

$NinjaRelease = Invoke-RestMethod `
    -Uri $NinjaApi `
    -Headers $Headers


$NinjaAsset = $NinjaRelease.assets |
    Where-Object {
        $_.name -eq "ninja-win.zip"
    } |
    Select-Object -First 1


if (!$NinjaAsset) {
    throw "Could not find ninja-win.zip."
}


$NinjaZip = Join-Path `
    $env:TEMP `
    "blutter-ninja.zip"


curl.exe `
    --location `
    --fail `
    --retry 10 `
    --retry-delay 5 `
    --retry-all-errors `
    --output "$NinjaZip" `
    "$($NinjaAsset.browser_download_url)"

if ($LASTEXITCODE -ne 0) {
    throw "Ninja download failed."
}


$NinjaDir = Join-Path `
    $Tools `
    "ninja"


New-Item `
    -ItemType Directory `
    -Path $NinjaDir `
    -Force | Out-Null


Expand-Archive `
    -Path $NinjaZip `
    -DestinationPath $NinjaDir `
    -Force


Remove-Item `
    $NinjaZip `
    -Force


# ------------------------------------------------------------
# CMake
# ------------------------------------------------------------

Write-Host ""
Write-Host "Downloading CMake..."

$CMakeApi =
    "https://api.github.com/repos/Kitware/CMake/releases/latest"

$CMakeRelease = Invoke-RestMethod `
    -Uri $CMakeApi `
    -Headers $Headers


$CMakeAsset = $CMakeRelease.assets |
    Where-Object {
        $_.name -match `
        "cmake-.*-windows-x86_64\.zip$"
    } |
    Select-Object -First 1


if (!$CMakeAsset) {
    throw "Could not find Windows x64 CMake ZIP."
}


$CMakeZip = Join-Path `
    $env:TEMP `
    "blutter-cmake.zip"


curl.exe `
    --location `
    --fail `
    --retry 10 `
    --retry-delay 5 `
    --retry-all-errors `
    --output "$CMakeZip" `
    "$($CMakeAsset.browser_download_url)"

if ($LASTEXITCODE -ne 0) {
    throw "CMake download failed."
}


$CMakeExtract = Join-Path `
    $env:TEMP `
    "blutter-cmake"


if (Test-Path $CMakeExtract) {
    Remove-Item `
        $CMakeExtract `
        -Recurse `
        -Force
}


Expand-Archive `
    -Path $CMakeZip `
    -DestinationPath $CMakeExtract `
    -Force


Remove-Item `
    $CMakeZip `
    -Force


$CMakeRoot = Get-ChildItem `
    $CMakeExtract `
    -Directory |
    Select-Object -First 1


if (!$CMakeRoot) {
    throw "CMake extraction failed."
}


$CMakeBinSource =
    Join-Path $CMakeRoot.FullName "bin"


if (!(Test-Path $CMakeBinSource)) {
    throw "CMake bin directory not found."
}


$CMakeBinDestination =
    Join-Path $Tools "cmake"


New-Item `
    -ItemType Directory `
    -Path $CMakeBinDestination `
    -Force | Out-Null


Copy-Item `
    "$CMakeBinSource\*" `
    $CMakeBinDestination `
    -Recurse `
    -Force


# ============================================================
# 9. TEST
# ============================================================

Write-Host ""
Write-Host "[9/10] Testing package..."

if (!(Test-Path $LauncherExe)) {
    throw "blutter.exe is missing."
}


if (!(Test-Path "$Package\python\python.exe")) {
    throw "Bundled Python is missing."
}


if (!(Test-Path "$Package\blutter.py")) {
    throw "blutter.py is missing."
}


Write-Host ""
Write-Host "Testing launcher..."

& $LauncherExe

# Exit code 1 is expected because no arguments were supplied.
# Any actual Windows process failure is handled separately.

Write-Host ""
Write-Host "Package contents:"
Write-Host ""

Get-ChildItem `
    $Package `
    -Recurse `
    -File |
    Select-Object FullName, Length |
    Format-Table -AutoSize


# ============================================================
# 10. DONE
# ============================================================

Write-Host ""
Write-Host "[10/10] Build complete."
Write-Host ""

Write-Host "Package:"
Write-Host $Package

Write-Host ""
Write-Host "Usage:"
Write-Host ""
Write-Host "  blutter.exe libapp.so output"
Write-Host ""

Write-Host "============================================================"
Write-Host "                    SUCCESS"
Write-Host "============================================================"
Write-Host ""
