using System.Diagnostics;
using System.Reflection;

internal static class Program
{
    private const string Version = "1.0.0";

    private static int Main(string[] args)
    {
        Console.OutputEncoding = System.Text.Encoding.UTF8;

        if (args.Length == 0)
        {
            PrintBanner();
            PrintUsage();
            return 1;
        }

        if (args[0] == "--help" || args[0] == "-h")
        {
            PrintBanner();
            PrintUsage();
            return 0;
        }

        if (args[0] == "--version" || args[0] == "-v")
        {
            Console.WriteLine($"Blutter Windows {Version}");
            return 0;
        }

        if (args.Length < 2)
        {
            PrintBanner();

            Console.Error.WriteLine(
                "Error: input and output paths are required.\n");

            PrintUsage();
            return 1;
        }

        string input = Path.GetFullPath(args[0]);
        string output = Path.GetFullPath(args[1]);

        if (!File.Exists(input))
        {
            Console.Error.WriteLine(
                $"Error: libapp.so was not found:\n{input}");

            return 2;
        }

        if (!IsLibApp(input))
        {
            Console.Error.WriteLine(
                "Error: input does not appear to be an ELF libapp.so file.");

            return 3;
        }

        string root = AppContext.BaseDirectory;

        string python = Path.Combine(
            root,
            "runtime",
            "python",
            "python.exe");

        string blutterScript = Path.Combine(
            root,
            "blutter",
            "blutter.py");

        if (!File.Exists(python))
        {
            Console.Error.WriteLine(
                $"Error: bundled Python was not found:\n{python}");

            return 10;
        }

        if (!File.Exists(blutterScript))
        {
            Console.Error.WriteLine(
                $"Error: Blutter Python frontend was not found:\n{blutterScript}");

            return 11;
        }

        string? libFlutter = FindLibFlutter(input);

        if (libFlutter == null)
        {
            Console.Error.WriteLine();
            Console.Error.WriteLine(
                "Error: libflutter.so was not found.");
            Console.Error.WriteLine();
            Console.Error.WriteLine(
                "Blutter needs libflutter.so to automatically determine");
            Console.Error.WriteLine(
                "the Dart/Flutter version used by libapp.so.");
            Console.Error.WriteLine();
            Console.Error.WriteLine(
                "Put libflutter.so beside libapp.so:");
            Console.Error.WriteLine();
            Console.Error.WriteLine(
                $"  {Path.GetDirectoryName(input)}\\libflutter.so");
            Console.Error.WriteLine();

            return 12;
        }

        Directory.CreateDirectory(output);

        string tempInput = Path.Combine(
            Path.GetTempPath(),
            "blutter-" + Guid.NewGuid().ToString("N"));

        Directory.CreateDirectory(tempInput);

        string tempApp = Path.Combine(
            tempInput,
            "libapp.so");

        string tempFlutter = Path.Combine(
            tempInput,
            "libflutter.so");

        try
        {
            File.Copy(input, tempApp, true);
            File.Copy(libFlutter, tempFlutter, true);

            PrintBanner();

            Console.WriteLine($"Input : {input}");
            Console.WriteLine($"Flutter: {libFlutter}");
            Console.WriteLine($"Output: {output}");
            Console.WriteLine();

            Console.WriteLine("Starting Blutter...");
            Console.WriteLine();

            var psi = new ProcessStartInfo
            {
                FileName = python,
                WorkingDirectory = Path.Combine(root, "blutter"),
                UseShellExecute = false,
                CreateNoWindow = false
            };

            psi.ArgumentList.Add(blutterScript);
            psi.ArgumentList.Add(tempInput);
            psi.ArgumentList.Add(output);

            using Process? process = Process.Start(psi);

            if (process == null)
            {
                Console.Error.WriteLine(
                    "Error: failed to start Blutter.");

                return 20;
            }

            process.WaitForExit();

            if (process.ExitCode == 0)
            {
                Console.WriteLine();
                Console.WriteLine(
                    "Blutter completed successfully.");
                Console.WriteLine();
                Console.WriteLine(
                    $"Output: {output}");
            }
            else
            {
                Console.Error.WriteLine();
                Console.Error.WriteLine(
                    $"Blutter failed with exit code {process.ExitCode}.");
            }

            return process.ExitCode;
        }
        finally
        {
            try
            {
                if (Directory.Exists(tempInput))
                    Directory.Delete(tempInput, true);
            }
            catch
            {
                // Ignore temporary directory cleanup failures.
            }
        }
    }

    private static string? FindLibFlutter(string libApp)
    {
        string? directory = Path.GetDirectoryName(libApp);

        if (directory == null)
            return null;

        string direct = Path.Combine(
            directory,
            "libflutter.so");

        if (File.Exists(direct))
            return direct;

        // Also check common Flutter APK extraction layout.
        string? parent = Directory.GetParent(directory)?.FullName;

        if (parent != null)
        {
            string arm64 = Path.Combine(
                parent,
                "arm64-v8a",
                "libflutter.so");

            if (File.Exists(arm64))
                return arm64;
        }

        return null;
    }

    private static bool IsLibApp(string path)
    {
        try
        {
            using FileStream fs = File.OpenRead(path);

            byte[] magic = new byte[4];

            if (fs.Read(magic, 0, 4) != 4)
                return false;

            return magic[0] == 0x7F &&
                   magic[1] == (byte)'E' &&
                   magic[2] == (byte)'L' &&
                   magic[3] == (byte)'F';
        }
        catch
        {
            return false;
        }
    }

    private static void PrintBanner()
    {
        Console.WriteLine();
        Console.WriteLine("==============================================");
        Console.WriteLine("              BLUTTER WINDOWS");
        Console.WriteLine("       Flutter AOT Reverse Engineering");
        Console.WriteLine("==============================================");
        Console.WriteLine();
    }

    private static void PrintUsage()
    {
        Console.WriteLine("Usage:");
        Console.WriteLine();
        Console.WriteLine("  blutter.exe <libapp.so> <output>");
        Console.WriteLine();
        Console.WriteLine("Example:");
        Console.WriteLine();
        Console.WriteLine(
            @"  blutter.exe C:\APK\libapp.so C:\APK\output");
        Console.WriteLine();
        Console.WriteLine("Options:");
        Console.WriteLine();
        Console.WriteLine("  --help       Show this help");
        Console.WriteLine("  --version    Show version");
        Console.WriteLine();
        Console.WriteLine(
            "Place libflutter.so beside libapp.so.");
        Console.WriteLine();
    }
}
