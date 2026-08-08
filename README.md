# Blutter Windows

> A Windows-friendly distribution of [Blutter](https://github.com/worawit/blutter) for Flutter/Dart reverse engineering.

Blutter is a tool for analyzing Flutter applications and extracting useful information from `libapp.so`.

This fork provides a **native Windows CLI** with a bundled Python runtime, so you can run Blutter without installing Python or .NET separately.

---

## ✨ Features

- 🪟 Native Windows `blutter.exe`
- 🐍 Bundled Python 3.12 runtime
- 📦 Self-contained distribution
- 🔧 Built automatically with GitHub Actions
- 🚫 No .NET runtime required
- ⚡ Simple command-line interface
- 🛠️ Uses the original Blutter Python tooling
- 📁 Supports APKs, directories, and `libapp.so`

---

## 🚀 Usage

From Command Prompt:

```cmd
blutter.exe <libapp.so> <output>
```

Example:

```cmd
blutter.exe libapp.so output
```

You can also provide a directory containing the Flutter libraries:

```cmd
blutter.exe E:\App\lib\arm64-v8a E:\Output
```

Or an APK:

```cmd
blutter.exe application.apk output
```

The launcher will locate the required Flutter libraries and start the underlying Blutter workflow.

---

## 📂 Expected Flutter Libraries

For a typical extracted Flutter application:

```text
lib/
└── arm64-v8a/
    ├── libapp.so
    └── libflutter.so
```

`libflutter.so` should be available beside `libapp.so` when using the `libapp.so` input mode.

---

## 🖥️ Windows Package

The release package contains everything required to run the Windows launcher:

```text
blutter/
├── blutter.exe
├── blutter.py
├── blutter/
├── scripts/
├── dartvm_fetch_build.py
├── extract_dart_info.py
├── bin/
└── python/
    └── python.exe
```

The bundled Python runtime means you don't need to install Python separately.

---

## 📥 Installation

Download the latest Windows ZIP from the repository's **Releases** page.

Extract it somewhere convenient, for example:

```text
E:\Tools\blutter\
```

Then either run it from that directory:

```cmd
cd /d E:\Tools\blutter
blutter.exe libapp.so output
```

or add the directory to your Windows `PATH` and use:

```cmd
blutter libapp.so output
```

---

## 🔨 Building

The Windows build is handled entirely through GitHub Actions.

The build process:

```text
launcher.cpp
     ↓
MSVC
     ↓
native blutter.exe
     ↓
bundled Python
     ↓
Blutter
     ↓
Windows ZIP
```

No local Windows build environment is required if you use the GitHub Actions workflow.

---

## 🧩 Credits

This project is based on the original Blutter project:

**Blutter**  
https://github.com/worawit/blutter

Original project and its contributors deserve credit for the underlying reverse-engineering tooling.

This repository focuses on making the tooling easier to use on Windows.

---

## 👤 Maintainer

**Md Tusar Akon**

Telegram: **[@im_trt](https://t.me/im_trt)**

---

## ⚠️ Disclaimer

This project is intended for legitimate research, debugging, interoperability, security analysis, and educational purposes.

Only analyze applications and software that you have permission to inspect.

---

<p align="center">
  Made for Windows users who just want to run Blutter without fighting the setup.
</p>
