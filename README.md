# Blutter Windows

> A Windows-native distribution of Blutter with a simple CLI launcher, bundled Python runtime, and GitHub Actions-powered builds.

**Blutter Windows** packages the original Blutter reverse-engineering workflow into a convenient Windows executable so you can run it directly from `cmd.exe` without manually setting up Python, dependencies, or the Blutter source tree.

## Features

- Native Windows `blutter.exe` launcher
- Simple command-line interface
- Bundled Python 3.12 runtime
- No system Python required
- No system .NET runtime required
- Automatically prepares the Blutter environment
- Automatically downloads/builds required Dart components
- Supports `libapp.so`
- Supports directories containing Flutter libraries
- Supports APK input
- Windows x64 build
- GitHub Actions automated build
- Portable distribution
- Easy to add to Windows `PATH`

## CLI

Primary usage:

```text
blutter.exe <libapp.so> <output>
```

Example:

```cmd
blutter.exe libapp.so output
```

If `libflutter.so` is located beside `libapp.so`, Blutter will automatically use it.

## Input Formats

### Direct `libapp.so`

```cmd
blutter.exe E:\FlutterApp\libapp.so E:\FlutterApp\output
```

Expected layout:

```text
FlutterApp\
├── libapp.so
└── libflutter.so
```

### Directory containing Flutter libraries

```cmd
blutter.exe E:\FlutterApp E:\FlutterApp\output
```

Example:

```text
E:\FlutterApp\
├── libapp.so
├── libflutter.so
└── ...
```

### APK

```cmd
blutter.exe E:\APK\app.apk E:\APK\output
```

## Windows Installation

Download the latest Windows ZIP package from the repository Releases page.

Extract it somewhere convenient:

```text
E:\Tools\blutter\
```

The extracted directory should contain files similar to:

```text
blutter\
├── blutter.exe
├── blutter.py
├── blutter\
├── dartvm_fetch_build.py
├── extract_dart_info.py
├── python\
├── dartsdk\
├── scripts\
├── bin\
└── ...
```

Test the executable:

```cmd
E:\Tools\blutter\blutter.exe --help
```

## Add Blutter to PATH

Adding the Blutter directory to Windows `PATH` allows you to execute:

```cmd
blutter
```

from any directory.

For example, if Blutter is installed at:

```text
E:\Tools\blutter
```

add:

```text
E:\Tools\blutter
```

to your Windows user `PATH`.

Then open a **new CMD window**.

Verify:

```cmd
where blutter
```

Then:

```cmd
blutter --help
```

## Example Workflow

Suppose you have:

```text
E:\Mod\
├── libapp.so
└── libflutter.so
```

Run:

```cmd
blutter E:\Mod E:\Mod\output
```

Blutter will initialize its environment and begin processing the Flutter application.

Output will be written to:

```text
E:\Mod\output
```

## CLI Branding

The Windows launcher identifies this distribution as:

```text
B(L)UTTER WINDOWS
```

Maintainer:

```text
Md Tusar Akon
```

Telegram:

```text
@im_trt
```

## Requirements

The packaged Windows distribution is designed to minimize external dependencies.

### Required

- Windows 10/11
- Windows x64
- Internet connection for components that Blutter needs to obtain dynamically

### Not Required

The packaged CLI does not require separately installing:

- Python
- pip
- .NET 8
- CMake
- Ninja
- MSVC

The distribution includes its own Python runtime and required Python dependencies.

## Development Build

This repository uses GitHub Actions to build the Windows distribution.

The build environment is provided by GitHub-hosted Windows runners.

This means you do not need a powerful local computer to build the Windows package.

## GitHub Actions

The workflow prepares the required build environment, including:

- Python
- .NET
- MSVC
- CMake
- Ninja
- Python dependencies
- ICU
- Capstone
- Standalone Python
- Blutter runtime files

The final package is generated as:

```text
dist/blutter-windows-x64.zip
```

## Building with GitHub Actions

You do not need a powerful local computer.

1. Fork this repository.
2. Open the repository on GitHub.
3. Go to **Actions**.
4. Select the Windows build workflow.
5. Click **Run workflow**.
6. Wait for the build to complete.
7. Download the generated artifact.

The workflow can also create a GitHub Release when triggered by a version tag.

## Creating a Release

Create and push a version tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The GitHub Actions workflow detects tags matching:

```text
v*
```

and publishes:

```text
blutter-windows-x64.zip
```

to the GitHub Release.

## Project Structure

```text
blutter-windows/
│
├── .github/
│   └── workflows/
│       └── build-windows.yml
│
├── launcher/
│   └── launcher.cpp
│
├── scripts/
│   └── ...
│
├── blutter/
│   └── ...
│
├── dartvm_fetch_build.py
├── extract_dart_info.py
├── blutter.py
├── build-windows.ps1
├── README.md
└── LICENSE
```

## How the Launcher Works

The Windows executable acts as the front-end for the bundled Blutter environment.

Conceptually:

```text
blutter.exe
    │
    ├── Validate command line
    │
    ├── Locate bundled runtime
    │
    ├── Locate bundled Python
    │
    ├── Locate blutter.py
    │
    ├── Pass input/output arguments
    │
    └── Execute Blutter
```

This allows users to simply run:

```cmd
blutter input output
```

instead of manually invoking Python scripts.

## Portable Design

The distribution is intended to be portable.

For example:

```text
E:\Tools\blutter\
```

can be moved to:

```text
D:\ReverseEngineering\blutter\
```

and used from there.

If the directory is added to `PATH`, Windows can locate the executable regardless of the current working directory.

## Troubleshooting

### `blutter` is not recognized

If CMD shows:

```text
'blutter' is not recognized as an internal or external command
```

verify:

```cmd
where blutter
```

If nothing is returned, the Blutter directory has not been added correctly to `PATH`.

Close CMD, open a new CMD window, and try again.

### Verify the executable

Run:

```cmd
blutter --help
```

or:

```cmd
blutter
```

The CLI should display the Blutter Windows interface.

### Verify the input

For a normal Flutter Android application, make sure the required native libraries are available.

Typical files include:

```text
libapp.so
libflutter.so
```

For example:

```text
E:\Mod\
├── libapp.so
└── libflutter.so
```

Then:

```cmd
blutter E:\Mod E:\Mod\output
```

### Internet Connection

Some Blutter operations may download or obtain additional Dart/Flutter-related components.

If processing fails while retrieving a component, verify that internet access is available and retry.

## Dart / Flutter Version Compatibility

Flutter applications contain compiled Dart code and corresponding runtime metadata.

Blutter determines information from the supplied Flutter binaries and may need to obtain the corresponding Dart SDK/runtime sources.

For example, the analysis may report:

```text
Dart version: 3.8.1
```

Blutter can then prepare the appropriate environment for that version.

Compatibility depends on:

- Flutter version
- Dart version
- Architecture
- Flutter engine version
- Application build configuration
- Blutter support for the detected runtime

## Performance

The initial analysis can take significantly longer than subsequent operations because Blutter may need to prepare or build version-specific components.

Typical first-run flow:

```text
Detect Dart version
        ↓
Prepare Dart source
        ↓
Configure build
        ↓
Build required components
        ↓
Analyze application
```

Subsequent runs may be faster when required components are already available.

## Architecture

The current Windows distribution targets:

```text
x86-64 / AMD64
```

It is intended for:

- Windows 10 x64
- Windows 11 x64

ARM64 Windows is not currently the primary target of this distribution.

## Security Notice

This project is intended for legitimate software research, interoperability, debugging, malware analysis, security research, and applications you are authorized to inspect.

Only analyze software and applications for which you have the appropriate permission.

Do not use this project to bypass access controls, steal proprietary code, or access data without authorization.

## Credits

This Windows distribution is based on the original Blutter project.

The purpose of this repository is to provide a convenient Windows-native distribution and CLI experience around the existing Blutter tooling.

## Maintainer

**Md Tusar Akon**

Telegram: **@im_trt**
