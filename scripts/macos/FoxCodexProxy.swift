import Foundation
import Darwin

// Opaque CONNECT tunnels: never decrypt TLS or replay an established request.
@_silgen_name("launch_activate_socket")
func launchSocket(_ name: UnsafePointer<CChar>, _ fds: UnsafeMutablePointer<UnsafeMutablePointer<Int32>?>, _ count: UnsafeMutablePointer<Int>) -> Int32
struct Failure: Error, CustomStringConvertible { let description: String }
let home = FileManager.default.homeDirectoryForCurrentUser
let support = home.appendingPathComponent("Library/Application Support/FoxCodexProxy")
let label = "com.openai.codex-auto-proxy"
let markerStart = "# BEGIN fox-codex-proxy-macos"
let markerEnd = "# END fox-codex-proxy-macos"
let proxyKeys: Set<String> = ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "WS_PROXY", "WSS_PROXY", "http_proxy", "https_proxy", "all_proxy", "ws_proxy", "wss_proxy", "NO_PROXY", "no_proxy"]
let args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String, _ fallback: String) -> String { if let i = args.firstIndex(of: name), i+1 < args.count { return args[i+1] }; return fallback }
func number(_ name: String, _ fallback: Int, range: ClosedRange<Int>) throws -> Int {
    guard let n = Int(option(name, String(fallback))), range.contains(n) else { throw Failure(description: "Invalid \(name)") }; return n
}
let logLock = NSLock()
var logWindow = Date(); var logCount = 0
func log(_ message: String, detail: Bool = false) {
    logLock.lock(); defer { logLock.unlock() }
    if Date().timeIntervalSince(logWindow) >= 60 { logWindow = Date(); logCount = 0 }
    if detail { guard logCount < 10 else { return }; logCount += 1 }
    fputs("\(ISO8601DateFormatter().string(from: Date())) \(message)\n", stderr)
}
func error(_ operation: String) -> Failure { Failure(description: "\(operation): errno=\(errno)") }
func timeout(_ fd: Int32, seconds: Int) {
    var tv = timeval(tv_sec: seconds, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
}
func keepAlive(_ fd: Int32) {
    var one: Int32 = 1; setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &one, 4)
    var seconds: Int32 = 30; setsockopt(fd, IPPROTO_TCP, TCP_KEEPALIVE, &seconds, 4)
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, 4)
}
func addresses(_ host: String, _ port: Int) throws -> UnsafeMutablePointer<addrinfo> {
    var hints = addrinfo(); hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM; hints.ai_protocol = IPPROTO_TCP
    var result: UnsafeMutablePointer<addrinfo>?
    let rc = getaddrinfo(host, String(port), &hints, &result)
    guard rc == 0, let list = result else { throw Failure(description: "DNS lookup failed: \(rc)") }; return list
}
func connectTCP(_ host: String, _ port: Int, seconds: Int = 8) throws -> Int32 {
    let list = try addresses(host, port); defer { freeaddrinfo(list) }
    var next: UnsafeMutablePointer<addrinfo>? = list
    let deadline = Date().addingTimeInterval(TimeInterval(seconds))
    while let node = next {
        next = node.pointee.ai_next
        let a = node.pointee; let fd = socket(a.ai_family, a.ai_socktype, a.ai_protocol)
        if fd < 0 { continue }
        let original = fcntl(fd, F_GETFL, 0); _ = fcntl(fd, F_SETFL, original | O_NONBLOCK)
        let rc = Darwin.connect(fd, a.ai_addr, a.ai_addrlen)
        var ok = rc == 0
        if !ok && errno == EINPROGRESS {
            var p = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let remaining = max(0, Int(deadline.timeIntervalSinceNow * 1000))
            if poll(&p, 1, Int32(remaining)) > 0 {
                var e: Int32 = 0; var length = socklen_t(4)
                if getsockopt(fd, SOL_SOCKET, SO_ERROR, &e, &length) == 0 && e == 0 { ok = true }
            }
        }
        if ok { _ = fcntl(fd, F_SETFL, original); timeout(fd, seconds: 8); keepAlive(fd); return fd }
        close(fd)
        if Date() >= deadline { break }
    }
    throw Failure(description: "TCP connection failed")
}
func sendAll(_ fd: Int32, _ data: Data) throws {
    try data.withUnsafeBytes { raw in
        var offset = 0
        while offset < raw.count {
            let n = Darwin.send(fd, raw.baseAddress!.advanced(by: offset), raw.count-offset, 0)
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { throw error("send") }; offset += n
        }
    }
}
func header(_ fd: Int32) throws -> Data {
    var data = Data(); var b: UInt8 = 0
    while data.count < 65536 {
        let n = recv(fd, &b, 1, 0)
        if n < 0 && errno == EINTR { continue }
        guard n == 1 else { throw error("header read") }
        data.append(b)
        if data.count >= 4 && data.suffix(4) == Data([13,10,13,10]) { return data }
    }
    throw Failure(description: "Header exceeds 64 KiB")
}
func fakeDNS(_ host: String) -> Bool {
    guard let list = try? addresses(host, 443) else { return false }; defer { freeaddrinfo(list) }
    var next: UnsafeMutablePointer<addrinfo>? = list
    while let p = next {
        if p.pointee.ai_family == AF_INET {
            let ip = p.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr.bigEndian }
            if ip & 0xfffe0000 == 0xc6120000 { return true }
        }
        next = p.pointee.ai_next
    }
    return false
}
func tunEnabled() -> Bool {
    let path = "/var/run/clash-verge-service/users/\(getuid())/verge-mihomo.sock"
    let fd = socket(AF_UNIX, SOCK_STREAM, 0); guard fd >= 0 else { return false }; defer { close(fd) }; timeout(fd, seconds: 1)
    var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX); addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    guard path.utf8.count < MemoryLayout.size(ofValue: addr.sun_path) else { return false }
    withUnsafeMutableBytes(of: &addr.sun_path) { raw in path.withCString { source in _ = memcpy(raw.baseAddress!, source, path.utf8.count+1) } }
    let rc = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
    guard rc == 0 else { return false }
    do {
        try sendAll(fd, Data("GET /configs HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n".utf8))
        let h = try header(fd); guard String(decoding:h,as:UTF8.self).components(separatedBy:" ").dropFirst().first == "200" else { return false }
        var body = Data(); var buffer = [UInt8](repeating:0,count:4096)
        while body.count < 262144 { let n = recv(fd,&buffer,buffer.count,0); if n <= 0 { break }; body.append(contentsOf:buffer.prefix(n)) }
        let json = try JSONSerialization.jsonObject(with:body) as? [String:Any]
        return (json?["tun"] as? [String:Any])?["enable"] as? Bool ?? false
    } catch { return false }
}
final class Routes {
    let lock = NSLock(); let mode: String; let status: URL
    var cached: (String,String)?; var checked = Date.distantPast
    init(_ mode: String,_ status: URL) { self.mode=mode; self.status=status }
    func select(fresh: Bool = false) -> String {
        lock.lock(); defer { lock.unlock() }
        if !fresh, let c=cached, Date().timeIntervalSince(checked)<60 { return c.0 }
        var route="clash"; var reason="Direct TLS probe did not pass"
        if mode != "auto" { route=mode; reason="Explicit route; direct can still be intercepted by VPN/TUN" }
        else if tunEnabled() { reason="Clash TUN detected; use explicit mixed port" }
        else if fakeDNS("chatgpt.com") { reason="Fake-IP DNS detected; direct is not verified" }
        else {
            var passed=true
            for _ in 0..<3 {
                let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/curl")
                p.arguments=["--silent","--head","--noproxy","*","--connect-timeout","2","--max-time","3","--output","/dev/null","--write-out","%{http_code}","https://chatgpt.com/backend-api/codex/responses"]
                let out=Pipe(); p.standardOutput=out; p.standardError=FileHandle.nullDevice
                do { try p.run(); let code=String(decoding:out.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self); p.waitUntilExit()
                    if p.terminationStatus != 0 || !["200","401","405"].contains(code) { passed=false; break }
                } catch { passed=false; break }
            }
            if passed { route="direct"; reason="Three OS-route TLS/HTTP probes passed; this does not verify model stability or VPN bypass" }
        }
        checked=Date();cached=(route,reason)
        let value:[String:Any]=["mode":route,"reason":reason,"checked_at":ISO8601DateFormatter().string(from:checked),"pid":getpid()]
        if let data=try? JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]) { try? FileManager.default.createDirectory(at:status.deletingLastPathComponent(),withIntermediateDirectories:true);try? data.write(to:status,options:.atomic) }
        log("route=\(route) reason=\(reason)");return route
    }
    func invalidate() { lock.lock();checked=Date.distantPast;lock.unlock() }
}
// poll pumps both directions with bounded buffers. Clean EOF propagates only
// after buffered bytes are delivered; client half-close may await a long reply.
func relay(_ client: Int32,_ remote: Int32) throws -> (Int,Int) {
    for fd in [client,remote] { timeout(fd,seconds:0);_ = fcntl(fd,F_SETFL,fcntl(fd,F_GETFL,0)|O_NONBLOCK) }
    var toRemote=Data(),toClient=Data();var clientEOF=false,remoteEOF=false,remoteFIN=false,clientFIN=false
    var sent=0,received=0
    var buffer=[UInt8](repeating:0,count:65536)
    while true {
        if clientEOF && toRemote.isEmpty && !remoteFIN { shutdown(remote,SHUT_WR);remoteFIN=true }
        if remoteEOF && toClient.isEmpty && !clientFIN { shutdown(client,SHUT_WR);clientFIN=true }
        if clientEOF && remoteEOF && toRemote.isEmpty && toClient.isEmpty { return (sent,received) }
        var polls=[pollfd(fd:client,events:0,revents:0),pollfd(fd:remote,events:0,revents:0)]
        if !clientEOF && toRemote.count<1048576 { polls[0].events |= Int16(POLLIN) }
        if !remoteEOF && toClient.count<1048576 { polls[1].events |= Int16(POLLIN) }
        if !toClient.isEmpty { polls[0].events |= Int16(POLLOUT) }
        if !toRemote.isEmpty { polls[1].events |= Int16(POLLOUT) }
        for i in 0..<2 where polls[i].events==0 {polls[i].fd = -1}
        let rc=poll(&polls,2,1000);if rc<0 { if errno==EINTR {continue};throw error("poll") }
        for i in 0..<2 {
            if polls[i].fd < 0 {continue}
            let fd = i==0 ? client : remote
            if polls[i].revents & Int16(POLLNVAL) != 0 {throw Failure(description:"Invalid tunnel descriptor")}
            if polls[i].revents & Int16(POLLIN|POLLHUP|POLLERR) != 0 && !(i==0 ? clientEOF : remoteEOF) && (i==0 ? toRemote.count : toClient.count)<1048576 {
                let capacity=1048576-(i==0 ? toRemote.count : toClient.count)
                let n=recv(fd,&buffer,min(buffer.count,capacity),0)
                if n>0 { if i==0 {toRemote.append(contentsOf:buffer.prefix(n));sent += n} else {toClient.append(contentsOf:buffer.prefix(n));received += n} }
                else if n==0 { if i==0 {clientEOF=true} else {remoteEOF=true} }
                else if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {throw error(i==0 ? "read client" : "read upstream")}
            }
            if polls[i].revents & Int16(POLLOUT) != 0 {
                let data = i==0 ? toClient : toRemote
                if !data.isEmpty {
                    let n=data.withUnsafeBytes { Darwin.send(fd,$0.baseAddress!,$0.count,0) }
                    if n>0 { if i==0 {toClient.removeFirst(n)} else {toRemote.removeFirst(n)} }
                    else if n<0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {throw error(i==0 ? "write client" : "write upstream")}
                }
            }
        }
    }
}
final class Tracker {
    let lock=NSLock();var active=0;var last=Date()
    func change(_ amount:Int) {lock.lock();active += amount;last=Date();lock.unlock()}
    func idle(_ seconds:Int)->Bool {lock.lock();defer{lock.unlock()};return active==0 && Date().timeIntervalSince(last)>=Double(seconds)}
}
func target(_ text:String)throws->(String,Int) {
    let parts=text.split(separator:" ");guard parts.count==3,parts[0]=="CONNECT",parts[2].hasPrefix("HTTP/1.") else {throw Failure(description:"Only HTTP CONNECT is supported")}
    let value=String(parts[1]);guard let colon=value.lastIndex(of:":"),let port=Int(value[value.index(after:colon)...]),(1...65535).contains(port) else {throw Failure(description:"Invalid CONNECT target")}
    let host=String(value[..<colon]).trimmingCharacters(in:CharacterSet(charactersIn:"[]"));guard !host.isEmpty else {throw Failure(description:"Missing host")};return(host,port)
}
func handle(_ client:Int32,_ routes:Routes,_ upstream:Int) {
    defer{close(client)};keepAlive(client);timeout(client,seconds:8)
    var remote:Int32 = -1;var established=false;let began=Date();var selected="unknown"
    defer{if remote>=0 {close(remote)}}
    do {
        let h=try header(client);let first=String(decoding:h,as:UTF8.self).components(separatedBy:"\r\n")[0];let(host,port)=try target(first)
        selected=routes.select()
        let candidates=routes.mode=="auto" ? [selected,selected=="clash" ? "direct" : "clash"] : [selected]
        var response=Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8)
        var opened=false
        for route in candidates {
            do {
                remote=try connectTCP(route=="direct" ? host : "127.0.0.1",route=="direct" ? port : upstream)
                if route=="clash" {
                    try sendAll(remote,h);let reply=try header(remote)
                    let words=String(decoding:reply,as:UTF8.self).split(whereSeparator:{$0==" " || $0=="\r" || $0=="\n"})
                    guard words.count>1,words[1]=="200" else {throw Failure(description:"Upstream CONNECT rejected")};response=reply
                }
                selected=route;opened=true;break
            } catch {if remote>=0 {close(remote);remote = -1};routes.invalidate()}
        }
        guard opened else {throw Failure(description:"Both connection routes failed")}
        // From here on, never fall back or emit another HTTP response.
        established=true;try sendAll(client,response)
        let (sent,received)=try relay(client,remote)
        log("tunnel_closed route=\(selected) seconds=\(Int(Date().timeIntervalSince(began))) clientRead=\(sent) upstreamRead=\(received)",detail:true)
    } catch {
        log("tunnel_error route=\(selected) established=\(established) seconds=\(Int(Date().timeIntervalSince(began))) error=\(error)",detail:true)
        if !established {try? sendAll(client,Data("HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\nContent-Length: 0\r\n\r\n".utf8))}
    }
}
func listener(_ port:Int)throws->Int32 {
    if args.contains("--launchd-socket") {
        var fds:UnsafeMutablePointer<Int32>?;var count=0
        let rc="Listener".withCString {launchSocket($0,&fds,&count)}
        guard rc==0,count==1,let list=fds else {throw Failure(description:"launchd socket activation failed: \(rc)")}
        let fd=list[0];free(list);return fd
    }
    let fd=socket(AF_INET,SOCK_STREAM,0);guard fd>=0 else {throw error("socket")}
    var one:Int32=1;setsockopt(fd,SOL_SOCKET,SO_REUSEADDR,&one,4)
    var a=sockaddr_in();a.sin_len=UInt8(MemoryLayout<sockaddr_in>.size);a.sin_family=sa_family_t(AF_INET);a.sin_port=UInt16(port).bigEndian;a.sin_addr.s_addr=inet_addr("127.0.0.1")
    let rc=withUnsafePointer(to:&a){$0.withMemoryRebound(to:sockaddr.self,capacity:1){bind(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size))}}
    guard rc==0,listen(fd,128)==0 else {close(fd);throw error("listen")};return fd
}
func serve(_ port:Int,_ upstream:Int,_ idle:Int,_ mode:String,_ status:URL)throws {
    let fd=try listener(port);defer{close(fd)};let tracker=Tracker();let routes=Routes(mode,status)
    log("FoxCodexProxy native listening loopback=\(port) upstream=\(upstream)")
    while true {
        var p=pollfd(fd:fd,events:Int16(POLLIN),revents:0);let rc=poll(&p,1,1000)
        if rc<0 {if errno==EINTR {continue};throw error("listener poll")}
        if rc>0 {
            let client=accept(fd,nil,nil);if client<0 {continue};tracker.change(1)
            // Dispatch retains each handler until completion, unlike unowned async tasks.
            DispatchQueue.global().async {defer{tracker.change(-1)};handle(client,routes,upstream)}
        }
        if idle>0 && tracker.idle(idle) {log("No active connections; exit");return}
    }
}
func run(_ executable:String,_ arguments:[String])->(Int32,String) {
    let p=Process();p.executableURL=URL(fileURLWithPath:executable);p.arguments=arguments
    let pipe=Pipe();p.standardOutput=pipe;p.standardError=pipe
    do {try p.run();let data=pipe.fileHandleForReading.readDataToEndOfFile();p.waitUntilExit();return(p.terminationStatus,String(decoding:data,as:UTF8.self))} catch {return(1,String(describing:error))}
}
func atomicJSON(_ value:Any,_ path:URL)throws {try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]).write(to:path,options:.atomic)}
func key(_ line:String)->String? {
    let value=line.trimmingCharacters(in:.whitespaces)
    guard !value.hasPrefix("#"),let index=value.firstIndex(of:"=") else{return nil}
    return String(value[..<index]).trimmingCharacters(in:.whitespaces)
}
func envText(_ path:URL)throws->String { if !FileManager.default.fileExists(atPath:path.path){return ""};return try String(contentsOf:path,encoding:.utf8) }
func removeBlock(_ text:String,_ keepEdited:[String:String]? = nil)->String {
    var inside=false;var output=[String]()
    for line in text.components(separatedBy:"\n") {
        if line==markerStart {inside=true;continue};if line==markerEnd {inside=false;continue}
        if !inside {output.append(line)}
        else if let written=keepEdited,let k=key(line),line != written[k] {output.append(line)}
    }
    return output.joined(separator:"\n")
}
func registeredProcess()->Bool {
    let result=run("/bin/launchctl",["print","gui/\(getuid())/\(label)"])
    return result.0==0 && result.1.components(separatedBy:"\n").contains {$0.trimmingCharacters(in:.whitespaces).hasPrefix("pid =")}
}
func validateBlock(_ text:String)throws {
    let lines=text.components(separatedBy:"\n")
    let begin=lines.indices.filter{lines[$0]==markerStart};let end=lines.indices.filter{lines[$0]==markerEnd}
    guard (begin.isEmpty && end.isEmpty) || (begin.count==1 && end.count==1 && begin[0]<end[0]) else {throw Failure(description:"Malformed managed .env block; no changes made")}
}
func restoreFile(_ url:URL,_ data:Data?,_ permissions:Int)throws {
    if let data=data {try data.write(to:url,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:permissions],ofItemAtPath:url.path)}
    else if FileManager.default.fileExists(atPath:url.path){try FileManager.default.removeItem(at:url)}
}
func install(_ port:Int,_ upstream:Int,_ mode:String)throws {
    guard port != upstream else {throw Failure(description:"Bridge and Clash ports must differ")}
    guard !registeredProcess() else {throw Failure(description:"Existing proxy is active. Finish Codex tasks, quit Codex and wait 30 seconds before installing. No changes made.")}
    let fm=FileManager.default;let codex=home.appendingPathComponent(".codex");let env=codex.appendingPathComponent(".env");let state=support.appendingPathComponent("env-state.json")
    let agentDir=home.appendingPathComponent("Library/LaunchAgents");let plist=agentDir.appendingPathComponent(label+".plist")
    let bin=support.appendingPathComponent("fox-codex-proxy")
    let oldEnv=try? Data(contentsOf:env);let oldState=try? Data(contentsOf:state);let oldJob=try? Data(contentsOf:plist);let oldBin=try? Data(contentsOf:bin)
    let wasRegistered=run("/bin/launchctl",["print","gui/\(getuid())/\(label)"]).0==0
    let old=try envText(env);try validateBlock(old)
    var previous=[String]();var owned=[String:String]()
    if let data=oldState {
        let saved=try JSONSerialization.jsonObject(with:data) as? [String:Any]
        previous=saved?["previous"] as? [String] ?? [];owned=saved?["written"] as? [String:String] ?? [:]
        var inside=false
        for line in old.components(separatedBy:"\n") {
            if line==markerStart {inside=true;continue};if line==markerEnd {inside=false;continue}
            if inside,let k=key(line),line != owned[k] {throw Failure(description:"Managed proxy block edited; review .codex/.env before upgrading")}
            if !inside,let k=key(line),proxyKeys.contains(k) {throw Failure(description:"Proxy key outside managed block: \(k); preserving user edit, upgrade stopped")}
        }
    } else {
        guard !old.contains(markerStart) else {throw Failure(description:"Managed block has no ownership record; inspect before installing")}
        // Positively identify the legacy job before removing its dead-port values.
        let legacyJob=oldJob.flatMap{try? PropertyListSerialization.propertyList(from:$0,options:[],format:nil) as? [String:Any]}
        let legacyArgs=legacyJob?["ProgramArguments"] as? [String] ?? []
        let legacy=legacyArgs.contains{ $0.hasSuffix("/codex-auto-proxy/scripts/auto_proxy.py") }
        previous=old.components(separatedBy:"\n").filter { line in
            guard let k=key(line),proxyKeys.contains(k) else{return false}
            let value=line.split(separator:"=",maxSplits:1,omittingEmptySubsequences:false).last.map(String.init)?.trimmingCharacters(in:CharacterSet(charactersIn:"\"' ")) ?? ""
            return !(legacy && !["NO_PROXY","no_proxy"].contains(k) && value=="http://127.0.0.1:7898")
        }
    }
    var lines=removeBlock(old).components(separatedBy:"\n").filter {!(key($0).map{proxyKeys.contains($0)} ?? false)}
    while lines.last=="" {lines.removeLast()}
    let proxy="http://127.0.0.1:\(port)";var written=[String:String]()
    for k in proxyKeys where k != "NO_PROXY" && k != "no_proxy" {written[k]="\(k)=\(proxy)"}
    var bypass=previous.filter{key($0)=="NO_PROXY" || key($0)=="no_proxy"}.last.map{String($0.split(separator:"=",maxSplits:1,omittingEmptySubsequences:false).last ?? "") } ?? ""
    bypass=bypass.trimmingCharacters(in:CharacterSet(charactersIn:"\"' "))
    var hosts=bypass.split(separator:",").map(String.init)
    for h in ["localhost","127.0.0.1","::1"] where !hosts.contains(h){hosts.append(h)}
    for k in ["NO_PROXY","no_proxy"] {written[k]="\(k)=\(hosts.joined(separator:","))"}
    let output=(lines+[markerStart]+written.keys.sorted().map{written[$0]!}+[markerEnd,""]).joined(separator:"\n")
    try fm.createDirectory(at:support,withIntermediateDirectories:true);try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:support.path)
    try fm.createDirectory(at:codex,withIntermediateDirectories:true);try fm.createDirectory(at:agentDir,withIntermediateDirectories:true)
    let logs=home.appendingPathComponent("Library/Logs");try fm.createDirectory(at:logs,withIntermediateDirectories:true)
    let original=URL(fileURLWithPath:CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath()
    let newBin=try Data(contentsOf:original)
    let job:[String:Any]=["Label":label,"ProgramArguments":[bin.path,"--serve","--launchd-socket","Listener","--port",String(port),"--clash-port",String(upstream),"--mode",mode,"--idle-timeout","30"],"Sockets":["Listener":["SockNodeName":"127.0.0.1","SockServiceName":String(port),"SockType":"stream"]],"ThrottleInterval":2,"ProcessType":"Background","StandardOutPath":logs.appendingPathComponent("FoxCodexProxy.log").path,"StandardErrorPath":logs.appendingPathComponent("FoxCodexProxy.error.log").path]
    let jobData=try PropertyListSerialization.data(fromPropertyList:job,format:.xml,options:0)
    if let oldEnv=oldEnv,!fm.fileExists(atPath:support.appendingPathComponent("env-before-install.txt").path){try restoreFile(support.appendingPathComponent("env-before-install.txt"),oldEnv,0o600)}
    if let oldJob=oldJob,!fm.fileExists(atPath:support.appendingPathComponent("previous-agent.plist").path){try restoreFile(support.appendingPathComponent("previous-agent.plist"),oldJob,0o600)}
    guard !registeredProcess() else {throw Failure(description:"Proxy became active; installation stopped before changing service")}
    do {
        _ = run("/bin/launchctl",["bootout","gui/\(getuid())/\(label)"])
        try restoreFile(bin,newBin,0o755);try restoreFile(plist,jobData,0o600)
        let activated=run("/bin/launchctl",["bootstrap","gui/\(getuid())",plist.path])
        guard activated.0==0 else {throw Failure(description:"launchd registration failed: \(activated.1)")}
        try atomicJSON(["previous":previous,"written":written,"port":port,"clash_port":upstream,"mode":mode],state)
        try output.write(to:env,atomically:true,encoding:.utf8);try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:env.path)
    } catch {
        let cause=error
        _ = run("/bin/launchctl",["bootout","gui/\(getuid())/\(label)"])
        try restoreFile(bin,oldBin,0o755);try restoreFile(plist,oldJob,0o600);try restoreFile(env,oldEnv,0o600);try restoreFile(state,oldState,0o600)
        if wasRegistered,oldJob != nil {
            let restored=run("/bin/launchctl",["bootstrap","gui/\(getuid())",plist.path])
            guard restored.0==0 else {throw Failure(description:"Installation failed and old job could not register: \(restored.1)")}
        }
        throw cause
    }
    print("Installed on-demand proxy on 127.0.0.1:\(port), Clash \(upstream), mode \(mode). No tray, login helper or new icon. Fully quit and reopen Codex using its original icon.")
}
func uninstall()throws {
    guard !registeredProcess() else {throw Failure(description:"Proxy is active; finish tasks, quit Codex and wait 30 seconds. Uninstall did not change anything.")}
    let fm=FileManager.default;let state=support.appendingPathComponent("env-state.json");let env=home.appendingPathComponent(".codex/.env")
    guard fm.fileExists(atPath:state.path) else {throw Failure(description:"No native installation ownership record; refusing to remove another proxy")}
    let saved=try JSONSerialization.jsonObject(with:Data(contentsOf:state)) as? [String:Any]
    guard let written=saved?["written"] as? [String:String],!written.isEmpty,let previous=saved?["previous"] as? [String] else {throw Failure(description:"Invalid ownership record; no changes made")}
    let plist=home.appendingPathComponent("Library/LaunchAgents/"+label+".plist")
    let oldJob=try? Data(contentsOf:plist)
    if let data=oldJob {
        let job=try PropertyListSerialization.propertyList(from:data,options:[],format:nil) as? [String:Any]
        guard (job?["ProgramArguments"] as? [String])?.first==support.appendingPathComponent("fox-codex-proxy").path else {throw Failure(description:"Launch agent ownership changed; refusing to uninstall another service")}
    }
    let oldEnv=try? Data(contentsOf:env);let wasRegistered=run("/bin/launchctl",["print","gui/\(getuid())/\(label)"]).0==0
    let current=try envText(env);try validateBlock(current)
    var restored=removeBlock(current,written)
    let present=Set(restored.components(separatedBy:"\n").compactMap{key($0)})
    let missing=previous.filter {key($0).map{!present.contains($0)} ?? false}
    if !restored.hasSuffix("\n"){restored+="\n"};restored+=missing.joined(separator:"\n")
    if !restored.hasSuffix("\n"){restored+="\n"}
    guard !registeredProcess() else {throw Failure(description:"Proxy became active; uninstall stopped")}
    do {
        try restored.write(to:env,atomically:true,encoding:.utf8)
        _ = run("/bin/launchctl",["bootout","gui/\(getuid())/\(label)"])
        if fm.fileExists(atPath:plist.path){try fm.removeItem(at:plist)}
        try fm.moveItem(at:state,to:support.appendingPathComponent("env-state-uninstalled-"+UUID().uuidString+".json"))
    } catch {
        let cause=error;try restoreFile(env,oldEnv,0o600);try restoreFile(plist,oldJob,0o600)
        if wasRegistered,oldJob != nil {
            let result=run("/bin/launchctl",["bootstrap","gui/\(getuid())",plist.path])
            if result.0 != 0 && !run("/bin/launchctl",["print","gui/\(getuid())/\(label)"]).1.contains("state =") {throw Failure(description:"Uninstall rollback could not register service: \(result.1)")}
        }
        throw cause
    }
    try? fm.removeItem(at:support.appendingPathComponent("status.json"))
    print("Removed on-demand service and managed .env values. User edits and local backups retained. Reopen Codex to apply.")
}
signal(SIGPIPE,SIG_IGN)
do {
    let saved=(try? Data(contentsOf:support.appendingPathComponent("env-state.json"))).flatMap{try? JSONSerialization.jsonObject(with:$0) as? [String:Any]}
    let port=try number("--port",args.contains("--install") ? saved?["port"] as? Int ?? 7898 : 7898,range:1...65535)
    let upstream=try number("--clash-port",args.contains("--install") ? saved?["clash_port"] as? Int ?? 7897 : 7897,range:1...65535)
    let idle=try number("--idle-timeout",30,range:0...3600)
    let mode=option("--mode",args.contains("--install") ? saved?["mode"] as? String ?? "auto" : "auto");guard ["auto","direct","clash"].contains(mode) else {throw Failure(description:"Mode must be auto, direct or clash")}
    let status=URL(fileURLWithPath:option("--status-file",support.appendingPathComponent("status.json").path))
    if args.contains("--serve"){try serve(port,upstream,idle,mode,status)}
    else if args.contains("--install"){try install(port,upstream,mode)}
    else if args.contains("--uninstall"){try uninstall()}
    else if args.contains("--check"){print(Routes(mode,status).select(fresh:true))}
    else if args.contains("--status") {
        let result=run("/bin/launchctl",["print","gui/\(getuid())/\(label)"])
        print("Registered: \(result.0==0); helper running: \(registeredProcess())")
        if let data=try? Data(contentsOf:status){print("Cached status (see checked_at):\n"+String(decoding:data,as:UTF8.self))}
        else{print("No native route status yet")}
    } else {print("FoxCodexProxy macOS 2.2.1 preview\n--install [--clash-port 7897 --port 7898 --mode auto]\n--status | --check | --uninstall\n--serve [--port 7898 --clash-port 7897 --mode auto --idle-timeout 30]\nThe service starts only on connections and exits when no connections remain. No tray or system proxy changes.")}
} catch {fputs("FoxCodexProxy: \(error)\n",stderr);exit(1)}
