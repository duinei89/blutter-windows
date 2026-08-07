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
            backslashes++;
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


static void print_banner()
{
    std::wcout
        << L"\n"
        << L"============================================================\n"
        << L"                     B(L)UTTER WINDOWS\n"
        << L"============================================================\n"
        << L"\n";
}


static int fail(const std::wstring& message)
{
    std::wcerr << L"\nERROR: " << message << L"\n\n";
    return 1;
}


int wmain(int argc, wchar_t* argv[])
{
    print_banner();

    if (argc < 3)
    {
        std::wcout
            << L"Usage:\n"
            << L"  blutter.exe <libapp.so> <output>\n"
            << L"\n"
            << L"Example:\n"
            << L"  blutter.exe libapp.so output\n"
            << L"\n"
            << L"The launcher expects libflutter.so beside libapp.so.\n"
            << L"\n"
            << L"Other supported input:\n"
            << L"  blutter.exe <directory-containing-libapp-and-libflutter> <output>\n"
            << L"  blutter.exe <application.apk> <output>\n"
            << L"\n";

        return 1;
    }


    // --------------------------------------------------------
    // Locate ourselves
    // --------------------------------------------------------

    wchar_t module_path[MAX_PATH];

    DWORD length = GetModuleFileNameW(
        nullptr,
        module_path,
        MAX_PATH
    );

    if (length == 0 || length >= MAX_PATH)
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

    if (!fs::exists(python_exe))
    {
        return fail(
            L"Bundled Python was not found:\n  " +
            python_exe.wstring()
        );
    }


    // --------------------------------------------------------
    // Blutter Python entry point
    // --------------------------------------------------------

    fs::path blutter_py =
        root / L"blutter.py";

    if (!fs::exists(blutter_py))
    {
        return fail(
            L"blutter.py was not found:\n  " +
            blutter_py.wstring()
        );
    }


    // --------------------------------------------------------
    // Copy arguments
    // --------------------------------------------------------

    std::vector<std::wstring> args;

    for (int i = 1; i < argc; ++i)
    {
        args.emplace_back(argv[i]);
    }


    // --------------------------------------------------------
    // Special convenience mode:
    //
    // blutter.exe libapp.so output
    //
    // Convert this to:
    //
    // python blutter.py <parent-directory> output
    //
    // because upstream Blutter needs libflutter.so as well.
    // --------------------------------------------------------

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
        fs::is_regular_file(input_path, ec) &&
        input_path.filename() == L"libapp.so"
    )
    {
        fs::path parent =
            input_path.parent_path();

        fs::path flutter =
            parent / L"libflutter.so";

        if (!fs::exists(flutter))
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
    // Build Python command line
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
        << L"Input : " << args[0] << L"\n"
        << L"Output: " << args[1] << L"\n"
        << L"\n"
        << L"Starting Blutter...\n"
        << L"\n";


    // --------------------------------------------------------
    // Environment
    // --------------------------------------------------------

    // Put bundled tools first.
    //
    // This allows us to ship:
    //
    // tools\
    //   cmake\
    //   ninja\
    //   git\
    //
    // without requiring the user to configure PATH.

    wchar_t old_path_buffer[32768];

    DWORD old_path_length =
        GetEnvironmentVariableW(
            L"PATH",
            old_path_buffer,
            static_cast<DWORD>(
                sizeof(old_path_buffer) /
                sizeof(wchar_t)
            )
        );

    std::wstring old_path;

    if (old_path_length > 0)
    {
        old_path.assign(
            old_path_buffer,
            old_path_length
        );
    }


    std::wstring bundled_tools =
        (root / L"tools").wstring();

    std::wstring new_path =
        bundled_tools;

    if (!old_path.empty())
    {
        new_path += L";";
        new_path += old_path;
    }

    SetEnvironmentVariableW(
        L"PATH",
        new_path.c_str()
    );


    // --------------------------------------------------------
    // Change current directory to package root
    // --------------------------------------------------------

    SetCurrentDirectoryW(
        root.wstring().c_str()
    );


    // --------------------------------------------------------
    // Launch Python
    // --------------------------------------------------------

    STARTUPINFOW startup_info{};
    startup_info.cb =
        sizeof(startup_info);

    PROCESS_INFORMATION process_info{};

    std::vector<wchar_t> command_buffer(
        command.begin(),
        command.end()
    );

    command_buffer.push_back(L'\0');


    BOOL created =
        CreateProcessW(
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
        DWORD error =
            GetLastError();

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


    CloseHandle(
        process_info.hThread
    );

    CloseHandle(
        process_info.hProcess
    );


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
