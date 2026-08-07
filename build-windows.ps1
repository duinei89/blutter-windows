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

Write-Host ""
Write-Host "[2/10] Checking MSVC..."
Write-Host ""

$clCommand = Get-Command cl.exe -ErrorAction SilentlyContinue

if (!$clCommand) {
    throw "MSVC cl.exe was not found. The Visual C++ environment is not initialized."
}

Write-Host "MSVC location:"
Write-Host $clCommand.Source
Write-Host ""

Write-Host "MSVC version:"
cl.exe 2>&1 | Select-Object -First 5


# ============================================================
# 3. BUILD NATIVE LAUNCHER
# ============================================================

Write-Host ""
Write-Host "[3/10] Building native blutter.exe..."
Write-Host ""

if (!(Test-Path $LauncherSource)) {
    throw "Launcher source not found: $LauncherSource"
}

Write-Host "Source:"
Write-Host "  $LauncherSource"
Write-Host ""

Write-Host "Output:"
Write-Host "  $LauncherExe"
Write-Host ""

if (Test-Path $LauncherExe) {
    Remove-Item $LauncherExe -Force
}

Write-Host "Compiling launcher..."
Write-Host ""

$compileOutput = @()

& cl.exe `
    /nologo `
    /O2 `
    /EHsc `
    /MT `
    /DUNICODE `
    /D_UNICODE `
    "/Fe:$LauncherExe" `
    "$LauncherSource" `
    /link `
    /SUBSYSTEM:CONSOLE 2>&1 |
    Tee-Object -Variable compileOutput

$compileExitCode = $LASTEXITCODE

Write-Host ""
Write-Host "MSVC exit code: $compileExitCode"
Write-Host ""

if ($compileExitCode -ne 0) {

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "              MSVC COMPILATION FAILED"
    Write-Host "============================================================"
    Write-Host ""

    if ($compileOutput.Count -gt 0) {
        $compileOutput | ForEach-Object {
            Write-Host $_
        }
    }
    else {
        Write-Host "MSVC produced no diagnostic output."
    }

    Write-Host ""
    throw "Native launcher compilation failed with exit code $compileExitCode."
}

if (!(Test-Path $LauncherExe)) {
    throw "MSVC returned success, but blutter.exe was not generated."
}

Write-Host ""
Write-Host "============================================================"
Write-Host "              LAUNCHER BUILD SUCCESSFUL"
Write-Host "============================================================"
Write-Host ""

Get-Item $LauncherExe |
    Select-Object FullName, Length |
    Format-List


# ============================================================
# 4. COPY BLUTTER SOURCE
# ============================================================

Write-Host ""
Write-Host "[4/10] Copying Blutter source..."
Write-Host ""

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
Write-Host ""

$PythonDir = Join-Path $Package "python"

New-Item `
    -ItemType Directory `
    -Path $PythonDir `
    -Force | Out-Null


$ApiUrl = `
    "https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest"

$Headers = @{
    "User-Agent" = "blutter-windows-builder"
    "Accept"     = "application/vnd.github+json"
}


Write-Host "Querying:"
Write-Host $ApiUrl
Write-Host ""

$Release = Invoke-RestMethod `
    -Uri $ApiUrl `
    -Headers $Headers `
    -Method Get


Write-Host "Latest standalone Python release:"
Write-Host $Release.tag_name
Write-Host ""


# Match current x64 Windows CPython 3.12 install_only archives.
#
# Example:
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

    Write-Host "Available Windows x64 CPython 3.12 assets:"
    Write-Host ""

    $Release.assets |
        Where-Object {
            $_.name -match `
            "cpython-3\.12.*x86_64-pc-windows-msvc"
        } |
        ForEach-Object {
            Write-Host $_.name
        }

    throw "Could not find CPython 3.12 Windows x64 install_only archive."
}


Write-Host "Selected Python asset:"
Write-Host $Asset.name
Write-Host ""

$PythonArchive = Join-Path `
    $env:TEMP `
    "blutter-python.tar.gz"


if (Test-Path $PythonArchive) {
    Remove-Item $PythonArchive -Force
}


Write-Host "Downloading Python..."

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


if (!(Test-Path $PythonArchive)) {
    throw "Python archive was not downloaded."
}


Write-Host ""
Write-Host "Python archive size:"

(Get-Item $PythonArchive).Length


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
Write-Host ""

& $PythonExe.FullName --version


if ($LASTEXITCODE -ne 0) {
    throw "Bundled Python failed to execute."
}


# ============================================================
# 6. PYTHON DEPENDENCIES
# ============================================================

Write-Host ""
Write-Host "[6/10] Installing Python dependencies..."
Write-Host ""


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
Write-Host ""


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

    $InitExitCode = $LASTEXITCODE

    if ($InitExitCode -ne 0) {
        throw "init_env_win.py failed with exit code $InitExitCode."
    }

}
finally {

    Pop-Location
}


# ============================================================
# 8. PREPARE BUNDLED TOOLS
# ============================================================

Write-Host ""
Write-Host "[8/10] Preparing bundled tools..."
Write-Host ""


$Tools = Join-Path $Package "tools"

New-Item `
    -ItemType Directory `
    -Path $Tools `
    -Force | Out-Null


# ============================================================
# NINJA
# ============================================================

Write-Host ""
Write-Host "Downloading Ninja..."


$NinjaApi =
    "https://api.github.com/repos/ninja-build/ninja/releases/latest"


$NinjaRelease = Invoke-RestMethod `
    -Uri $NinjaApi `
    -Headers $Headers `
    -Method Get


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


if (Test-Path $NinjaZip) {
    Remove-Item $NinjaZip -Force
}


curl.exe `
    --location `
    --fail `
    --retry 10 `
    --retry-delay 5 `
    --retry-all-errors `
    --connect-timeout 30 `
    --max-time 600 `
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


# ============================================================
# CMAKE
# ============================================================

Write-Host ""
Write-Host "Downloading CMake..."


$CMakeApi =
    "https://api.github.com/repos/Kitware/CMake/releases/latest"


$CMakeRelease = Invoke-RestMethod `
    -Uri $CMakeApi `
    -Headers $Headers `
    -Method Get


$CMakeAsset = $CMakeRelease.assets |
    Where-Object {
        $_.name -match `
        "^cmake-.*-windows-x86_64\.zip$"
    } |
    Select-Object -First 1


if (!$CMakeAsset) {
    throw "Could not find Windows x64 CMake ZIP."
}


$CMakeZip = Join-Path `
    $env:TEMP `
    "blutter-cmake.zip"


if (Test-Path $CMakeZip) {
    Remove-Item $CMakeZip -Force
}


curl.exe `
    --location `
    --fail `
    --retry 10 `
    --retry-delay 5 `
    --retry-all-errors `
    --connect-timeout 30 `
    --max-time 900 `
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
    throw "CMake bin directory was not found."
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
# 9. VERIFY PACKAGE
# ============================================================

Write-Host ""
Write-Host "[9/10] Verifying package..."
Write-Host ""


if (!(Test-Path $LauncherExe)) {
    throw "blutter.exe is missing."
}


if (!(Test-Path "$Package\python\python.exe")) {
    throw "Bundled Python is missing."
}


if (!(Test-Path "$Package\blutter.py")) {
    throw "blutter.py is missing."
}


if (!(Test-Path "$Package\scripts")) {
    throw "scripts directory is missing."
}


Write-Host "blutter.exe:"
Get-Item $LauncherExe |
    Select-Object FullName, Length |
    Format-List


Write-Host ""
Write-Host "Bundled Python:"
Get-Item "$Package\python\python.exe" |
    Select-Object FullName, Length |
    Format-List


Write-Host ""
Write-Host "Package files:"
Write-Host ""


Get-ChildItem `
    $Package `
    -Recurse `
    -File |
    Select-Object FullName, Length |
    Format-Table -AutoSize


# ============================================================
# 10. COMPLETE
# ============================================================

Write-Host ""
Write-Host "[10/10] Build complete."
Write-Host ""

Write-Host "Package:"
Write-Host $Package

Write-Host ""
Write-Host "CLI:"
Write-Host ""
Write-Host "  blutter.exe libapp.so output"
Write-Host ""

Write-Host "============================================================"
Write-Host "                    SUCCESS"
Write-Host "============================================================"
Write-Host ""
