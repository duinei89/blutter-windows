#define UNICODE
#define _UNICODE

#include <windows.h>
#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

namespace fs = std::filesystem;


// ============================================================
// Branding
// ============================================================

static const wchar_t* APP_NAME = L"B(L)UTTER WINDOWS";
static const wchar_t* AUTHOR = L"Md Tusar Akon";
static const wchar_t* TELEGRAM = L"@im_trt";


// ============================================================
// Quote Windows command-line argument
// ============================================================

static std::wstring quote_arg(const std::wstring& arg)
{
    if (arg.empty())
        return L"\"\"";

    bool needs_quotes = false;

    for (wchar_t c : arg)
    {
        if (c == L' ' ||
            c == L'\t' ||
            c == L'"')
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
            result.append(
                backslashes * 2 + 1,
                L'\\'
            );

            result += L'"';

            backslashes = 0;

            continue;
        }

        result.append(
            backslashes,
            L'\\'
        );

        backslashes = 0;

        result += c;
    }

    result.append(
        backslashes * 2,
        L'\\'
    );

    result += L'"';

    return result;
}


// ============================================================
// Banner
// ============================================================

static void print_banner()
{
    std::wcout
        << L"\n"
        << L"============================================================\n"
        << L"                    " << APP_NAME << L"\n"
        << L"============================================================\n"
        << L"  Flutter / Dart native AOT analysis toolkit\n"
        << L"\n"
        << L"  Created by : " << AUTHOR << L"\n"
        << L"  Telegram   : " << TELEGRAM << L"\n"
        << L"============================================================\n"
        << L"\n";
}


// ============================================================
// Usage
// ============================================================

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
        << L"  blutter.exe E:\\\\dump\\\\libapp.so E:\\\\dump\\\\output\n"
        << L"  blutter.exe E:\\\\dump E:\\\\dump\\\\output\n"
        << L"  blutter.exe application.apk output\n"
        << L"\n"
        << L"Input directory mode:\n"
        << L"\n"
        << L"  The directory should contain:\n"
        << L"    libapp.so\n"
        << L"    libflutter.so\n"
        << L"\n"
        << L"The launcher automatically uses the bundled:\n"
        << L"  Python\n"
        << L"  CMake\n"
        << L"  Ninja\n"
        << L"  Git\n"
        << L"\n"
        << L"No separate installation is required.\n"
        << L"\n"
        << L"Author:\n"
        << L"  " << AUTHOR << L"\n"
        << L"  Telegram: " << TELEGRAM << L"\n"
        << L"\n";
}


// ============================================================
// Error helper
// ============================================================

static int fail(const std::wstring& message)
{
    std::wcerr
        << L"\n"
        << L"ERROR: "
        << message
        << L"\n\n";

    return 1;
}


// ============================================================
// Get executable directory
// ============================================================

static bool get_executable_directory(fs::path& result)
{
    std::vector<wchar_t> buffer(
        MAX_PATH
    );

    for (;;)
    {
        DWORD length = GetModuleFileNameW(
            nullptr,
            buffer.data(),
            static_cast<DWORD>(buffer.size())
        );

        if (length == 0)
            return false;

        if (length < buffer.size() - 1)
        {
            buffer.resize(length);

            result = fs::path(buffer.data()).parent_path();

            return true;
        }

        buffer.resize(
            buffer.size() * 2
        );
    }
}


// ============================================================
// Add directory to PATH
// ============================================================

static bool prepend_to_path(
    const fs::path& directory,
    std::wstring& path_cache
)
{
    std::error_code ec;

    if (!fs::exists(directory, ec) ||
        !fs::is_directory(directory, ec))
    {
        return false;
    }

    const std::wstring dir =
        directory.wstring();

    if (path_cache.empty())
    {
        path_cache = dir;
    }
    else
    {
        path_cache =
            dir +
            L";" +
            path_cache;
    }

    return true;
}


// ============================================================
// Configure bundled environment
// ============================================================

static bool configure_environment(
    const fs::path& root
)
{
    wchar_t buffer[32768];

    DWORD length =
        GetEnvironmentVariableW(
            L"PATH",
            buffer,
            static_cast<DWORD>(
                sizeof(buffer) /
                sizeof(wchar_t)
            )
        );

    std::wstring path;

    if (length > 0 &&
        length < sizeof(buffer) / sizeof(wchar_t))
    {
        path.assign(
            buffer,
            length
        );
    }

    /*
     * Runtime DLLs:
     *
     *   bin\
     *
     * ICU and Capstone are installed here
     * by init_env_win.py.
     */

    prepend_to_path(
        root / L"bin",
        path
    );


    /*
     * Generic bundled tools:
     *
     *   tools\
     */

    prepend_to_path(
        root / L"tools",
        path
    );


    /*
     * CMake:
     *
     *   tools\cmake\bin\
     */

    prepend_to_path(
        root / L"tools" / L"cmake" / L"bin",
        path
    );


    /*
     * Git:
     *
     * MinGit normally contains:
     *
     *   cmd\
     *   mingw64\bin\
     */

    prepend_to_path(
        root / L"tools" / L"git" / L"cmd",
        path
    );

    prepend_to_path(
        root / L"tools" / L"git" / L"mingw64" / L"bin",
        path
    );


    /*
     * Ninja is placed directly inside tools.
     *
     * cmake.exe will find ninja.exe through PATH.
     */


    if (!SetEnvironmentVariableW(
            L"PATH",
            path.c_str()))
    {
        return false;
    }

    return true;
}


// ============================================================
// Run Python
// ============================================================

static int run_python(
    const fs::path& root,
    int argc,
    wchar_t* argv[]
)
{
    const fs::path python =
        root /
        L"python" /
        L"python.exe";


    const fs::path blutter =
        root /
        L"blutter.py";


    if (!fs::exists(python))
    {
        return fail(
            L"Bundled Python was not found:\n  " +
            python.wstring()
        );
    }


    if (!fs::exists(blutter))
    {
        return fail(
            L"blutter.py was not found:\n  " +
            blutter.wstring()
        );
    }


    /*
     * Build:
     *
     * python.exe blutter.py ...
     */

    std::wstring command;

    command += quote_arg(
        python.wstring()
    );

    command += L" ";

    command += quote_arg(
        blutter.wstring()
    );


    for (int i = 1; i < argc; ++i)
    {
        command += L" ";

        command += quote_arg(
            argv[i]
        );
    }


    /*
     * Run from package root.
     */

    if (!SetCurrentDirectoryW(
            root.wstring().c_str()))
    {
        return fail(
            L"Could not set working directory:\n  " +
            root.wstring()
        );
    }


    STARTUPINFOW startup_info{};

    startup_info.cb =
        sizeof(startup_info);


    PROCESS_INFORMATION process_info{};


    std::vector<wchar_t> command_buffer(
        command.begin(),
        command.end()
    );

    command_buffer.push_back(
        L'\0'
    );


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
            << L"\n"
            << L"Blutter failed with exit code "
            << exit_code
            << L".\n\n";
    }
    else
    {
        std::wcout
            << L"\n"
            << L"Blutter completed successfully.\n"
            << L"\n";
    }


    return static_cast<int>(
        exit_code
    );
}


// ============================================================
// Main
// ============================================================

int wmain(
    int argc,
    wchar_t* argv[]
)
{
    print_banner();


    if (argc < 3)
    {
        print_usage();

        return 0;
    }


    fs::path root;


    if (!get_executable_directory(root))
    {
        return fail(
            L"Could not determine blutter.exe location."
        );
    }


    /*
     * Configure all bundled runtime tools.
     */

    if (!configure_environment(root))
    {
        return fail(
            L"Could not configure bundled environment."
        );
    }


    /*
     * Copy command arguments.
     */

    std::vector<std::wstring> args;


    for (int i = 1; i < argc; ++i)
    {
        args.emplace_back(
            argv[i]
        );
    }


    /*
     * --------------------------------------------------------
     * Convenience mode
     *
     * blutter.exe libapp.so output
     *
     * Upstream Blutter expects the directory containing
     * both libapp.so and libflutter.so.
     * --------------------------------------------------------
     */

    fs::path input_path(
        args[0]
    );


    std::error_code ec;


    input_path =
        fs::absolute(
            input_path,
            ec
        );


    if (ec)
    {
        return fail(
            L"Could not resolve input path."
        );
    }


    if (
        fs::is_regular_file(
            input_path,
            ec
        ) &&
        input_path.filename() ==
            L"libapp.so"
    )
    {
        fs::path parent =
            input_path.parent_path();


        fs::path flutter =
            parent /
            L"libflutter.so";


        if (!fs::exists(
                flutter,
                ec))
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


        /*
         * Convert:
         *
         * blutter.exe libapp.so output
         *
         * into:
         *
         * blutter.py <parent> output
         */

        args[0] =
            parent.wstring();
    }


    /*
     * Show actual input/output.
     */

    std::wcout
        << L"Input : "
        << args[0]
        << L"\n";

    std::wcout
        << L"Output: "
        << args[1]
        << L"\n\n";


    std::wcout
        << L"Bundled environment:\n"
        << L"  Python : "
        << (root / L"python" / L"python.exe").wstring()
        << L"\n"
        << L"  Tools  : "
        << (root / L"tools").wstring()
        << L"\n"
        << L"  Bin    : "
        << (root / L"bin").wstring()
        << L"\n\n";


    std::wcout
        << L"Starting Blutter...\n\n";


    /*
     * Construct a modified argv-like array.
     *
     * run_python currently uses the original argv for the
     * command. We therefore temporarily create a new vector
     * with the transformed arguments.
     */

    std::vector<std::wstring> final_args;

    final_args.push_back(
        argv[0]
    );

    for (const auto& arg : args)
    {
        final_args.push_back(
            arg
        );
    }


    std::vector<wchar_t*> final_argv;


    for (auto& value : final_args)
    {
        final_argv.push_back(
            value.data()
        );
    }


    return run_python(
        root,
        static_cast<int>(
            final_argv.size()
        ),
        final_argv.data()
    );
}
