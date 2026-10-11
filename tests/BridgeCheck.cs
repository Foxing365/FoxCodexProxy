using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
namespace CodexAutoProxy {
    class BridgeCheck {
        static int FreePort() { var l=new TcpListener(IPAddress.Loopback,0); l.Start(); int p=((IPEndPoint)l.LocalEndpoint).Port; l.Stop(); return p; }
        static void Headers(NetworkStream s) { int state=0; while(state<4) { int b=s.ReadByte(); if(b<0) throw new Exception("early EOF"); int expected=state%2==0?13:10; state=b==expected?state+1:0; } }
        static void Main() {
            int upstream=FreePort(), bridge=FreePort();
            var listener=new TcpListener(IPAddress.Loopback,upstream); listener.Start();
            var server=new Thread(delegate() { using(var c=listener.AcceptTcpClient()) { var s=c.GetStream(); Headers(s); byte[] h=Encoding.ASCII.GetBytes("HTTP/1.1 200 Connection Established\r\n\r\n"); s.Write(h,0,h.Length); Thread.Sleep(17000); s.WriteByte(42); } }); server.IsBackground=true; server.Start();
            var settings=new Settings(); settings.ClashPort=upstream; settings.ListenPort=bridge;
            if(!settings.LaunchCodexOnStart) throw new Exception("autolaunch default false");
            using(var detector=new RouteDetector(settings)) {
                detector.Mode=RouteMode.Clash;
                using(var proxy=new ProxyServer(settings,detector)) {
                    proxy.Start();
                    using(var client=new TcpClient("127.0.0.1",bridge)) {
                        client.ReceiveTimeout=22000; var s=client.GetStream();
                        byte[] h=Encoding.ASCII.GetBytes("CONNECT test.invalid:443 HTTP/1.1\r\nHost: test.invalid:443\r\n\r\n"); s.Write(h,0,h.Length); Headers(s);
                        var watch=System.Diagnostics.Stopwatch.StartNew();
                        if(s.ReadByte()!=42 || watch.ElapsedMilliseconds<16000) throw new Exception("tunnel idle regression");
                        Console.WriteLine("LONG_TUNNEL_OK ms="+watch.ElapsedMilliseconds);
                    }
                }
            }
            listener.Stop();
            string cfg=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"test-settings.ini");
            File.WriteAllText(cfg,"CodexExe=desktop.exe\nLaunchCodexOnStart=false\n");
            var loaded=Settings.Load(cfg); if(loaded.LaunchCodexOnStart) throw new Exception("false setting ignored");
            loaded.LaunchCodexOnStart=true; loaded.Save();
            if(!Settings.Load(cfg).LaunchCodexOnStart) throw new Exception("setting not saved");
            Console.WriteLine("AUTOLAUNCH_SETTING_OK");
            loaded.PreferClash=true; loaded.UpstreamExe="test-core.exe"; loaded.UpstreamConfig="test-config.yaml"; loaded.Save();
            var persisted=Settings.Load(cfg);
            if(!persisted.PreferClash || persisted.UpstreamExe!="test-core.exe" || persisted.UpstreamConfig!="test-config.yaml") throw new Exception("dedicated setting not saved");
            using(var health=new RouteDetector(new Settings())) {
                var record=typeof(RouteDetector).GetMethod("RecordProbe",System.Reflection.BindingFlags.NonPublic|System.Reflection.BindingFlags.Instance);
                record.Invoke(health,new object[]{405}); record.Invoke(health,new object[]{405});
                if(health.DirectAvailable) throw new Exception("direct enabled prematurely");
                record.Invoke(health,new object[]{405}); if(!health.DirectAvailable) throw new Exception("direct health never enabled");
                health.ReportEmptyTunnel(RouteMode.Direct,400,458,0);
                record.Invoke(health,new object[]{405}); record.Invoke(health,new object[]{405}); record.Invoke(health,new object[]{405});
                if(health.DirectAvailable) throw new Exception("direct cooldown ignored");
            }
            Console.WriteLine("ROUTE_HEALTH_COOLDOWN_OK");
            int corePort=FreePort();
            string coreConfig=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"fake-core.yaml");
            File.WriteAllText(coreConfig,"mixed-port: "+corePort);
            var coreSettings=new Settings(); coreSettings.ClashPort=corePort; coreSettings.PreferClash=true;
            coreSettings.UpstreamExe=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"FakeCore.exe"); coreSettings.UpstreamConfig=coreConfig;
            int firstPid;
            using(var managed=new ManagedUpstream(coreSettings)) {
                managed.EnsureRunning(); Thread.Sleep(300);
                string state=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"managed-upstream.pid");
                firstPid=Int32.Parse(File.ReadAllLines(state)[0]);
                using(var child=System.Diagnostics.Process.GetProcessById(firstPid)) { child.Kill(); child.WaitForExit(); }
                managed.EnsureRunning(); Thread.Sleep(300);
                int secondPid=Int32.Parse(File.ReadAllLines(state)[0]);
                if(secondPid==firstPid) throw new Exception("managed core not restarted");
                // A fresh tray can adopt the exact recorded process after its predecessor crashes.
                using(var adopted=new ManagedUpstream(coreSettings)) { adopted.EnsureRunning(); }
                try { using(var child=System.Diagnostics.Process.GetProcessById(secondPid)) {
                    if(!child.WaitForExit(3000)) throw new Exception("adopted core not cleaned up");
                } } catch(ArgumentException) { /* Already removed from the process table. */ }
            }
            Console.WriteLine("MANAGED_CORE_START_RECOVER_ADOPT_STOP_OK");
        }
    }
}
