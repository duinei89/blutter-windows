$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot
$Dist = Join-Path $Root "dist"
$Package = Join-Path $Dist "blutter"

$LauncherSource =
    Join-Path $Root "launcher\launcher.cpp"

$LauncherExe =
    Join-Path $Package "blutter.exe"

$PythonDir =
    Join-Path $Package "python"

$ToolsDir =
    Join-Path $Package "tools"

$BinDir =
    Join-Path $Package "bin"


# ============================================================
# HELPERS
# ============================================================

function Download-File {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$Output
    )

    Write-Host ""
    Write-Host "Downloading:"
    Write-Host $Url
    Write-Host ""

    if (Test-Path $Output) {
        Remove-Item $Output -Force
    }

    curl.exe `
        --location `
        --fail `
        --retry 10 `
        --retry-delay 5 `
        --retry-all-errors `
        --connect-timeout 30 `
        --max-time 1800 `
        --output "$Output" `
        "$Url"

    if ($LASTEXITCODE -ne 0) {
        throw "Download failed: $Url"
    }

    if (!(Test-Path $Output)) {
        throw "Downloaded file does not exist: $Output"
    }
}


function Get-LatestGitHubRelease {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApiUrl
    )

    $headers = @{
        "User-Agent" = "blutter-windows-builder"
        "Accept" = "application/vnd.github+json"
    }

    return Invoke-RestMethod `
        -Uri $ApiUrl `
        -Headers $headers `
        -Method Get
}


function Expand-ZipClean {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Zip,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    if (Test-Path $Destination) {
        Remove-Item `
            $Destination `
            -Recurse `
            -Force
    }

    New-Item `
        -ItemType Directory `
        -Path $Destination `
        -Force |
        Out-Null

    Expand-Archive `
        -Path $Zip `
        -DestinationPath $Destination `
        -Force
}


# ============================================================
# HEADER
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host "              B(L)UTTER WINDOWS BUILD"
Write-Host "============================================================"
Write-Host ""
Write-Host "              Md Tusar Akon"
Write-Host "              Telegram: @im_trt"
Write-Host ""
Write-Host "============================================================"
Write-Host ""


# ============================================================
# 1. CLEAN
# ============================================================

Write-Host "[1/10] Cleaning distribution..."

if (Test-Path $Dist) {
    Remove-Item `
        $Dist `
        -Recurse `
        -Force
}

New-Item `
    -ItemType Directory `
    -Path $Package `
    -Force |
    Out-Null

New-Item `
    -ItemType Directory `
    -Path $ToolsDir `
    -Force |
    Out-Null

New-Item `
    -ItemType Directory `
    -Path $BinDir `
    -Force |
    Out-Null


# ============================================================
# 2. VERIFY MSVC
# ============================================================

Write-Host ""
Write-Host "[2/10] Checking MSVC..."

$cl = Get-Command `
    cl.exe `
    -ErrorAction SilentlyContinue

if (!$cl) {
    throw "cl.exe was not found. MSVC environment is not initialized."
}

Write-Host "cl.exe:"
Write-Host $cl.Source


# ============================================================
# 3. BUILD NATIVE LAUNCHER
# ============================================================

Write-Host ""
Write-Host "[3/10] Building blutter.exe..."

if (!(Test-Path $LauncherSource)) {
    throw "Launcher source not found: $LauncherSource"
}

Write-Host ""
Write-Host "Source:"
Write-Host $LauncherSource

Write-Host ""
Write-Host "Output:"
Write-Host $LauncherExe

Write-Host ""

$CompileCommand = @"
cl.exe /nologo /std:c++17 /O2 /EHsc /MT /DUNICODE /D_UNICODE /Fe:"$LauncherExe" "$LauncherSource" /link /SUBSYSTEM:CONSOLE
"@

Write-Host "MSVC compilation:"
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
    throw "blutter.exe was not created."
}

Write-Host "Native launcher built successfully."


# ============================================================
# 4. COPY BLUTTER SOURCE
# ============================================================

Write-Host ""
Write-Host "[4/10] Copying Blutter source..."

$Files = @(
    "blutter.py",
    "dartvm_fetch_build.py",
    "extract_dart_info.py",
    "README.md",
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
    "blutter",
    "scripts"
)

foreach ($Directory in $Directories) {

    $Source =
        Join-Path $Root $Directory

    $Destination =
        Join-Path $Package $Directory

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
# 5. STANDALONE PYTHON
# ============================================================

Write-Host ""
Write-Host "[5/10] Downloading standalone Python..."

New-Item `
    -ItemType Directory `
    -Path $PythonDir `
    -Force |
    Out-Null


$PythonApi =
    "https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest"


$PythonRelease =
    Get-LatestGitHubRelease `
        $PythonApi


Write-Host ""
Write-Host "Latest Python release:"
Write-Host $PythonRelease.tag_name


$PythonAsset =
    $PythonRelease.assets |
    Where-Object {
        $_.name -match `
        "^cpython-3\.12\.[0-9]+\+.*-x86_64-pc-windows-msvc-install_only\.tar\.gz$"
    } |
    Select-Object -First 1


if (!$PythonAsset) {

    Write-Host ""
    Write-Host "Available x64 Python assets:"

    $PythonRelease.assets |
        Where-Object {
            $_.name -match `
            "cpython-3\.12.*x86_64-pc-windows-msvc"
        } |
        ForEach-Object {
            Write-Host $_.name
        }

    throw "Could not find CPython 3.12 Windows x64 archive."
}


Write-Host ""
Write-Host "Selected Python:"
Write-Host $PythonAsset.name


$PythonArchive =
    Join-Path $env:TEMP "blutter-python.tar.gz"

Download-File `
    $PythonAsset.browser_download_url `
    $PythonArchive


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
    -Force |
    Out-Null


Write-Host ""
Write-Host "Extracting Python..."

tar.exe `
    -xzf `
    "$PythonArchive" `
    -C `
    "$PythonTemp"

if ($LASTEXITCODE -ne 0) {
    throw "Python extraction failed."
}


$ExtractedPythonRoot =
    Get-ChildItem `
        $PythonTemp `
        -Directory |
        Select-Object -First 1


if (!$ExtractedPythonRoot) {
    throw "Could not locate extracted Python."
}


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
    throw "Bundled Python was not installed correctly."
}


Write-Host ""
Write-Host "Bundled Python:"
Write-Host $PythonExe

& $PythonExe --version

if ($LASTEXITCODE -ne 0) {
    throw "Bundled Python failed."
}


# ============================================================
# 6. BUNDLE CMAKE
# ============================================================

Write-Host ""
Write-Host "[6/10] Bundling CMake, Ninja and Git..."

$CMakeRoot =
    Join-Path $ToolsDir "cmake"


$CMakeApi =
    "https://api.github.com/repos/Kitware/CMake/releases/latest"


$CMakeRelease =
    Get-LatestGitHubRelease `
        $CMakeApi


$CMakeAsset =
    $CMakeRelease.assets |
    Where-Object {
        $_.name -match `
        "^cmake-[0-9]+\.[0-9]+\.[0-9]+-windows-x86_64\.zip$"
    } |
    Select-Object -First 1


if (!$CMakeAsset) {

    Write-Host ""
    Write-Host "Available CMake assets:"

    $CMakeRelease.assets |
        Where-Object {
            $_.name -match "windows-x86_64.*zip"
        } |
        ForEach-Object {
            Write-Host $_.name
        }

    throw "Could not find Windows x64 CMake archive."
}


Write-Host ""
Write-Host "CMake:"
Write-Host $CMakeAsset.name


$CMakeZip =
    Join-Path $env:TEMP "blutter-cmake.zip"


Download-File `
    $CMakeAsset.browser_download_url `
    $CMakeZip


$CMakeTemp =
    Join-Path $env:TEMP "blutter-cmake"


Expand-ZipClean `
    $CMakeZip `
    $CMakeTemp


$CMakeExtracted =
    Get-ChildItem `
        $CMakeTemp `
        -Directory |
        Select-Object -First 1


if (!$CMakeExtracted) {
    throw "CMake extraction failed."
}


New-Item `
    -ItemType Directory `
    -Path $CMakeRoot `
    -Force |
    Out-Null


Get-ChildItem `
    $CMakeExtracted.FullName `
    -Force |
    ForEach-Object {

        Copy-Item `
            $_.FullName `
            $CMakeRoot `
            -Recurse `
            -Force
    }


Remove-Item `
    $CMakeZip `
    -Force

Remove-Item `
    $CMakeTemp `
    -Recurse `
    -Force


$CMakeExe =
    Join-Path `
        $CMakeRoot `
        "bin\cmake.exe"


if (!(Test-Path $CMakeExe)) {
    throw "Bundled cmake.exe was not found."
}


Write-Host ""
Write-Host "Bundled CMake:"
Write-Host $CMakeExe

& $CMakeExe --version

if ($LASTEXITCODE -ne 0) {
    throw "CMake verification failed."
}


# ============================================================
# BUNDLE NINJA
# ============================================================

Write-Host ""
Write-Host "Downloading Ninja..."


$NinjaApi =
    "https://api.github.com/repos/ninja-build/ninja/releases/latest"


$NinjaRelease =
    Get-LatestGitHubRelease `
        $NinjaApi


$NinjaAsset =
    $NinjaRelease.assets |
    Where-Object {
        $_.name -eq "ninja-win.zip"
    } |
    Select-Object -First 1


if (!$NinjaAsset) {
    throw "Could not find ninja-win.zip."
}


Write-Host ""
Write-Host "Ninja:"
Write-Host $NinjaAsset.name


$NinjaZip =
    Join-Path $env:TEMP "blutter-ninja.zip"


Download-File `
    $NinjaAsset.browser_download_url `
    $NinjaZip


Expand-Archive `
    -Path $NinjaZip `
    -DestinationPath $ToolsDir `
    -Force


Remove-Item `
    $NinjaZip `
    -Force


$NinjaExe =
    Join-Path `
        $ToolsDir `
        "ninja.exe"


if (!(Test-Path $NinjaExe)) {
    throw "Bundled ninja.exe was not found."
}


Write-Host ""
Write-Host "Bundled Ninja:"
Write-Host $NinjaExe

& $NinjaExe --version

if ($LASTEXITCODE -ne 0) {
    throw "Ninja verification failed."
}


# ============================================================
# BUNDLE MINGIT
# ============================================================

Write-Host ""
Write-Host "Downloading MinGit..."


$GitApi =
    "https://api.github.com/repos/git-for-windows/git/releases/latest"


$GitRelease =
    Get-LatestGitHubRelease `
        $GitApi


$GitAsset =
    $GitRelease.assets |
    Where-Object {
        $_.name -match `
        "^MinGit-.*-64-bit\.zip$"
    } |
    Select-Object -First 1


if (!$GitAsset) {

    Write-Host ""
    Write-Host "Available MinGit assets:"

    $GitRelease.assets |
        Where-Object {
            $_.name -match "MinGit.*64-bit.*zip"
        } |
        ForEach-Object {
            Write-Host $_.name
        }

    throw "Could not find MinGit 64-bit archive."
}


Write-Host ""
Write-Host "MinGit:"
Write-Host $GitAsset.name


$GitZip =
    Join-Path $env:TEMP "blutter-mingit.zip"


Download-File `
    $GitAsset.browser_download_url `
    $GitZip


$GitRoot =
    Join-Path $ToolsDir "git"


Expand-ZipClean `
    $GitZip `
    $GitRoot


Remove-Item `
    $GitZip `
    -Force


$GitExe =
    Join-Path `
        $GitRoot `
        "cmd\git.exe"


if (!(Test-Path $GitExe)) {

    Write-Host ""
    Write-Host "Git package contents:"

    Get-ChildItem `
        $GitRoot `
        -Recurse `
        -File |
        Select-Object FullName |
        Format-Table -AutoSize

    throw "Bundled Git was not found."
}


Write-Host ""
Write-Host "Bundled Git:"
Write-Host $GitExe

& $GitExe --version

if ($LASTEXITCODE -ne 0) {
    throw "Git verification failed."
}


# ============================================================
# CONFIGURE BUILD PATH
# ============================================================

$env:PATH =
    (
        (Join-Path $BinDir ""),
        (Join-Path $ToolsDir ""),
        (Join-Path $CMakeRoot "bin"),
        (Join-Path $GitRoot "cmd"),
        (Join-Path $GitRoot "mingw64\bin"),
        $env:PATH
    ) -join ";"


Write-Host ""
Write-Host "Bundled tool PATH configured."


# ============================================================
# 7. PYTHON DEPENDENCIES
# ============================================================

Write-Host ""
Write-Host "[7/10] Installing Python dependencies..."

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
# INITIALIZE BLUTTER
# ============================================================

Write-Host ""
Write-Host "Initializing Blutter..."

$InitScript =
    Join-Path `
        $Package `
        "scripts\init_env_win.py"


if (!(Test-Path $InitScript)) {
    throw "init_env_win.py was not found."
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
# 8. VERIFY BUNDLED TOOLS
# ============================================================

Write-Host ""
Write-Host "[8/10] Verifying bundled tools..."


$RequiredFiles = @(
    $LauncherExe,
    "$Package\blutter.py",
    "$Package\python\python.exe",
    "$Package\tools\ninja.exe",
    "$Package\tools\cmake\bin\cmake.exe",
    "$Package\tools\git\cmd\git.exe"
)


foreach ($File in $RequiredFiles) {

    if (!(Test-Path $File)) {

        Write-Host ""
        Write-Host "MISSING:"
        Write-Host $File

        throw "Required package file is missing."
    }
}


Write-Host ""
Write-Host "Python:"
& $PythonExe --version


Write-Host ""
Write-Host "CMake:"
& $CMakeExe --version


Write-Host ""
Write-Host "Ninja:"
& $NinjaExe --version


Write-Host ""
Write-Host "Git:"
& $GitExe --version


# ============================================================
# 9. VERIFY RUNTIME
# ============================================================

Write-Host ""
Write-Host "[9/10] Verifying runtime..."


$RuntimeDlls = @(
    "$Package\bin\capstone.dll",
    "$Package\bin\icudt73.dll",
    "$Package\bin\icuuc73.dll"
)


foreach ($Dll in $RuntimeDlls) {

    if (!(Test-Path $Dll)) {

        Write-Host ""
        Write-Host "WARNING: runtime DLL not found:"
        Write-Host $Dll
    }
}


# ============================================================
# 10. FINAL PACKAGE
# ============================================================

Write-Host ""
Write-Host "[10/10] Final package verification..."


$RequiredDirectories = @(
    "$Package\blutter",
    "$Package\scripts",
    "$Package\python",
    "$Package\tools",
    "$Package\tools\cmake",
    "$Package\tools\git",
    "$Package\bin"
)


foreach ($Directory in $RequiredDirectories) {

    if (!(Test-Path $Directory)) {
        throw "Required package directory missing: $Directory"
    }
}


Write-Host ""
Write-Host "============================================================"
Write-Host "                 BUILD SUCCESSFUL"
Write-Host "============================================================"
Write-Host ""
Write-Host "               B(L)UTTER WINDOWS"
Write-Host ""
Write-Host "               Md Tusar Akon"
Write-Host "               Telegram: @im_trt"
Write-Host ""
Write-Host "Executable:"
Write-Host $LauncherExe
Write-Host ""
Write-Host "Package:"
Write-Host $Package
Write-Host ""
Write-Host "Usage:"
Write-Host ""
Write-Host "  blutter.exe libapp.so output"
Write-Host ""
Write-Host "============================================================"
Write-Host ""
