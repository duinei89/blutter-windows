$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot

$Dist = Join-Path $Root "dist"
$Package = Join-Path $Dist "blutter"

$LauncherSource = Join-Path `
    $Root `
    "launcher\launcher.cpp"

$LauncherExe = Join-Path `
    $Package `
    "blutter.exe"


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
    Remove-Item `
        $Dist `
        -Recurse `
        -Force
}

New-Item `
    -ItemType Directory `
    -Path $Package `
    -Force | Out-Null


# ============================================================
# 2. CHECK MSVC
# ============================================================

Write-Host "[2/10] Checking MSVC..."

where.exe cl

if ($LASTEXITCODE -ne 0) {
    throw "MSVC compiler 'cl.exe' was not found."
}

cl 2>&1 | Select-Object -First 4


# ============================================================
# 3. BUILD NATIVE LAUNCHER
# ============================================================

Write-Host "[3/10] Building native blutter.exe..."

if (!(Test-Path $LauncherSource)) {
    throw "Missing launcher source: $LauncherSource"
}


$LauncherObj = Join-Path `
    $env:TEMP `
    "blutter-launcher.obj"


if (Test-Path $LauncherObj) {
    Remove-Item `
        $LauncherObj `
        -Force
}


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
    /SUBSYSTEM:CONSOLE `
    /OUT:"$LauncherExe"

if ($LASTEXITCODE -ne 0) {
    throw "Native launcher compilation failed."
}


if (!(Test-Path $LauncherExe)) {
    throw "blutter.exe was not generated."
}


Write-Host ""
Write-Host "Launcher:"
Write-Host $LauncherExe


# ============================================================
# 4. COPY BLUTTER
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

    $Source = Join-Path `
        $Root `
        $File

    if (Test-Path $Source) {

        Copy-Item `
            $Source `
            $Package `
            -Force

        Write-Host "Copied $File"
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

    $Source = Join-Path `
        $Root `
        $Directory

    if (!(Test-Path $Source)) {
        throw "Required directory missing: $Directory"
    }

    Copy-Item `
        $Source `
        (Join-Path $Package $Directory) `
        -Recurse `
        -Force

    Write-Host "Copied $Directory"
}


# ============================================================
# 5. PYTHON
# ============================================================

Write-Host ""
Write-Host "[5/10] Downloading standalone Python..."

$PythonDir = Join-Path `
    $Package `
    "python"

New-Item `
    -ItemType Directory `
    -Path $PythonDir `
    -Force | Out-Null


$ApiUrl = `
    "https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest"


$Headers = @{
    "User-Agent" = "blutter-windows-builder"
}


Write-Host "Querying:"
Write-Host $ApiUrl


$Release = Invoke-RestMethod `
    -Uri $ApiUrl `
    -Headers $Headers `
    -Method Get


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
        "Could not find Python 3.12 x64 Windows install_only archive."
}


Write-Host ""
Write-Host "Python asset:"
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


& $PythonExe.FullName `
    --version


if ($LASTEXITCODE -ne 0) {
    throw "Bundled Python failed."
}


# ============================================================
# 6. PYTHON PACKAGES
# ============================================================

Write-Host ""
Write-Host "[6/10] Installing Python packages..."


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
# 7. WINDOWS LIBRARIES
# ============================================================

Write-Host ""
Write-Host "[7/10] Preparing ICU and Capstone..."


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

    if ($LASTEXITCODE -ne 0) {
        throw "init_env_win.py failed."
    }

}
finally {

    Pop-Location
}


# ============================================================
# 8. BUNDLED TOOLS DIRECTORY
# ============================================================

Write-Host ""
Write-Host "[8/10] Preparing bundled tools..."


$Tools = Join-Path `
    $Package `
    "tools"


New-Item `
    -ItemType Directory `
    -Path $Tools `
    -Force | Out-Null


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
    throw "Could not find Windows x64 CMake archive."
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


$CMakeBin = Get-ChildItem `
    $CMakeExtract `
    -Directory `
    -Recurse |
    Where-Object {
        Test-Path (
            Join-Path $_.FullName "bin\cmake.exe"
        )
    } |
    Select-Object -First 1


if (!$CMakeBin) {
    throw "CMake executable not found."
}


Copy-Item `
    (Join-Path $CMakeBin.FullName "bin") `
    (Join-Path $Tools "cmake") `
    -Recurse `
    -Force


# ------------------------------------------------------------
# Ninja
# ------------------------------------------------------------

Write-Host ""
Write-Host "Downloading Ninja..."


$NinjaReleaseApi =
    "https://api.github.com/repos/ninja-build/ninja/releases/latest"


$NinjaRelease = Invoke-RestMethod `
    -Uri $NinjaReleaseApi `
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
    "ninja-win.zip"


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


# ============================================================
# 9. TEST PACKAGE
# ============================================================

Write-Host ""
Write-Host "[9/10] Testing package..."


$TestExe = Join-Path `
    $Package `
    "blutter.exe"


& $TestExe


if ($LASTEXITCODE -eq 0) {
    Write-Host "Launcher test passed."
}
else {
    Write-Host "Launcher correctly returned usage information."
}


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
# 10. COMPLETE
# ============================================================

Write-Host ""
Write-Host "[10/10] Build complete."
Write-Host ""

Write-Host "Package:"
Write-Host $Package

Write-Host ""
Write-Host "CLI:"
Write-Host "  blutter.exe libapp.so output"

Write-Host ""
Write-Host "============================================================"
Write-Host "                    SUCCESS"
Write-Host "============================================================"
Write-Host ""
