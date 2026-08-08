#define UNICODE
#define _UNICODE

#include <windows.h>
#include <shellapi.h>

#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

#pragma comment(lib, "Shell32.lib")

namespace fs = std::filesystem;

static std::wstring quote_arg(const std::wstring& arg)
{
    if (arg.empty())
        return L"\"\"";

    bool needs_quotes = false;

    for (wchar_t c : arg)
    {
        if (c == L' ' || c == L'\t' || c == L'"')
        {
            needs_quotes = true;
            break;
        }
    }

    if (!needs_quotes)
        return arg;

    std::wstring result = L"\"";
    size_t backslashes = 0;

    for (wchar_t c : arg)
    {
        if (c == L'\\')
        {
            ++backslashes;
            continue;
        }

        if (c == L'"')
        {
            result.append(backslashes * 2 + 1, L'\\');
            result += L'"';
            backslashes = 0;
            continue;
        }

        result.append(backslashes, L'\\');
        backslashes = 0;
        result += c;
    }

    result.append(backslashes * 2, L'\\');
    result += L'"';

    return result;
}

static bool file_exists(const fs::path& path)
{
    std::error_code ec;
    return fs::is_regular_file(path, ec);
}

static bool directory_exists(const fs::path& path)
{
    std::error_code ec;
    return fs::is_directory(path, ec);
}

static int fail(const std::wstring& message)
{
    std::wcerr
        << L"\n"
        << L"ERROR: "
        << message
        << L"\n\n";

    return 1;
}

static void print_banner()
{
    std::wcout
        << L"\n"
        << L"============================================================\n"
        << L"                    B(L)UTTER WINDOWS\n"
        << L"============================================================\n"
        << L"\n"
        << L" Flutter / Dart native AOT analysis toolkit\n"
        << L"\n"
        << L" Maintainer : Md Tusar Akon\n"
        << L" Telegram   : @im_trt\n"
        << L"\n";
}

static void print_usage()
{
    std::wcout
        << L"Usage:\n"
        << L"\n"
        << L"  blutter.exe <libapp.so> <output>\n"
        << L"\n"
        << L"Examples:\n"
        << L"\n"
        << L"  blutter.exe libapp.so output\n"
        << L"  blutter.exe E:\\dump\\libapp.so E:\\dump\\output\n"
        << L"  blutter.exe E:\\dump E:\\dump\\output\n"
        << L"  blutter.exe application.apk output\n"
        << L"\n"
        << L"Input directory mode:\n"
        << L"\n"
        << L"  The directory should contain:\n"
        << L"    libapp.so\n"
        << L"    libflutter.so\n"
        << L"\n"
        << L"Bundled environment:\n"
        << L"  Python\n"
        << L"  CMake\n"
        << L"  Ninja\n"
        << L"  Git\n"
        << L"  Clang / LLD\n"
        << L"  Windows C/C++ sysroot\n"
        << L"\n"
        << L"No separate development environment is required.\n"
        << L"\n";
}

static bool set_env(const wchar_t* name, const std::wstring& value)
{
    return SetEnvironmentVariableW(name, value.c_str()) != FALSE;
}

static std::wstring get_env(const wchar_t* name)
{
    DWORD size = GetEnvironmentVariableW(name, nullptr, 0);

    if (size == 0)
        return L"";

    std::vector<wchar_t> buffer(size);

    DWORD result = GetEnvironmentVariableW(
        name,
        buffer.data(),
        size
    );

    if (result == 0)
        return L"";

    return std::wstring(buffer.data(), result);
}

static void prepend_path(std::wstring& path, const fs::path& value)
{
    if (!directory_exists(value))
        return;

    if (!path.empty())
        path += L";";

    path += value.wstring();
}

int wmain(int argc, wchar_t* argv[])
{
    print_banner();

    if (argc < 3)
    {
        print_usage();
        return 1;
    }

    // --------------------------------------------------------
    // Locate package root
    // --------------------------------------------------------

    wchar_t module_path[32768]{};

    DWORD length = GetModuleFileNameW(
        nullptr,
        module_path,
        static_cast<DWORD>(std::size(module_path))
    );

    if (length == 0 || length >= std::size(module_path))
    {
        return fail(L"Could not determine blutter.exe location.");
    }

    fs::path exe_path(module_path);
    fs::path root = exe_path.parent_path();

    // --------------------------------------------------------
    // Bundled Python
    // --------------------------------------------------------

    fs::path python_exe =
        root / L"python" / L"python.exe";

    if (!file_exists(python_exe))
    {
        return fail(
            L"Bundled Python was not found:\n  " +
            python_exe.wstring()
        );
    }

    // --------------------------------------------------------
    // Blutter
    // --------------------------------------------------------

    fs::path blutter_py =
        root / L"blutter.py";

    if (!file_exists(blutter_py))
    {
        return fail(
            L"blutter.py was not found:\n  " +
            blutter_py.wstring()
        );
    }

    // --------------------------------------------------------
    // Validate arguments
    // --------------------------------------------------------

    std::vector<std::wstring> args;

    for (int i = 1; i < argc; ++i)
    {
        args.emplace_back(argv[i]);
    }

    fs::path input_path(args[0]);

    std::error_code ec;

    input_path = fs::absolute(input_path, ec);

    if (ec)
    {
        return fail(L"Could not resolve input path.");
    }

    // --------------------------------------------------------
    // libapp.so convenience mode
    // --------------------------------------------------------

    if (
        fs::is_regular_file(input_path, ec) &&
        input_path.filename() == L"libapp.so"
    )
    {
        fs::path parent = input_path.parent_path();
        fs::path flutter = parent / L"libflutter.so";

        if (!file_exists(flutter))
        {
            return fail(
                L"libflutter.so was not found beside libapp.so.\n\n"
                L"Expected:\n  " +
                parent.wstring() +
                L"\\libapp.so\n  " +
                parent.wstring() +
                L"\\libflutter.so"
            );
        }

        args[0] = parent.wstring();
    }

    // --------------------------------------------------------
    // Package directories
    // --------------------------------------------------------

    fs::path tools_dir =
        root / L"tools";

    fs::path bin_dir =
        root / L"bin";

    fs::path clang_dir =
        root / L"llvm" / L"bin";

    fs::path sysroot_dir =
        root / L"sysroot";

    fs::path cmake_dir =
        root / L"tools" / L"cmake" / L"bin";

    fs::path ninja_dir =
        root / L"tools" / L"ninja";

    fs::path git_dir =
        root / L"tools" / L"git" / L"cmd";

    // --------------------------------------------------------
    // Validate bundled compiler
    // --------------------------------------------------------

    fs::path clang_cl =
        clang_dir / L"clang-cl.exe";

    fs::path clang =
        clang_dir / L"clang.exe";

    fs::path lld_link =
        clang_dir / L"lld-link.exe";

    if (!file_exists(clang_cl))
    {
        return fail(
            L"Bundled Clang was not found:\n  " +
            clang_cl.wstring()
        );
    }

    if (!file_exists(lld_link))
    {
        return fail(
            L"Bundled LLD linker was not found:\n  " +
            lld_link.wstring()
        );
    }

    if (!directory_exists(sysroot_dir))
    {
        return fail(
            L"Bundled Windows compiler sysroot was not found:\n  " +
            sysroot_dir.wstring()
        );
    }

    // --------------------------------------------------------
    // Build PATH
    // --------------------------------------------------------

    std::wstring path = get_env(L"PATH");

    prepend_path(path, clang_dir);
    prepend_path(path, bin_dir);
    prepend_path(path, cmake_dir);
    prepend_path(path, ninja_dir);
    prepend_path(path, git_dir);
    prepend_path(path, tools_dir);

    if (!set_env(L"PATH", path))
    {
        return fail(L"Could not configure PATH.");
    }

    // --------------------------------------------------------
    // Configure compiler
    //
    // CMake sees clang-cl as the C and C++ compiler.
    // /winsysroot supplies the bundled Windows CRT/SDK.
    // --------------------------------------------------------

    std::wstring compiler_options =
        L"/winsysroot \"" +
        sysroot_dir.wstring() +
        L"\" "
        L"-fuse-ld=lld-link";

    if (!set_env(L"CC", L"clang-cl"))
    {
        return fail(L"Could not set CC.");
    }

    if (!set_env(L"CXX", L"clang-cl"))
    {
        return fail(L"Could not set CXX.");
    }

    if (!set_env(L"CL", compiler_options))
    {
        return fail(L"Could not set CL compiler options.");
    }

    if (!set_env(L"LINK", L"lld-link"))
    {
        return fail(L"Could not set LINK.");
    }

    // Useful for CMake and other build systems.
    set_env(
        L"CMAKE_C_COMPILER",
        clang_cl.wstring()
    );

    set_env(
        L"CMAKE_CXX_COMPILER",
        clang_cl.wstring()
    );

    // --------------------------------------------------------
    // Informational environment
    // --------------------------------------------------------

    std::wcout
        << L"Package : " << root.wstring() << L"\n"
        << L"Input   : " << args[0] << L"\n"
        << L"Output  : " << args[1] << L"\n"
        << L"\n"
        << L"Bundled environment:\n"
        << L"  Python  : " << python_exe.wstring() << L"\n"
        << L"  Clang   : " << clang_cl.wstring() << L"\n"
        << L"  LLD     : " << lld_link.wstring() << L"\n"
        << L"  Sysroot : " << sysroot_dir.wstring() << L"\n"
        << L"\n";

    // --------------------------------------------------------
    // Build Python command
    // --------------------------------------------------------

    std::wstring command;

    command += quote_arg(python_exe.wstring());
    command += L" ";
    command += quote_arg(blutter_py.wstring());

    for (const auto& arg : args)
    {
        command += L" ";
        command += quote_arg(arg);
    }

    std::wcout
        << L"Starting Blutter...\n"
        << L"\n";

    // --------------------------------------------------------
    // Run from package root
    // --------------------------------------------------------

    if (!SetCurrentDirectoryW(root.wstring().c_str()))
    {
        return fail(
            L"Could not change working directory to:\n  " +
            root.wstring()
        );
    }

    // --------------------------------------------------------
    // Launch bundled Python
    // --------------------------------------------------------

    STARTUPINFOW startup_info{};
    startup_info.cb = sizeof(startup_info);

    PROCESS_INFORMATION process_info{};

    std::vector<wchar_t> command_buffer(
        command.begin(),
        command.end()
    );

    command_buffer.push_back(L'\0');

    BOOL created = CreateProcessW(
        nullptr,
        command_buffer.data(),
        nullptr,
        nullptr,
        FALSE,
        0,
        nullptr,
        root.wstring().c_str(),
        &startup_info,
        &process_info
    );

    if (!created)
    {
        DWORD error = GetLastError();

        return fail(
            L"Could not start bundled Python.\n"
            L"Windows error code: " +
            std::to_wstring(error)
        );
    }

    // --------------------------------------------------------
    // Wait
    // --------------------------------------------------------

    WaitForSingleObject(
        process_info.hProcess,
        INFINITE
    );

    DWORD exit_code = 1;

    GetExitCodeProcess(
        process_info.hProcess,
        &exit_code
    );

    CloseHandle(process_info.hThread);
    CloseHandle(process_info.hProcess);

    if (exit_code != 0)
    {
        std::wcerr
            << L"\nBlutter failed with exit code "
            << exit_code
            << L".\n\n";
    }
    else
    {
        std::wcout
            << L"\nBlutter completed successfully.\n\n";
    }

    return static_cast<int>(exit_code);
}
