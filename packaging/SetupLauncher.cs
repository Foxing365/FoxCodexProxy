using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows.Forms;

internal static class SetupLauncher
{
    [STAThread]
    private static int Main(string[] args)
    {
        string temporary = null;
        try
        {
            bool extractOnly = args.Length == 2 && args[0] == "--extract";
            if (args.Length != 0 && !extractOnly)
                throw new ArgumentException("Usage: Setup.exe [--extract new-directory]");
            string destination;
            if (extractOnly)
            {
                destination = Path.GetFullPath(args[1]);
                if (Directory.Exists(destination) || File.Exists(destination))
                    throw new IOException("Extraction destination must not already exist.");
            }
            else
            {
                temporary = Path.Combine(Path.GetTempPath(), "FoxCodexProxy-" + Guid.NewGuid().ToString("N"));
                destination = temporary;
            }
            Directory.CreateDirectory(destination);
            string root = Path.GetFullPath(destination) + Path.DirectorySeparatorChar;
            using (Stream payload = Assembly.GetExecutingAssembly().GetManifestResourceStream("windows-payload.zip"))
            using (ZipArchive archive = new ZipArchive(payload, ZipArchiveMode.Read))
            {
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    string target = Path.GetFullPath(Path.Combine(destination, entry.FullName));
                    if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                        throw new IOException("Invalid package entry.");
                    if (String.IsNullOrEmpty(entry.Name)) { Directory.CreateDirectory(target); continue; }
                    Directory.CreateDirectory(Path.GetDirectoryName(target));
                    using (Stream input = entry.Open())
                    using (FileStream output = File.Create(target)) input.CopyTo(output);
                }
            }
            if (extractOnly) return 0;
            string script = Path.Combine(destination, "scripts", "windows", "setup.ps1");
            var start = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe"));
            start.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File \"" + script + "\"";
            start.WorkingDirectory = destination;
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            using (Process process = Process.Start(start)) { process.WaitForExit(); return process.ExitCode; }
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "FoxCodexProxy installer", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally
        {
            if (temporary != null)
            {
                string parent = Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar);
                if (String.Equals(Path.GetDirectoryName(temporary), parent, StringComparison.OrdinalIgnoreCase))
                    try { Directory.Delete(temporary, true); } catch { }
            }
        }
    }
}
