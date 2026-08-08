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

static void banner()
{
    std::wcout
        << L"\n"
        << L"============================================================\n"
        << L"                         blutter\n"
        << L"============================================================\n"
        << L" Flutter / Dart native AOT analysis toolkit\n"
        << L"\n"
        << L" Md Tusar Akon  |  Telegram: @im_trt\n"
        << L"============================================================\n"
        << L"\n";
}

static int fail(const std::wstring& message)
{
    std::wcerr
        << L"\n"
        << L"ERROR\n"
        << L"------------------------------------------------------------\n"
        << message
        << L"\n"
        << L"------------------------------------------------------------\n\n";

    return 1;
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

static void set_env(const wchar_t* name, const fs::path& value)
{
    SetEnvironmentVariableW(name, value.wstring().c_str());
}

static std::wstring get_env(const wchar_t* name)
{
    DWORD size = GetEnvironmentVariableW(name, nullptr, 0);

    if (size == 0)
        return L"";

    std::vector<wchar_t> buffer(size);

    DWORD written = GetEnvironmentVariableW(
        name,
        buffer.data(),
        size
    );

    if (written == 0)
        return L"";

    return std::wstring(buffer.data(), written);
}

static void prepend_path(const fs::path& directory)
{
    if (!directory_exists(directory))
        return;

    std::wstring old_path = get_env(L"PATH");
    std::wstring new_path = directory.wstring();

    if (!old_path.empty())
    {
        new_path += L";";
        new_path += old_path;
    }

    SetEnvironmentVariableW(
        L"PATH",
        new_path.c_str()
    );
}

static bool find_toolchain(
    const fs::path& root,
    fs::path& bin_dir
)
{
    std::vector<fs::path> candidates =
    {
        root / L"tools" / L"llvm-mingw" / L"bin",
        root / L"tools" / L"llvm-mingw" / L"llvm-mingw" / L"bin",
        root / L"llvm-mingw" / L"bin"
    };

    for (const auto& candidate : candidates)
    {
        if (
            file_exists(candidate / L"clang.exe") &&
            file_exists(candidate / L"clang++.exe") &&
            file_exists(candidate / L"cmake.exe") == false
        )
        {
            bin_dir = candidate;
            return true;
        }
    }

    return false;
}

static bool find_python(
    const fs::path& root,
    fs::path& python
)
{
    std::vector<fs::path> candidates =
    {
        root / L"python" / L"python.exe",
        root / L"python" / L"python.exe"
    };

    for (const auto& candidate : candidates)
    {
        if (file_exists(candidate))
        {
            python = candidate;
            return true;
        }
    }

    return false;
}

static int launch_process(
    const fs::path& python,
    const fs::path& script,
    const std::vector<std::wstring>& args,
    const fs::path& working_directory
)
{
    std::wstring command;

    command += quote_arg(python.wstring());
    command += L" ";
    command += quote_arg(script.wstring());

    for (const auto& arg : args)
    {
        command += L" ";
        command += quote_arg(arg);
    }

    std::vector<wchar_t> command_buffer(
        command.begin(),
        command.end()
    );

    command_buffer.push_back(L'\0');

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);

    PROCESS_INFORMATION process{};

    BOOL created = CreateProcessW(
        nullptr,
        command_buffer.data(),
        nullptr,
        nullptr,
        FALSE,
        0,
        nullptr,
        working_directory.wstring().c_str(),
        &startup,
        &process
    );

    if (!created)
    {
        DWORD error = GetLastError();

        return fail(
            L"Could not start bundled Python.\n"
            L"Windows error: " +
            std::to_wstring(error)
        );
    }

    WaitForSingleObject(
        process.hProcess,
        INFINITE
    );

    DWORD exit_code = 1;

    GetExitCodeProcess(
        process.hProcess,
        &exit_code
    );

    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);

    return static_cast<int>(exit_code);
}

int wmain(int argc, wchar_t* argv[])
{
    banner();

    if (argc < 3)
    {
        std::wcout
            << L"Usage:\n"
            << L"  blutter.exe <libapp.so> <output>\n"
            << L"\n"
            << L"Examples:\n"
            << L"  blutter.exe libapp.so output\n"
            << L"  blutter.exe E:\\dump\\libapp.so E:\\dump\\output\n"
            << L"  blutter.exe E:\\dump E:\\dump\\output\n"
            << L"  blutter.exe application.apk output\n"
            << L"\n"
            << L"Input directory mode expects:\n"
            << L"  libapp.so\n"
            << L"  libflutter.so\n"
            << L"\n";

        return 1;
    }

    wchar_t module_path[32768];

    DWORD length = GetModuleFileNameW(
        nullptr,
        module_path,
        static_cast<DWORD>(std::size(module_path))
    );

    if (length == 0 || length >= std::size(module_path))
    {
        return fail(
            L"Could not determine blutter.exe location."
        );
    }

    fs::path exe_path(module_path);
    fs::path root = exe_path.parent_path();

    fs::path python;

    if (!find_python(root, python))
    {
        return fail(
            L"Bundled Python was not found.\n\n"
            L"Expected:\n" +
            (root / L"python" / L"python.exe").wstring()
        );
    }

    fs::path blutter_py =
        root / L"blutter.py";

    if (!file_exists(blutter_py))
    {
        return fail(
            L"blutter.py was not found:\n" +
            blutter_py.wstring()
        );
    }

    fs::path toolchain_bin;

    if (!find_toolchain(root, toolchain_bin))
    {
        return fail(
            L"Bundled LLVM-MinGW compiler was not found.\n\n"
            L"Expected:\n" +
            (root / L"tools" / L"llvm-mingw" / L"bin").wstring()
        );
    }

    fs::path clang =
        toolchain_bin / L"clang.exe";

    fs::path clangxx =
        toolchain_bin / L"clang++.exe";

    fs::path ar =
        toolchain_bin / L"llvm-ar.exe";

    fs::path ranlib =
        toolchain_bin / L"llvm-ranlib.exe";

    prepend_path(toolchain_bin);

    set_env(L"CC", clang);
    set_env(L"CXX", clangxx);

    if (file_exists(ar))
        set_env(L"AR", ar);

    if (file_exists(ranlib))
        set_env(L"RANLIB", ranlib);

    fs::path tools_dir =
        root / L"tools";

    prepend_path(tools_dir);

    fs::path cmake =
        tools_dir / L"cmake" / L"bin" / L"cmake.exe";

    fs::path ninja =
        tools_dir / L"ninja" / L"ninja.exe";

    fs::path git =
        tools_dir / L"git" / L"cmd" / L"git.exe";

    std::wcout
        << L"Environment:\n"
        << L"  Python : " << python.wstring() << L"\n"
        << L"  Clang  : " << clang.wstring() << L"\n"
        << L"  Clang++: " << clangxx.wstring() << L"\n";

    if (file_exists(cmake))
        std::wcout << L"  CMake  : " << cmake.wstring() << L"\n";

    if (file_exists(ninja))
        std::wcout << L"  Ninja  : " << ninja.wstring() << L"\n";

    if (file_exists(git))
        std::wcout << L"  Git    : " << git.wstring() << L"\n";

    std::wcout << L"\n";

    std::vector<std::wstring> args;

    for (int i = 1; i < argc; ++i)
        args.emplace_back(argv[i]);

    fs::path input_path(args[0]);

    std::error_code ec;

    input_path =
        fs::absolute(input_path, ec);

    if (ec)
    {
        return fail(
            L"Could not resolve input path."
        );
    }

    if (
        file_exists(input_path) &&
        input_path.filename() == L"libapp.so"
    )
    {
        fs::path parent =
            input_path.parent_path();

        fs::path libflutter =
            parent / L"libflutter.so";

        if (!file_exists(libflutter))
        {
            return fail(
                L"libflutter.so was not found beside libapp.so.\n\n"
                L"Expected:\n" +
                (parent / L"libapp.so").wstring() +
                L"\n" +
                (parent / L"libflutter.so").wstring()
            );
        }

        args[0] =
            parent.wstring();
    }

    std::wcout
        << L"Input : " << args[0] << L"\n"
        << L"Output: " << args[1] << L"\n"
        << L"\n"
        << L"Starting Blutter...\n"
        << L"\n";

    return launch_process(
        python,
        blutter_py,
        args,
        root
    );
}
