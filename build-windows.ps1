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

Write-Host "MSVC:"
Write-Host $cl.Source
Write-Host ""


# ============================================================
# 3. BUILD NATIVE LAUNCHER
# ============================================================

Write-Host ""
Write-Host "[3/8] Building blutter.exe..."
Write-Host ""

if (!(Test-Path $LauncherSource)) {
    throw "Launcher source not found: $LauncherSource"
}

Write-Host "Source:"
Write-Host "  $LauncherSource"

Write-Host ""
Write-Host "Output:"
Write-Host "  $LauncherExe"

if (Test-Path $LauncherExe) {
    Remove-Item $LauncherExe -Force
}

Write-Host ""
Write-Host "Compiling..."
Write-Host ""

# IMPORTANT:
# launcher.cpp uses std::filesystem.
# Therefore C++17 or newer is required.
#
# Do NOT remove /std:c++17.

& cl.exe `
    /nologo `
    /std:c++17 `
    /O2 `
    /EHsc `
    /MT `
    /DUNICODE `
    /D_UNICODE `
    "/Fe:$LauncherExe" `
    "$LauncherSource" `
    /link `
    /SUBSYSTEM:CONSOLE

$CompileExitCode = $LASTEXITCODE

Write-Host ""
Write-Host "MSVC exit code: $CompileExitCode"
Write-Host ""

if ($CompileExitCode -ne 0) {
    throw "launcher.cpp compilation failed with exit code $CompileExitCode."
}

if (!(Test-Path $LauncherExe)) {
    throw "MSVC succeeded but blutter.exe was not created."
}

Write-Host "Launcher successfully created:"
Write-Host $LauncherExe


# ============================================================
# 4. COPY BLUTTER
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

        Write-Host "Copied $File"
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

    Write-Host "Copied $Directory"
}


# ============================================================
# 5. BUNDLED PYTHON
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

Write-Host "Querying Python release..."

$PythonRelease = Invoke-RestMethod `
    -Uri $PythonApi `
    -Headers $Headers `
    -Method Get

Write-Host "Release: $($PythonRelease.tag_name)"

# Current python-build-standalone naming:
#
# cpython-3.12.13+20260807-x86_64-pc-windows-msvc-install_only.tar.gz

$PythonAsset = $PythonRelease.assets |
    Where-Object {
        $_.name -match `
        "^cpython-3\.12\.[0-9]+\+.*-x86_64-pc-windows-msvc-install_only\.tar\.gz$"
    } |
    Select-Object -First 1

if (!$PythonAsset) {

    Write-Host ""
    Write-Host "Available Python 3.12 x64 Windows assets:"

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
Write-Host "Selected:"
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
    throw "Bundled Python failed."
}


# ============================================================
# 6. INSTALL PYTHON DEPENDENCIES
# ============================================================

Write-Host ""
Write-Host "[6/8] Installing Python dependencies..."

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
    throw "init_env_win.py not found."
}

Push-Location $Package

try {

    & $PythonExe.FullName `
        $InitScript

    $InitExitCode = $LASTEXITCODE

    if ($InitExitCode -ne 0) {
        throw "Blutter initialization failed with exit code $InitExitCode."
    }

}
finally {

    Pop-Location
}


# ============================================================
# 8. PACKAGE / VERIFY
# ============================================================

Write-Host ""
Write-Host "[8/8] Verifying package..."

if (!(Test-Path $LauncherExe)) {
    throw "blutter.exe missing."
}

if (!(Test-Path "$Package\python\python.exe")) {
    throw "Bundled Python missing."
}

if (!(Test-Path "$Package\blutter.py")) {
    throw "blutter.py missing."
}

if (!(Test-Path "$Package\blutter")) {
    throw "blutter source directory missing."
}

if (!(Test-Path "$Package\scripts")) {
    throw "scripts directory missing."
}

Write-Host ""
Write-Host "============================================================"
Write-Host "                  BUILD SUCCESSFUL"
Write-Host "============================================================"
Write-Host ""

Write-Host "Executable:"
Get-Item $LauncherExe

Write-Host ""
Write-Host "Package:"
Write-Host $Package

Write-Host ""
Write-Host "Usage:"
Write-Host ""
Write-Host "  blutter.exe libapp.so output"
Write-Host ""

Write-Host "Package contents:"
Write-Host ""

Get-ChildItem `
    $Package `
    -Recurse `
    -File |
    Select-Object FullName, Length |
    Format-Table -AutoSize
