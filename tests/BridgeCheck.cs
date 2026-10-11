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
        }
    }
}
