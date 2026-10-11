using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Pipes;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace CodexAutoProxy
{
    internal enum RouteMode { Auto, Direct, Clash }

    internal static class RoutePolicy
    {
        public static RouteMode Preferred(RouteMode mode, RouteMode detected, string host)
        {
            if (mode != RouteMode.Auto) return mode;
            // The ChatGPT probe cannot establish whether Google is reachable.
            string normalized = (host ?? "").TrimEnd('.').ToLowerInvariant();
            foreach (string domain in new[] { "google.com", "googleapis.com", "gstatic.com", "googleusercontent.com", "antigravity.google" })
                if (normalized == domain || normalized.EndsWith("." + domain, StringComparison.Ordinal))
                    return RouteMode.Clash;
            return detected;
        }
    }

    internal static class Diagnostic
    {
        private static readonly object networkGate = new object();
        private static DateTime networkWindow = DateTime.MinValue;
        private static int networkCount;

        public static void Network(string message)
        {
            // Do not log targets, URLs, headers, tokens, or conversation content.
            lock (networkGate)
            {
                if (DateTime.UtcNow >= networkWindow.AddMinutes(1))
                {
                    networkWindow = DateTime.UtcNow;
                    networkCount = 0;
                }
                networkCount++;
                if (networkCount <= 10) Write(message);
                else if (networkCount == 11) Write("Network diagnostic rate limit reached; further entries suppressed for this minute.");
            }
        }

        public static string ErrorType(Exception error)
        {
            SocketException socket = error as SocketException ?? error.InnerException as SocketException;
            return error.GetType().Name + (socket == null ? "" : "/" + socket.SocketErrorCode);
        }

        public static void Write(string message)
        {
            try
            {
                File.AppendAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "diagnostic.log"),
                    DateTime.UtcNow.ToString("o") + " " + message + Environment.NewLine, new UTF8Encoding(false));
            }
            catch { }
        }
    }

    internal sealed class Settings
    {
        private string configPath;
        public string CodexExe;
        public string ClashHost = "127.0.0.1";
        public int ClashPort = 7897;
        public int ListenPort = 7898;
        public int ProbeSeconds = 30;
        public bool LaunchCodexOnStart = true;
        public bool PreferClash = false;
        public string UpstreamExe = "";
        public string UpstreamConfig = "";

        public static Settings Load(string path)
        {
            Settings value = new Settings();
            value.configPath = path;
            if (!File.Exists(path)) throw new FileNotFoundException("找不到 config.ini", path);
            foreach (string raw in File.ReadAllLines(path, Encoding.UTF8))
            {
                string line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#")) continue;
                int equals = line.IndexOf('=');
                if (equals < 1) continue;
                string key = line.Substring(0, equals).Trim();
                string item = line.Substring(equals + 1).Trim();
                int parsed;
                if (key.Equals("CodexExe", StringComparison.OrdinalIgnoreCase)) value.CodexExe = item;
                else if (key.Equals("ClashHost", StringComparison.OrdinalIgnoreCase)) value.ClashHost = item;
                else if (key.Equals("ClashPort", StringComparison.OrdinalIgnoreCase) && Int32.TryParse(item, out parsed) && parsed > 0 && parsed <= 65535) value.ClashPort = parsed;
                else if (key.Equals("ListenPort", StringComparison.OrdinalIgnoreCase) && Int32.TryParse(item, out parsed) && parsed > 0 && parsed <= 65535) value.ListenPort = parsed;
                else if (key.Equals("ProbeSeconds", StringComparison.OrdinalIgnoreCase) && Int32.TryParse(item, out parsed)) value.ProbeSeconds = Math.Max(10, parsed);
                else if (key.Equals("LaunchCodexOnStart", StringComparison.OrdinalIgnoreCase)) value.LaunchCodexOnStart = item.Equals("true", StringComparison.OrdinalIgnoreCase);
                else if (key.Equals("PreferClash", StringComparison.OrdinalIgnoreCase)) value.PreferClash = item.Equals("true", StringComparison.OrdinalIgnoreCase);
                else if (key.Equals("UpstreamExe", StringComparison.OrdinalIgnoreCase)) value.UpstreamExe = item;
                else if (key.Equals("UpstreamConfig", StringComparison.OrdinalIgnoreCase)) value.UpstreamConfig = item;
            }
            if (String.IsNullOrWhiteSpace(value.CodexExe)) throw new InvalidDataException("config.ini 缺少 CodexExe");
            return value;
        }

        public void Save()
        {
            string[] lines = new string[] {
                "CodexExe=" + CodexExe,
                "ClashHost=" + ClashHost,
                "ClashPort=" + ClashPort,
                "ListenPort=" + ListenPort,
                "ProbeSeconds=" + ProbeSeconds,
                "LaunchCodexOnStart=" + LaunchCodexOnStart.ToString().ToLowerInvariant(),
                "PreferClash=" + PreferClash.ToString().ToLowerInvariant(),
                "UpstreamExe=" + UpstreamExe,
                "UpstreamConfig=" + UpstreamConfig
            };
            File.WriteAllLines(configPath, lines, new UTF8Encoding(false));
        }
    }

    internal sealed class SettingsForm : Form
    {
        private readonly NumericUpDown clashPort;
        private readonly CheckBox startWithWindows;

        public SettingsForm(Settings settings, bool startupEnabled)
        {
            Text = "Codex 自动代理设置";
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(330, 170);

            Label label = new Label();
            label.Text = "Clash Verge mixed port：";
            label.AutoSize = true;
            label.Location = new Point(18, 24);
            Controls.Add(label);

            clashPort = new NumericUpDown();
            clashPort.Minimum = 1;
            clashPort.Maximum = 65535;
            clashPort.Value = settings.ClashPort;
            clashPort.Location = new Point(190, 20);
            clashPort.Width = 110;
            Controls.Add(clashPort);

            Label hint = new Label();
            hint.Text = "保存后，新建连接立即使用该端口。";
            hint.AutoSize = true;
            hint.ForeColor = SystemColors.GrayText;
            hint.Location = new Point(18, 57);
            Controls.Add(hint);

            startWithWindows = new CheckBox();
            startWithWindows.Text = "随 Windows 登录启动代理";
            startWithWindows.Checked = startupEnabled;
            startWithWindows.AutoSize = true;
            startWithWindows.Location = new Point(18, 88);
            Controls.Add(startWithWindows);

            Button save = new Button();
            save.Text = "保存";
            save.DialogResult = DialogResult.OK;
            save.Location = new Point(144, 126);
            save.Width = 75;
            Controls.Add(save);

            Button cancel = new Button();
            cancel.Text = "取消";
            cancel.DialogResult = DialogResult.Cancel;
            cancel.Location = new Point(225, 126);
            cancel.Width = 75;
            Controls.Add(cancel);

            AcceptButton = save;
            CancelButton = cancel;
        }

        public int ClashPort { get { return Decimal.ToInt32(clashPort.Value); } }
        public bool StartWithWindows { get { return startWithWindows.Checked; } }
    }

    internal static class CodexEnvironment
    {
        private const string Begin = "# BEGIN codex-auto-proxy-windows";
        private const string End = "# END codex-auto-proxy-windows";
        private const string BackupKeyName = @"Software\CodexAutoProxy\EnvironmentBackup";
        private const int HwndBroadcast = 0xffff;
        private const int WmSettingChange = 0x001a;
        private static readonly string[] ProxyNames = { "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY" };
        private static readonly object Sync = new object();

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern bool SendNotifyMessage(
            IntPtr hWnd, int message, UIntPtr wParam, string lParam);

        public static string PathName
        {
            get
            {
                return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex", ".env");
            }
        }

        public static void Disable()
        {
            lock (Sync)
            {
                RemoveLegacyFileBlock();
                using (RegistryKey backup = Registry.CurrentUser.OpenSubKey(BackupKeyName, true))
                using (RegistryKey environment = Registry.CurrentUser.CreateSubKey("Environment"))
                {
                    if (backup != null)
                    {
                        foreach (string name in ProxyNames)
                        {
                            if (backup.GetValue(name + "_Saved") == null) continue;
                            string managed = backup.GetValue(name + "_Managed") as string;
                            string current = environment.GetValue(name, null, RegistryValueOptions.DoNotExpandEnvironmentNames) as string;
                            if (!String.Equals(current, managed, StringComparison.OrdinalIgnoreCase)) continue;
                            bool existed = Convert.ToInt32(backup.GetValue(name + "_Existed", 0)) != 0;
                            string original = backup.GetValue(name + "_Original") as string;
                            if (existed) environment.SetValue(name, original ?? "", RegistryValueKind.String);
                            else environment.DeleteValue(name, false);
                        }
                    }
                }
                try { Registry.CurrentUser.DeleteSubKeyTree(BackupKeyName, false); } catch { }
                BroadcastEnvironmentChange();
            }
        }

        public static void PrepareCurrentProcess()
        {
            foreach (string name in ProxyNames)
                Environment.SetEnvironmentVariable(name, null, EnvironmentVariableTarget.Process);
        }

        private static void RemoveLegacyFileBlock()
        {
            List<string> lines = ReadWithoutManagedBlock();
            while (lines.Count > 0 && String.IsNullOrWhiteSpace(lines[lines.Count - 1])) lines.RemoveAt(lines.Count - 1);
            if (lines.Count == 0)
            {
                if (File.Exists(PathName)) File.Delete(PathName);
                return;
            }
            Write(lines);
        }

        private static void BroadcastEnvironmentChange()
        {
            SendNotifyMessage(new IntPtr(HwndBroadcast), WmSettingChange, UIntPtr.Zero, "Environment");
        }

        private static List<string> ReadWithoutManagedBlock()
        {
            List<string> output = new List<string>();
            bool inside = false;
            if (!File.Exists(PathName)) return output;
            foreach (string line in File.ReadAllLines(PathName, Encoding.UTF8))
            {
                if (line.Trim().Equals(Begin, StringComparison.Ordinal)) { inside = true; continue; }
                if (inside && line.Trim().Equals(End, StringComparison.Ordinal)) { inside = false; continue; }
                if (!inside) output.Add(line);
            }
            return output;
        }

        private static void Write(IEnumerable<string> lines)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(PathName));
            string temporary = PathName + ".codex-auto-proxy.tmp";
            File.WriteAllLines(temporary, lines, new UTF8Encoding(false));
            if (File.Exists(PathName)) File.Replace(temporary, PathName, null);
            else File.Move(temporary, PathName);
        }
    }

    internal sealed class RouteDetector : IDisposable
    {
        private readonly Settings settings;
        private readonly AutoResetEvent wake = new AutoResetEvent(false);
        private readonly Thread worker;
        private volatile bool stopping;
        private volatile bool directAvailable;
        private volatile RouteMode mode = RouteMode.Auto;
        private volatile string detail = "正在检测";
        private volatile string lastProbeUtc = "";
        private int directSuccesses;
        private DateTime directCooldown = DateTime.MinValue;
        private readonly object healthGate = new object();

        public RouteDetector(Settings value)
        {
            settings = value;
            worker = new Thread(Loop);
            worker.IsBackground = true;
            worker.Name = "Codex direct route detector";
        }

        public void Start() { worker.Start(); }
        public RouteMode Mode { get { return mode; } set { mode = value; wake.Set(); } }
        public bool DirectAvailable { get { return directAvailable; } }
        public string Detail { get { return detail; } }
        public string LastProbeUtc { get { return lastProbeUtc; } }
        public RouteMode EffectiveRoute { get { return mode == RouteMode.Auto ? (settings.PreferClash ? RouteMode.Clash : (directAvailable ? RouteMode.Direct : RouteMode.Clash)) : mode; } }
        public void ProbeNow() { wake.Set(); }

        public void ReportEmptyTunnel(RouteMode route, long elapsedMs, long uploaded, long downloaded)
        {
            if (route != RouteMode.Direct || uploaded == 0 || downloaded != 0 || elapsedMs >= 5000) return;
            lock (healthGate) { directAvailable = false; directSuccesses = 0; directCooldown = DateTime.UtcNow.AddMinutes(2); }
            Diagnostic.Network("Direct route entered 120-second cooldown after an empty early tunnel close.");
        }

        private void Loop()
        {
            while (!stopping)
            {
                Probe();
                if (stopping) break;
                wake.WaitOne(TimeSpan.FromSeconds(settings.ProbeSeconds));
            }
        }

        private void Probe()
        {
            try
            {
                ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
                HttpWebRequest request = (HttpWebRequest)WebRequest.Create("https://chatgpt.com/backend-api/codex/responses");
                request.Method = "HEAD";
                request.AllowAutoRedirect = false;
                request.Proxy = settings.PreferClash ? new WebProxy("http://" + settings.ClashHost + ":" + settings.ClashPort) : null;
                request.Timeout = 5000;
                request.ReadWriteTimeout = 5000;
                request.UserAgent = "CodexAutoProxy/1.0";
                using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
                {
                    RecordProbe((int)response.StatusCode);
                }
            }
            catch (WebException ex)
            {
                HttpWebResponse response = ex.Response as HttpWebResponse;
                if (response != null && (int)response.StatusCode < 500)
                {
                    RecordProbe((int)response.StatusCode);
                    response.Close();
                }
                else
                {
                    RecordProbe(0);
                    if (response != null) response.Close();
                }
            }
            catch
            {
                RecordProbe(0);
            }
            finally { lastProbeUtc = DateTime.UtcNow.ToString("o"); }
        }

        private void RecordProbe(int status)
        {
            bool reachable = status >= 200 && status < 500;
            if (settings.PreferClash)
            {
                directAvailable = false;
                detail = reachable ? "Clash TLS 探测可达 (HTTP " + status + ")" : "Clash TLS 探测失败";
                return;
            }
            lock (healthGate)
            {
                directSuccesses = reachable ? Math.Min(3, directSuccesses + 1) : 0;
                directAvailable = directSuccesses >= 3 && DateTime.UtcNow >= directCooldown;
                detail = directAvailable ? "直连 TLS 探测可达 (HTTP " + status + ")" : "使用 Clash · 直连未连续通过探测";
            }
        }

        public void Dispose()
        {
            stopping = true;
            wake.Set();
            // A five-second probe may still be running during shutdown.
            // Never dispose the event while that worker can still use it.
            if (worker.IsAlive) worker.Join(6000);
            if (!worker.IsAlive) wake.Dispose();
        }
    }

    internal sealed class ProxyServer : IDisposable
    {
        private readonly Settings settings;
        private readonly RouteDetector detector;
        private TcpListener listener;
        private Thread acceptThread;
        private volatile bool stopping;

        public ProxyServer(Settings value, RouteDetector routeDetector)
        {
            settings = value;
            detector = routeDetector;
        }

        public void Start()
        {
            listener = new TcpListener(IPAddress.Loopback, settings.ListenPort);
            listener.Start(64);
            acceptThread = new Thread(AcceptLoop);
            acceptThread.IsBackground = true;
            acceptThread.Name = "Codex local proxy listener";
            acceptThread.Start();
        }

        private void AcceptLoop()
        {
            while (!stopping)
            {
                try
                {
                    TcpClient client = listener.AcceptTcpClient();
                    Thread thread = new Thread(delegate() { Handle(client); });
                    thread.IsBackground = true;
                    thread.Start();
                }
                catch (SocketException) { if (!stopping) Thread.Sleep(100); }
                catch (ObjectDisposedException) { break; }
            }
        }

        private static byte[] ReadHeaders(NetworkStream stream, out int headerLength)
        {
            MemoryStream buffer = new MemoryStream();
            byte[] one = new byte[4096];
            headerLength = -1;
            while (buffer.Length < 65536 && headerLength < 0)
            {
                int read = stream.Read(one, 0, one.Length);
                if (read <= 0) break;
                buffer.Write(one, 0, read);
                byte[] current = buffer.ToArray();
                for (int i = Math.Max(0, current.Length - read - 3); i <= current.Length - 4; i++)
                {
                    if (current[i] == 13 && current[i + 1] == 10 && current[i + 2] == 13 && current[i + 3] == 10)
                    {
                        headerLength = i + 4;
                        break;
                    }
                }
            }
            return buffer.ToArray();
        }

        private void Handle(TcpClient client)
        {
            using (client)
            {
                try
                {
                    client.ReceiveTimeout = 15000;
                    NetworkStream incoming = client.GetStream();
                    int headerLength;
                    byte[] request = ReadHeaders(incoming, out headerLength);
                    if (headerLength < 0) return;
                    // The 15-second limit protects only HTTP header parsing.
                    // TLS/SSE tunnels must remain open while the client is idle.
                    client.ReceiveTimeout = 0;
                    string header = Encoding.ASCII.GetString(request, 0, headerLength);
                    string[] lines = header.Split(new string[] { "\r\n" }, StringSplitOptions.None);
                    string[] first = lines[0].Split(' ');
                    if (first.Length < 3) return;
                    bool connect = first[0].Equals("CONNECT", StringComparison.OrdinalIgnoreCase);
                    string host;
                    int port;
                    string path;
                    if (!ParseTarget(first[1], lines, connect, out host, out port, out path)) return;

                    RouteMode preferred = RoutePolicy.Preferred(detector.Mode, detector.EffectiveRoute, host);
                    RouteMode alternate = preferred == RouteMode.Direct ? RouteMode.Clash : RouteMode.Direct;
                    if (!TryHandleRoute(preferred, connect, host, port, path, lines, request, headerLength, incoming))
                    {
                        if (!TryHandleRoute(alternate, connect, host, port, path, lines, request, headerLength, incoming))
                        {
                            byte[] failure = Encoding.ASCII.GetBytes("HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\nContent-Length: 0\r\n\r\n");
                            incoming.Write(failure, 0, failure.Length);
                        }
                    }
                }
                catch { }
            }
        }

        private bool TryHandleRoute(RouteMode route, bool connect, string host, int port, string path, string[] lines, byte[] request, int headerLength, NetworkStream incoming)
        {
            TcpClient remote = null;
            Stopwatch elapsed = Stopwatch.StartNew();
            try
            {
                if (route == RouteMode.Direct)
                {
                    remote = ConnectWithTimeout(host, port, 5000);
                    NetworkStream outgoing = remote.GetStream();
                    if (connect)
                    {
                        SendEstablished(incoming);
                        SendRemainder(request, headerLength, outgoing);
                    }
                    else
                    {
                        byte[] rewritten = RewriteDirectRequest(lines, path, request, headerLength);
                        outgoing.Write(rewritten, 0, rewritten.Length);
                    }
                    Relay(incoming, outgoing, remote, route, port);
                    return true;
                }

                remote = ConnectWithTimeout(settings.ClashHost, settings.ClashPort, 3000);
                NetworkStream clash = remote.GetStream();
                if (connect)
                {
                    remote.ReceiveTimeout = 15000;
                    string tunnel = "CONNECT " + host + ":" + port + " HTTP/1.1\r\nHost: " + host + ":" + port + "\r\nProxy-Connection: Keep-Alive\r\n\r\n";
                    byte[] bytes = Encoding.ASCII.GetBytes(tunnel);
                    clash.Write(bytes, 0, bytes.Length);
                    int upstreamHeader;
                    byte[] answer = ReadHeaders(clash, out upstreamHeader);
                    remote.ReceiveTimeout = 0;
                    string answerText = upstreamHeader > 0 ? Encoding.ASCII.GetString(answer, 0, upstreamHeader) : "";
                    if (upstreamHeader < 0 || answerText.IndexOf(" 200 ", StringComparison.Ordinal) < 0) throw new IOException("Clash refused CONNECT");
                    SendEstablished(incoming);
                    if (answer.Length > upstreamHeader) incoming.Write(answer, upstreamHeader, answer.Length - upstreamHeader);
                    SendRemainder(request, headerLength, clash);
                }
                else
                {
                    clash.Write(request, 0, request.Length);
                }
                Relay(incoming, clash, remote, route, port);
                return true;
            }
            catch (Exception error)
            {
                Diagnostic.Network("route_setup_failed route=" + route + " port=" + port +
                    " elapsedMs=" + elapsed.ElapsedMilliseconds + " error=" + Diagnostic.ErrorType(error));
                if (remote != null) remote.Close();
                return false;
            }
        }

        private static TcpClient ConnectWithTimeout(string host, int port, int timeoutMs)
        {
            TcpClient client = new TcpClient();
            try
            {
                IAsyncResult result = client.BeginConnect(host, port, null, null);
                try
                {
                    if (!result.AsyncWaitHandle.WaitOne(timeoutMs)) throw new TimeoutException("Connection timed out");
                    client.EndConnect(result);
                }
                finally { result.AsyncWaitHandle.Close(); }
                client.NoDelay = true;
                return client;
            }
            catch
            {
                client.Close();
                throw;
            }
        }

        private static bool ParseTarget(string target, string[] lines, bool connect, out string host, out int port, out string path)
        {
            host = null; port = connect ? 443 : 80; path = target;
            if (connect)
            {
                int colon = target.LastIndexOf(':');
                host = colon > 0 ? target.Substring(0, colon) : target;
                int parsed;
                if (colon > 0 && Int32.TryParse(target.Substring(colon + 1), out parsed)) port = parsed;
                return !String.IsNullOrWhiteSpace(host);
            }
            Uri uri;
            if (Uri.TryCreate(target, UriKind.Absolute, out uri))
            {
                host = uri.Host;
                port = uri.IsDefaultPort ? (uri.Scheme.Equals("https", StringComparison.OrdinalIgnoreCase) ? 443 : 80) : uri.Port;
                path = String.IsNullOrEmpty(uri.PathAndQuery) ? "/" : uri.PathAndQuery;
                return true;
            }
            foreach (string line in lines)
            {
                if (!line.StartsWith("Host:", StringComparison.OrdinalIgnoreCase)) continue;
                string value = line.Substring(5).Trim();
                int colon = value.LastIndexOf(':');
                host = colon > 0 ? value.Substring(0, colon) : value;
                int parsed;
                if (colon > 0 && Int32.TryParse(value.Substring(colon + 1), out parsed)) port = parsed;
                return !String.IsNullOrWhiteSpace(host);
            }
            return false;
        }

        private static byte[] RewriteDirectRequest(string[] lines, string path, byte[] original, int headerLength)
        {
            string[] first = lines[0].Split(' ');
            lines[0] = first[0] + " " + path + " " + first[2];
            string header = String.Join("\r\n", lines);
            byte[] head = Encoding.ASCII.GetBytes(header);
            byte[] result = new byte[head.Length + original.Length - headerLength];
            Buffer.BlockCopy(head, 0, result, 0, head.Length);
            if (original.Length > headerLength) Buffer.BlockCopy(original, headerLength, result, head.Length, original.Length - headerLength);
            return result;
        }

        private static void SendEstablished(NetworkStream stream)
        {
            byte[] response = Encoding.ASCII.GetBytes("HTTP/1.1 200 Connection Established\r\nProxy-Agent: CodexAutoProxy/1.0\r\n\r\n");
            stream.Write(response, 0, response.Length);
        }

        private static void SendRemainder(byte[] request, int headerLength, NetworkStream output)
        {
            if (request.Length > headerLength) output.Write(request, headerLength, request.Length - headerLength);
        }

        private void Relay(NetworkStream incoming, NetworkStream outgoing, TcpClient remote, RouteMode route, int port)
        {
            Stopwatch elapsed = Stopwatch.StartNew();
            long uploadBytes = 0;
            string uploadError = "pending";
            Thread upload = new Thread(delegate() { uploadBytes = Copy(incoming, outgoing, out uploadError); });
            upload.IsBackground = true;
            upload.Start();
            string downloadError;
            long downloadBytes = Copy(outgoing, incoming, out downloadError);
            try { remote.Close(); } catch { }
            upload.Join(500);
            detector.ReportEmptyTunnel(route, elapsed.ElapsedMilliseconds, uploadBytes, downloadBytes);
            if (downloadBytes == 0 || downloadError != "none" || elapsed.ElapsedMilliseconds < 3000)
                Diagnostic.Network("tunnel_closed route=" + route + " port=" + port +
                    " elapsedMs=" + elapsed.ElapsedMilliseconds + " uploadBytes=" + uploadBytes +
                    " downloadBytes=" + downloadBytes + " uploadError=" + uploadError + " downloadError=" + downloadError);
        }

        private static long Copy(Stream source, Stream destination, out string failure)
        {
            long total = 0;
            failure = "none";
            try
            {
                byte[] buffer = new byte[32768];
                int read;
                while ((read = source.Read(buffer, 0, buffer.Length)) > 0)
                {
                    destination.Write(buffer, 0, read);
                    total += read;
                    destination.Flush();
                }
            }
            catch (Exception error) { failure = Diagnostic.ErrorType(error); }
            try { destination.Close(); } catch { }
            return total;
        }

        public void Dispose()
        {
            stopping = true;
            if (listener != null) listener.Stop();
            if (acceptThread != null && acceptThread.IsAlive) acceptThread.Join(1000);
        }
    }

    internal sealed class ManagedUpstream : IDisposable
    {
        private readonly Settings settings;
        private readonly string statePath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "managed-upstream.pid");
        private readonly Queue<DateTime> starts = new Queue<DateTime>();
        private Process owned;
        private bool disposed;
        public ManagedUpstream(Settings value) { settings = value; }
        public bool Enabled { get { return !String.IsNullOrEmpty(settings.UpstreamExe) && !String.IsNullOrEmpty(settings.UpstreamConfig); } }
        public void EnsureRunning()
        {
            if (disposed || !Enabled) return;
            if (owned != null && !owned.HasExited) return;
            if (owned != null) { owned.Dispose(); owned = null; }
            string root = Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            string config = Path.GetFullPath(settings.UpstreamConfig);
            if (!config.StartsWith(root, StringComparison.OrdinalIgnoreCase) || !File.Exists(config) || !File.Exists(settings.UpstreamExe))
                throw new InvalidDataException("专用出口配置或 Clash 内核不存在，请重新配置专用节点。");
            if (File.Exists(statePath))
            {
                string[] saved = File.ReadAllLines(statePath);
                int pid; long ticks;
                if (saved.Length >= 3 && Int32.TryParse(saved[0], out pid) && Int64.TryParse(saved[1], out ticks) && saved[2] == config)
                    try
                    {
                        Process previous = Process.GetProcessById(pid);
                        if (previous.StartTime.ToUniversalTime().Ticks == ticks &&
                            String.Equals(previous.MainModule.FileName, settings.UpstreamExe, StringComparison.OrdinalIgnoreCase))
                        { owned = previous; Diagnostic.Write("Adopted existing managed upstream pid=" + pid); return; }
                        previous.Dispose();
                    }
                    catch (ArgumentException) { }
            }
            while (starts.Count > 0 && starts.Peek() < DateTime.UtcNow.AddMinutes(-1)) starts.Dequeue();
            if (starts.Count >= 3) return;
            // Never adopt or terminate an unrelated listener merely because its port matches.
            using (TcpClient check = new TcpClient())
            {
                IAsyncResult attempt = check.BeginConnect(settings.ClashHost, settings.ClashPort, null, null);
                try { if (attempt.AsyncWaitHandle.WaitOne(250) && check.Connected) throw new IOException("专用出口端口已被其他程序占用。"); }
                finally { attempt.AsyncWaitHandle.Close(); }
            }
            ProcessStartInfo info = new ProcessStartInfo(settings.UpstreamExe);
            info.Arguments = "-d \"" + Path.GetDirectoryName(config) + "\" -f \"" + config + "\"";
            info.WorkingDirectory = Path.GetDirectoryName(config);
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            info.WindowStyle = ProcessWindowStyle.Hidden;
            info.RedirectStandardOutput = true;
            info.RedirectStandardError = true;
            starts.Enqueue(DateTime.UtcNow);
            owned = new Process();
            owned.StartInfo = info;
            owned.OutputDataReceived += delegate { };
            owned.ErrorDataReceived += delegate { };
            owned.Start();
            owned.BeginOutputReadLine();
            owned.BeginErrorReadLine();
            File.WriteAllLines(statePath, new[] { owned.Id.ToString(), owned.StartTime.ToUniversalTime().Ticks.ToString(), config });
            Diagnostic.Write("Started managed upstream pid=" + owned.Id + " port=" + settings.ClashPort);
        }
        public void Dispose()
        {
            if (disposed) return;
            disposed = true;
            if (owned != null)
            {
                try { if (!owned.HasExited) { owned.Kill(); owned.WaitForExit(3000); } } catch { }
                owned.Dispose(); owned = null;
            }
            if (Enabled) try { File.Delete(statePath); } catch { }
        }
    }

    internal sealed class TrayContext : ApplicationContext
    {
        private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private readonly Settings settings;
        private readonly RouteDetector detector;
        private readonly ProxyServer proxy;
        private readonly ManagedUpstream upstream;
        private DateTime nextUpstreamCheck = DateTime.MinValue;
        private readonly NotifyIcon icon;
        private readonly ToolStripMenuItem statusItem;
        private readonly ToolStripMenuItem autoItem;
        private readonly ToolStripMenuItem directItem;
        private readonly ToolStripMenuItem clashItem;
        private readonly ToolStripMenuItem startupItem;
        private readonly ToolStripMenuItem launchOnStartItem;
        private readonly System.Windows.Forms.Timer uiTimer;
        private readonly Queue<string> commands = new Queue<string>();
        private readonly Thread pipeThread;
        private volatile bool closing;
        private DateTime nextStatusWrite = DateTime.MinValue;
        private readonly string startedUtc = DateTime.UtcNow.ToString("o");

        public TrayContext(Settings value, bool launchNow)
        {
            settings = value;
            upstream = new ManagedUpstream(settings);
            try
            {
            upstream.EnsureRunning();
            detector = new RouteDetector(settings);
            proxy = new ProxyServer(settings, detector);
            detector.Start();
            proxy.Start();
            CodexEnvironment.Disable(); // Migrate legacy user-level variables; new launches use process-only variables.
            SystemEvents.SessionEnding += OnSessionEnding;
            SystemEvents.PowerModeChanged += OnPowerModeChanged;
            AppDomain.CurrentDomain.ProcessExit += OnProcessExit;

            ContextMenuStrip menu = new ContextMenuStrip();
            statusItem = new ToolStripMenuItem("正在检测网络");
            statusItem.Enabled = false;
            menu.Items.Add(statusItem);
            menu.Items.Add(new ToolStripSeparator());
            autoItem = new ToolStripMenuItem("自动选择", null, delegate { SetMode(RouteMode.Auto); });
            directItem = new ToolStripMenuItem("强制直连", null, delegate { SetMode(RouteMode.Direct); });
            clashItem = new ToolStripMenuItem("强制 Clash", null, delegate { SetMode(RouteMode.Clash); });
            menu.Items.Add(autoItem);
            menu.Items.Add(directItem);
            menu.Items.Add(clashItem);
            menu.Items.Add(new ToolStripMenuItem("立即检测", null, delegate { detector.ProbeNow(); }));
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(new ToolStripMenuItem("启动 Codex", null, delegate { LaunchCodex(); }));
            menu.Items.Add(new ToolStripMenuItem("设置 Clash 端口…", null, delegate { ShowSettings(); }));
            launchOnStartItem = new ToolStripMenuItem("代理启动时同时启动 Codex", null, delegate
            {
                settings.LaunchCodexOnStart = !settings.LaunchCodexOnStart;
                settings.Save();
                launchOnStartItem.Checked = settings.LaunchCodexOnStart;
            });
            launchOnStartItem.Checked = settings.LaunchCodexOnStart;
            menu.Items.Add(launchOnStartItem);
            startupItem = new ToolStripMenuItem("随 Windows 登录启动代理", null, delegate { ToggleStartup(); });
            startupItem.Checked = IsStartupEnabled();
            menu.Items.Add(startupItem);
            menu.Items.Add(new ToolStripMenuItem("打开安装目录", null, delegate { Process.Start(AppDomain.CurrentDomain.BaseDirectory); }));
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(new ToolStripMenuItem("退出", null, delegate { ExitThread(); }));

            icon = new NotifyIcon();
            icon.Icon = SystemIcons.Information;
            icon.Text = "Codex 自动代理";
            icon.ContextMenuStrip = menu;
            icon.Visible = true;
            icon.DoubleClick += delegate { LaunchCodex(); };

            pipeThread = new Thread(PipeLoop);
            pipeThread.IsBackground = true;
            pipeThread.Start();

            uiTimer = new System.Windows.Forms.Timer();
            uiTimer.Interval = 500;
            uiTimer.Tick += UiTick;
            uiTimer.Start();
            SetMode(RouteMode.Auto);
            if (launchNow)
            {
                Thread launchWorker = new Thread(delegate()
                {
                    // Clash may be starting at the same time. Keep the tray responsive.
                    DateTime deadline = DateTime.UtcNow.AddSeconds(30);
                    while (!closing && DateTime.UtcNow < deadline)
                    {
                        try
                        {
                            using (TcpClient ready = new TcpClient())
                            {
                                IAsyncResult attempt = ready.BeginConnect(settings.ClashHost, settings.ClashPort, null, null);
                                if (attempt.AsyncWaitHandle.WaitOne(500) && ready.Connected) break;
                            }
                        }
                        catch { }
                        if (detector.DirectAvailable) break;
                        Thread.Sleep(500);
                    }
                    if (!closing) Enqueue("launch");
                });
                launchWorker.IsBackground = true;
                launchWorker.Start();
            }
            }
            catch
            {
                closing = true;
                SystemEvents.SessionEnding -= OnSessionEnding;
                SystemEvents.PowerModeChanged -= OnPowerModeChanged;
                AppDomain.CurrentDomain.ProcessExit -= OnProcessExit;
                if (uiTimer != null) uiTimer.Stop();
                if (icon != null) { icon.Visible = false; icon.Dispose(); }
                if (proxy != null) proxy.Dispose();
                if (detector != null) detector.Dispose();
                upstream.Dispose();
                throw;
            }
        }

        private void UiTick(object sender, EventArgs e)
        {
            if (closing) return;
            if (DateTime.UtcNow >= nextUpstreamCheck)
            {
                nextUpstreamCheck = DateTime.UtcNow.AddSeconds(5);
                try { upstream.EnsureRunning(); }
                catch (Exception error) { Diagnostic.Network("Managed upstream restart failed: " + Diagnostic.ErrorType(error)); }
            }
            string command = null;
            lock (commands) { if (commands.Count > 0) command = commands.Dequeue(); }
            if (command == "launch") LaunchCodex();
            else if (command == "exit") ExitThread();
            if (closing) return;
            RouteMode effective = detector.EffectiveRoute;
            statusItem.Text = "当前：" + (effective == RouteMode.Direct ? "直连" : "Clash") + " · " + detector.Detail;
            string tip = "Codex 自动代理：" + (effective == RouteMode.Direct ? "直连" : "Clash");
            icon.Text = tip.Length > 63 ? tip.Substring(0, 63) : tip;
            if (DateTime.UtcNow >= nextStatusWrite)
            {
                nextStatusWrite = DateTime.UtcNow.AddSeconds(5);
                try
                {
                    string json = "{\"pid\":" + Process.GetCurrentProcess().Id +
                        ",\"startedUtc\":\"" + startedUtc + "\",\"updatedUtc\":\"" + DateTime.UtcNow.ToString("o") +
                        "\",\"lastProbeUtc\":\"" + detector.LastProbeUtc + "\",\"mode\":\"" + detector.Mode +
                        "\",\"route\":\"" + detector.EffectiveRoute + "\",\"googleRoute\":\"" +
                        RoutePolicy.Preferred(detector.Mode, detector.EffectiveRoute, "accounts.google.com") +
                        "\",\"listenPort\":" + settings.ListenPort + ",\"clashPort\":" + settings.ClashPort + "}";
                    File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "status.json"), json, new UTF8Encoding(false));
                }
                catch { }
            }
        }

        private void SetMode(RouteMode mode)
        {
            detector.Mode = mode;
            autoItem.Checked = mode == RouteMode.Auto;
            directItem.Checked = mode == RouteMode.Direct;
            clashItem.Checked = mode == RouteMode.Clash;
        }

        private static bool IsDesktopPath(string path)
        {
            return !String.IsNullOrEmpty(path) &&
                path.IndexOf("\\bin\\", StringComparison.OrdinalIgnoreCase) < 0 &&
                (Path.GetFileName(path).Equals("ChatGPT.exe", StringComparison.OrdinalIgnoreCase) ||
                 Path.GetFileName(path).Equals("Codex.exe", StringComparison.OrdinalIgnoreCase));
        }

        private string ResolveDesktopExecutable()
        {
            // Prefer the configured desktop application; CLI executables cannot open the GUI.
            if (IsDesktopPath(settings.CodexExe) && File.Exists(settings.CodexExe) &&
                settings.CodexExe.IndexOf("\\WindowsApps\\", StringComparison.OrdinalIgnoreCase) < 0) return settings.CodexExe;
            // Ask Windows for the registered package, rather than starting a stale version directory.
            try
            {
                ProcessStartInfo query = new ProcessStartInfo("powershell.exe",
                    "-NoProfile -NonInteractive -Command \"Get-AppxPackage -Name OpenAI.Codex | ForEach-Object { Join-Path $_.InstallLocation 'app\\ChatGPT.exe' }\"");
                query.UseShellExecute = false;
                query.CreateNoWindow = true;
                query.WindowStyle = ProcessWindowStyle.Hidden;
                query.RedirectStandardOutput = true;
                query.RedirectStandardError = true;
                using (Process process = Process.Start(query))
                {
                    var output = process.StandardOutput.ReadToEndAsync();
                    var errors = process.StandardError.ReadToEndAsync();
                    if (process.WaitForExit(8000))
                        foreach (string line in output.Result.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
                        {
                            string candidate = line.Trim();
                            if (IsDesktopPath(candidate) && File.Exists(candidate)) return candidate;
                        }
                    else process.Kill();
                }
            }
            catch (Exception ex) { Diagnostic.Write("Desktop package discovery failed: " + ex.GetType().Name); }
            foreach (string name in new[] { "ChatGPT", "Codex" })
            {
                foreach (Process running in Process.GetProcessesByName(name))
                {
                    using (running)
                    {
                        try
                        {
                            string path = running.MainModule.FileName;
                            if (IsDesktopPath(path) && path.IndexOf("OpenAI", StringComparison.OrdinalIgnoreCase) >= 0) return path;
                        }
                        catch { }
                    }
                }
            }
            // Microsoft Store updates change the application directory.
            try
            {
                string appRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "WindowsApps");
                List<DirectoryInfo> packages = new List<DirectoryInfo>(new DirectoryInfo(appRoot).GetDirectories("OpenAI.Codex_*"));
                packages.Sort(delegate(DirectoryInfo a, DirectoryInfo b) { return b.LastWriteTimeUtc.CompareTo(a.LastWriteTimeUtc); });
                foreach (DirectoryInfo package in packages)
                    foreach (string file in new[] { "ChatGPT.exe", "Codex.exe" })
                    {
                        string path = Path.Combine(package.FullName, "app", file);
                        if (File.Exists(path)) return path;
                    }
            }
            catch { }
            if (IsDesktopPath(settings.CodexExe) && File.Exists(settings.CodexExe)) return settings.CodexExe;
            return null;
        }

        private void LaunchCodex()
        {
            try
            {
                string executable = ResolveDesktopExecutable();
                if (executable == null) throw new FileNotFoundException("找不到 Codex 桌面应用，请重新运行安装器选择 ChatGPT.exe 或 Codex.exe。");
                ProcessStartInfo start = new ProcessStartInfo(executable);
                start.WorkingDirectory = Path.GetDirectoryName(executable);
                start.UseShellExecute = false;
                string proxyUrl = "http://127.0.0.1:" + settings.ListenPort;
                start.EnvironmentVariables["HTTP_PROXY"] = proxyUrl;
                start.EnvironmentVariables["HTTPS_PROXY"] = proxyUrl;
                start.EnvironmentVariables["WS_PROXY"] = proxyUrl;
                start.EnvironmentVariables["WSS_PROXY"] = proxyUrl;
                start.EnvironmentVariables["ALL_PROXY"] = proxyUrl;
                start.EnvironmentVariables["NO_PROXY"] = "127.0.0.1,localhost,::1";
                Process.Start(start);
            }
            catch (Exception ex)
            {
                MessageBox.Show("无法启动 Codex：\r\n" + ex.Message, "Codex 自动代理", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void ShowSettings()
        {
            using (SettingsForm form = new SettingsForm(settings, IsStartupEnabled()))
            {
                if (form.ShowDialog() != DialogResult.OK) return;
                if (upstream.Enabled && form.ClashPort != settings.ClashPort)
                {
                    MessageBox.Show("当前使用 Codex 专用出口，请通过专用节点配置脚本修改或关闭，再更改端口。", "Codex 自动代理", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }
                if (form.ClashPort == settings.ListenPort)
                {
                    MessageBox.Show("Clash 端口不能与本地桥接端口相同，请重新设置。", "Codex 自动代理", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }
                settings.ClashPort = form.ClashPort;
                try
                {
                    settings.Save();
                    SetStartup(form.StartWithWindows);
                    startupItem.Checked = IsStartupEnabled();
                    detector.ProbeNow();
                    icon.ShowBalloonTip(1800, "Codex 自动代理", "Clash 端口已改为 " + settings.ClashPort, ToolTipIcon.Info);
                }
                catch (Exception ex)
                {
                    MessageBox.Show("无法保存设置：\r\n" + ex.Message, "Codex 自动代理", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }

        private void ToggleStartup()
        {
            SetStartup(!startupItem.Checked);
            startupItem.Checked = IsStartupEnabled();
        }

        private static void SetStartup(bool enabled)
        {
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(RunKey))
            {
                if (enabled) key.SetValue("CodexAutoProxy", "\"" + Assembly.GetExecutingAssembly().Location + "\"");
                else key.DeleteValue("CodexAutoProxy", false);
            }
        }

        private static bool IsStartupEnabled()
        {
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(RunKey))
            {
                return key != null && key.GetValue("CodexAutoProxy") != null;
            }
        }

        private void PipeLoop()
        {
            while (!closing)
            {
                try
                {
                    using (NamedPipeServerStream pipe = new NamedPipeServerStream("CodexAutoProxy.Control", PipeDirection.In, 1))
                    {
                        pipe.WaitForConnection();
                        using (StreamReader reader = new StreamReader(pipe, Encoding.UTF8))
                        {
                            string command = reader.ReadLine();
                            if (!String.IsNullOrEmpty(command)) Enqueue(command.Trim().ToLowerInvariant());
                        }
                    }
                }
                catch { if (!closing) Thread.Sleep(200); }
            }
        }

        private void Enqueue(string command)
        {
            lock (commands) commands.Enqueue(command);
        }

        private void OnSessionEnding(object sender, SessionEndingEventArgs e)
        {
            CrashGuardian.MarkNormalExit();
            upstream.Dispose();
            try { CodexEnvironment.Disable(); } catch { }
        }

        private void OnPowerModeChanged(object sender, PowerModeChangedEventArgs e)
        {
            if (e.Mode == PowerModes.Resume && !closing)
            {
                Diagnostic.Write("Windows resumed; refreshing route detection.");
                try { detector.ProbeNow(); } catch (ObjectDisposedException) { }
            }
        }

        private void OnProcessExit(object sender, EventArgs e)
        {
            upstream.Dispose();
            try { CodexEnvironment.Disable(); } catch { }
        }

        protected override void ExitThreadCore()
        {
            CrashGuardian.MarkNormalExit();
            closing = true;
            SystemEvents.SessionEnding -= OnSessionEnding;
            SystemEvents.PowerModeChanged -= OnPowerModeChanged;
            AppDomain.CurrentDomain.ProcessExit -= OnProcessExit;
            uiTimer.Stop();
            icon.Visible = false;
            icon.Dispose();
            try { CodexEnvironment.Disable(); } catch { }
            proxy.Dispose();
            detector.Dispose();
            upstream.Dispose();
            base.ExitThreadCore();
        }
    }

    internal static class CrashGuardian
    {
        private static EventWaitHandle normalExit;
        internal static string EventName(int pid, long ticks)
        {
            return "Local\\CodexAutoProxy.NormalExit." + pid + "." + ticks;
        }
        public static void Start()
        {
            using (Process current = Process.GetCurrentProcess())
            {
                long ticks = current.StartTime.ToUniversalTime().Ticks;
                normalExit = new EventWaitHandle(false, EventResetMode.ManualReset, EventName(current.Id, ticks));
                ProcessStartInfo info = new ProcessStartInfo(Assembly.GetExecutingAssembly().Location,
                    "--watch-parent " + current.Id + " " + ticks);
                info.UseShellExecute = false;
                info.CreateNoWindow = true;
                info.WindowStyle = ProcessWindowStyle.Hidden;
                using (Process watcher = Process.Start(info)) { }
            }
        }
        public static void MarkNormalExit()
        {
            if (normalExit != null) try { normalExit.Set(); } catch { }
        }
        internal static bool ParentMatches(Process parent, long ticks)
        {
            return parent.StartTime.ToUniversalTime().Ticks == ticks;
        }
        internal static bool AllowRecovery(string path, DateTime now)
        {
            List<long> recent = new List<long>();
            if (File.Exists(path)) foreach (string line in File.ReadAllLines(path))
            {
                long ticks;
                if (Int64.TryParse(line, out ticks) && ticks <= now.Ticks && ticks > now.AddMinutes(-1).Ticks) recent.Add(ticks);
            }
            if (recent.Count >= 3) return false;
            recent.Add(now.Ticks);
            File.WriteAllLines(path, recent.ConvertAll(delegate(long ticks) { return ticks.ToString(); }).ToArray());
            return true;
        }
        public static void Watch(int pid, long ticks)
        {
            WatchCore(pid, ticks, delegate { CodexEnvironment.Disable(); }, delegate
            {
                ProcessStartInfo info = new ProcessStartInfo(Assembly.GetExecutingAssembly().Location);
                info.UseShellExecute = false;
                info.CreateNoWindow = true;
                info.WindowStyle = ProcessWindowStyle.Hidden;
                using (Process replacement = Process.Start(info)) { }
            }, Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "recovery-history.txt"), "Local\\CodexAutoProxy.Singleton");
        }
        internal static void WatchCore(int pid, long ticks, Action cleanup, Action restart, string history, string mutexName)
        {
            try
            {
                using (EventWaitHandle stop = EventWaitHandle.OpenExisting(EventName(pid, ticks)))
                {
                    try
                    {
                        using (Process parent = Process.GetProcessById(pid))
                        {
                            if (!ParentMatches(parent, ticks)) return;
                            while (!parent.WaitForExit(1000)) if (stop.WaitOne(0)) return;
                        }
                    }
                    catch (ArgumentException) { }
                    if (stop.WaitOne(0)) return;
                    bool acquired = false;
                    using (Mutex lease = new Mutex(false, mutexName))
                    {
                        try { acquired = lease.WaitOne(0); }
                        catch (AbandonedMutexException) { acquired = true; }
                        if (!acquired) return;
                        try
                        {
                            cleanup();
                            Diagnostic.Write("Proxy exited unexpectedly; removed stale managed environment.");
                        }
                        finally { lease.ReleaseMutex(); }
                    }
                    if (!AllowRecovery(history, DateTime.UtcNow))
                    {
                        Diagnostic.Write("Automatic recovery stopped after three attempts in one minute.");
                        return;
                    }
                    restart();
                    Diagnostic.Write("Requested proxy recovery after unexpected exit.");
                }
            }
            catch (Exception ex) { Diagnostic.Write("Recovery watcher failed: " + ex.GetType().Name); }
        }
    }

    internal static class Program
    {
        private static Mutex singleton;

        [STAThread]
        private static void Main(string[] args)
        {
            CodexEnvironment.PrepareCurrentProcess();
            if (args.Length == 3 && args[0] == "--watch-parent")
            {
                int parentId;
                long parentTicks;
                if (Int32.TryParse(args[1], out parentId) && Int64.TryParse(args[2], out parentTicks)) CrashGuardian.Watch(parentId, parentTicks);
                return;
            }
            bool launch = HasArgument(args, "--launch");
            bool exit = HasArgument(args, "--exit");
            bool created;
            singleton = new Mutex(true, "Local\\CodexAutoProxy.Singleton", out created);
            if (!created)
            {
                SendCommand(exit ? "exit" : (launch ? "launch" : "show"));
                return;
            }

            if (exit)
            {
                try { CodexEnvironment.Disable(); } catch { }
                return;
            }
            AppDomain.CurrentDomain.UnhandledException += delegate
            {
                Diagnostic.Write("Unhandled exception; restoring managed environment.");
                try { CodexEnvironment.Disable(); } catch { }
            };
            try
            {
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                string configPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "config.ini");
                Settings settings = Settings.Load(configPath);
                Diagnostic.Write("Starting proxy on loopback port " + settings.ListenPort + "; Clash port " + settings.ClashPort + ".");
                TrayContext context = new TrayContext(settings, !HasArgument(args, "--no-launch") && (launch || settings.LaunchCodexOnStart));
                CrashGuardian.Start();
                Application.Run(context);
            }
            catch (Exception ex)
            {
                Diagnostic.Write("Startup failed: " + ex.GetType().Name);
                MessageBox.Show(ex.Message, "Codex 自动代理", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally
            {
                CrashGuardian.MarkNormalExit();
                // Also covers failures midway through tray construction.
                try { CodexEnvironment.Disable(); } catch { }
                Diagnostic.Write("Proxy stopped; managed environment restored.");
                if (singleton != null) singleton.ReleaseMutex();
            }
        }

        private static bool HasArgument(string[] args, string value)
        {
            foreach (string arg in args) if (arg.Equals(value, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        private static void SendCommand(string command)
        {
            try
            {
                using (NamedPipeClientStream pipe = new NamedPipeClientStream(".", "CodexAutoProxy.Control", PipeDirection.Out))
                {
                    pipe.Connect(2000);
                    using (StreamWriter writer = new StreamWriter(pipe, new UTF8Encoding(false)))
                    {
                        writer.WriteLine(command);
                        writer.Flush();
                    }
                }
            }
            catch { }
        }
    }
}
