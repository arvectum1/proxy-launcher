using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using Microsoft.Win32;

internal static class Program
{
    private const string PacUrl = "http://127.0.0.1:8082/proxy.pac";
    private const string InternetSettings = @"Software\Microsoft\Windows\CurrentVersion\Internet Settings";

    private static int Main(string[] args)
    {
        try
        {
            Dictionary<string, string> parsed = ParseArgs(args);
            string backup = Require(parsed, "backup");
            string runtime = Require(parsed, "runtime");
            string expectedRuntimeSha256 = Require(parsed, "expected-runtime-sha256").ToLowerInvariant();
            string evidence = parsed.ContainsKey("evidence") ? parsed["evidence"] : Path.Combine(backup, "appcontrol-recovery-result.json");

            string durable = Directory.Exists(Path.Combine(backup, "durable-state"))
                ? Path.Combine(backup, "durable-state")
                : backup;
            string sourceSettings = Path.Combine(durable, "proxy_settings.json");
            string sourceNoProxy = Path.Combine(durable, "no_proxy.txt");
            if (!File.Exists(sourceSettings)) throw new InvalidOperationException("proxy_settings.json is missing from the recovery backup.");
            if (!File.Exists(sourceNoProxy)) throw new InvalidOperationException("no_proxy.txt is missing from the recovery backup.");

            string launcher = Path.GetFullPath(Path.Combine(runtime, "Arvectum Proxy Launcher.exe"));
            if (!File.Exists(launcher)) throw new InvalidOperationException("Static recovery runtime launcher is missing.");
            string actualRuntimeSha256 = Sha256(launcher);
            if (!String.Equals(actualRuntimeSha256, expectedRuntimeSha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Static recovery runtime launcher SHA256 mismatch.");

            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string stateRoot = Path.Combine(localAppData, "Arvectum", "ProxyLauncher");
            Directory.CreateDirectory(stateRoot);
            File.Copy(sourceSettings, Path.Combine(stateRoot, "proxy_settings.json"), true);
            File.Copy(sourceNoProxy, Path.Combine(stateRoot, "no_proxy.txt"), true);
            DeleteIfPresent(Path.Combine(stateRoot, "proxy_core.pid"));
            DeleteIfPresent(Path.Combine(stateRoot, "proxy_env_backup.json"));
            DeleteIfPresent(Path.Combine(stateRoot, "proxy_internet_backup.json"));

            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = launcher;
            psi.Arguments = "--start";
            psi.WorkingDirectory = Path.GetDirectoryName(launcher);
            psi.UseShellExecute = false;
            Process started = Process.Start(psi);
            if (started == null) throw new InvalidOperationException("Static recovery runtime could not be started.");

            DateTime deadline = DateTime.UtcNow.AddSeconds(35);
            int status = 0;
            int ownerPid = 0;
            string autoConfigUrl = String.Empty;
            while (DateTime.UtcNow < deadline)
            {
                System.Threading.Thread.Sleep(750);
                ownerPid = FindExactLauncherPid(launcher);
                if (ownerPid <= 0) continue;
                status = GetPacStatus();
                if (status != 200) continue;
                autoConfigUrl = ReadAutoConfigUrl();
                if (String.Equals(autoConfigUrl, PacUrl, StringComparison.OrdinalIgnoreCase)) break;
            }

            bool pass = ownerPid > 0 && status == 200 && String.Equals(autoConfigUrl, PacUrl, StringComparison.OrdinalIgnoreCase);
            WriteEvidence(evidence, pass ? "PASS" : "BLOCK", actualRuntimeSha256, ownerPid, status, autoConfigUrl, null);
            if (!pass) throw new InvalidOperationException("Recovery runtime did not establish exact-process + PAC HTTP 200 + WinINET AutoConfigURL before timeout.");

            Console.WriteLine("APL-WIN-014 NATIVE RECOVERY: PASS");
            Console.WriteLine("EXACT STATIC RUNTIME: RUNNING");
            Console.WriteLine("PAC HTTP: 200");
            Console.WriteLine("WINDOWS PAC: RESTORED");
            Console.WriteLine("APP CONTROL POLICY: NOT CHANGED");
            Console.WriteLine("EVIDENCE: " + evidence);
            return 0;
        }
        catch (Exception ex)
        {
            try
            {
                Dictionary<string, string> parsed = ParseArgs(args);
                if (parsed.ContainsKey("evidence"))
                    WriteEvidence(parsed["evidence"], "BLOCK", String.Empty, 0, 0, String.Empty, ex.Message);
            }
            catch { }
            Console.Error.WriteLine("APL-WIN-014 NATIVE RECOVERY: BLOCK");
            Console.Error.WriteLine(ex.Message);
            return 1;
        }
    }

    private static Dictionary<string, string> ParseArgs(string[] args)
    {
        Dictionary<string, string> result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        for (int i = 0; i < args.Length; i++)
        {
            string key = args[i];
            if (!key.StartsWith("--", StringComparison.Ordinal)) throw new ArgumentException("Unexpected argument: " + key);
            if (i + 1 >= args.Length) throw new ArgumentException("Missing value for " + key);
            result[key.Substring(2)] = args[++i];
        }
        return result;
    }

    private static string Require(Dictionary<string, string> args, string key)
    {
        if (!args.ContainsKey(key) || String.IsNullOrWhiteSpace(args[key])) throw new ArgumentException("Missing --" + key + ".");
        return Path.GetFullPath(args[key]) == args[key] || key == "expected-runtime-sha256" ? args[key] : args[key];
    }

    private static string Sha256(string path)
    {
        using (SHA256 sha = SHA256.Create())
        using (FileStream stream = File.OpenRead(path))
        {
            byte[] digest = sha.ComputeHash(stream);
            return BitConverter.ToString(digest).Replace("-", String.Empty).ToLowerInvariant();
        }
    }

    private static void DeleteIfPresent(string path)
    {
        if (File.Exists(path)) File.Delete(path);
    }

    private static int FindExactLauncherPid(string expectedPath)
    {
        string expected = Path.GetFullPath(expectedPath);
        foreach (Process process in Process.GetProcessesByName("Arvectum Proxy Launcher"))
        {
            try
            {
                string candidate = process.MainModule.FileName;
                if (String.Equals(Path.GetFullPath(candidate), expected, StringComparison.OrdinalIgnoreCase)) return process.Id;
            }
            catch { }
            finally { process.Dispose(); }
        }
        return 0;
    }

    private static int GetPacStatus()
    {
        try
        {
            HttpWebRequest request = (HttpWebRequest)WebRequest.Create(PacUrl);
            request.Proxy = null;
            request.Timeout = 3000;
            request.ReadWriteTimeout = 3000;
            using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
            {
                return (int)response.StatusCode;
            }
        }
        catch { return 0; }
    }

    private static string ReadAutoConfigUrl()
    {
        try
        {
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(InternetSettings, false))
            {
                object value = key == null ? null : key.GetValue("AutoConfigURL", null, RegistryValueOptions.DoNotExpandEnvironmentNames);
                return value == null ? String.Empty : Convert.ToString(value);
            }
        }
        catch { return String.Empty; }
    }

    private static string JsonEscape(string value)
    {
        if (value == null) return String.Empty;
        return value.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n");
    }

    private static void WriteEvidence(string path, string result, string runtimeSha256, int ownerPid, int pacStatus, string autoConfigUrl, string error)
    {
        string directory = Path.GetDirectoryName(Path.GetFullPath(path));
        if (!Directory.Exists(directory)) Directory.CreateDirectory(directory);
        string json = "{" +
            "\"schema\":\"arvectum.proxy.apl-win-014-native-recovery.v1\"," +
            "\"task\":\"APL-WIN-014\"," +
            "\"result\":\"" + JsonEscape(result) + "\"," +
            "\"created_utc\":\"" + DateTime.UtcNow.ToString("o") + "\"," +
            "\"runtime_sha256\":\"" + JsonEscape(runtimeSha256) + "\"," +
            "\"listener_owner_pid\":" + ownerPid.ToString() + "," +
            "\"pac_http_status\":" + pacStatus.ToString() + "," +
            "\"auto_config_url\":\"" + JsonEscape(autoConfigUrl) + "\"," +
            "\"changes_app_control_policy\":false," +
            "\"error\":\"" + JsonEscape(error) + "\"" +
            "}";
        File.WriteAllText(path, json, new System.Text.UTF8Encoding(false));
    }
}
