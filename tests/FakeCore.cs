using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text.RegularExpressions;
using System.Threading;
internal static class FakeCore {
    static void Main(string[] args) {
        int index=Array.IndexOf(args,"-f");
        string text=File.ReadAllText(args[index+1]);
        int port=Int32.Parse(Regex.Match(text,@"mixed-port:\s*(\d+)").Groups[1].Value);
        var listener=new TcpListener(IPAddress.Loopback,port); listener.Start();
        while(true) { using(var client=listener.AcceptTcpClient()) {} Thread.Sleep(1); }
    }
}
