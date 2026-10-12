#!/usr/bin/env python3
"""Local TCP tests only; never reads Codex auth or changes production proxy."""
import hashlib, os, pathlib, socket, subprocess, threading, time, tempfile, plistlib
ROOT=pathlib.Path(__file__).resolve().parents[2]
BINARY=ROOT/'bin/macos/fox-codex-proxy'
PAYLOAD=bytes(range(256))*262144 # 64 MiB: exceeds observed large requests
DIGEST=hashlib.sha256(PAYLOAD).digest()

def listener():
 s=socket.socket();s.bind(('127.0.0.1',0));s.listen();return s

def read_header(s):
 b=b''
 while not b.endswith(b'\r\n\r\n'):
  v=s.recv(1)
  assert v,'unexpected header EOF'
  b+=v
 return b

def destination():
 s=listener()
 def handle(c):
  with c:
   h=hashlib.sha256()
   while True:
    data=c.recv(65536)
    if not data:break
    h.update(data)
   if h.digest()==DIGEST:
    time.sleep(.2);c.sendall(DIGEST);c.sendall(PAYLOAD)
   else:c.sendall(b'ACK')
   c.shutdown(socket.SHUT_WR)
 def loop():
  while True:
   try:c,_=s.accept()
   except OSError:return
   threading.Thread(target=handle,args=(c,),daemon=True).start()
 threading.Thread(target=loop,daemon=True).start();return s

def fake_clash():
 s=listener()
 def pipe(a,b):
  try:
   while True:
    data=a.recv(65536)
    if not data: b.shutdown(socket.SHUT_WR);return
    b.sendall(data)
  except OSError:pass
 def handle(c):
  with c:
   target=read_header(c).split(b' ')[1].decode();host,port=target.rsplit(':',1)
   with socket.create_connection((host,int(port))) as r:
    c.sendall(b'HTTP/1.1 200 Connection Established\r\n\r\n')
    t=threading.Thread(target=pipe,args=(c,r));t.start();pipe(r,c);t.join()
 def loop():
  while True:
   try:c,_=s.accept()
   except OSError:return
   threading.Thread(target=handle,args=(c,),daemon=True).start()
 threading.Thread(target=loop,daemon=True).start();return s

def connect(port,target):
 c=socket.create_connection(('127.0.0.1',port));c.settimeout(60)
 c.sendall(('CONNECT 127.0.0.1:%s HTTP/1.1\r\nHost: local-test\r\n\r\n'%target).encode())
 assert b' 200 ' in read_header(c);return c

def wait_ready(port):
 for _ in range(100):
  try:
   c=socket.create_connection(('127.0.0.1',port),.1);c.close();return
  except OSError:time.sleep(.05)
 raise AssertionError('listener missing')

def roundtrip(port,target):
 with connect(port,target) as c:
  c.sendall(PAYLOAD);c.shutdown(socket.SHUT_WR)
  digest=b''
  while len(digest)<32:digest+=c.recv(32-len(digest))
  assert digest==DIGEST
  h=hashlib.sha256();size=0
  while True:
   data=c.recv(65536)
   if not data:break
   h.update(data);size+=len(data)
  assert size==len(PAYLOAD) and h.digest()==DIGEST

def regular(mode,upstream,target,tmp):
 spare=listener();port=spare.getsockname()[1];spare.close()
 with open(tmp/(mode+'.log'),'w') as log:
  p=subprocess.Popen([str(BINARY),'--serve','--port',str(port),'--clash-port',str(upstream),'--mode',mode,'--idle-timeout','2','--status-file',str(tmp/(mode+'.json'))],stderr=log)
  try:
   wait_ready(port);roundtrip(port,target)
   with connect(port,target) as c:
    time.sleep(3);assert p.poll() is None,'active quiet connection incorrectly exited'
    c.sendall(b'hello');c.shutdown(socket.SHUT_WR);assert c.recv(100)==b'ACK'
   p.wait(timeout=5);assert p.returncode==0
   print('PASS',mode,'64 MiB each direction, hash, half-close, active silence, idle exit',flush=True)
  finally:
   if p.poll() is None:p.terminate();p.wait()

def activation(target,tmp):
 spare=listener();port=spare.getsockname()[1];spare.close()
 name='org.foxcodexproxy.test.'+str(os.getpid());domain='gui/'+str(os.getuid())
 plist=tmp/'socket.plist'
 job={'Label':name,'ProgramArguments':[str(BINARY),'--serve','--launchd-socket','Listener','--port',str(port),'--mode','direct','--idle-timeout','2','--status-file',str(tmp/'activation.json')], 'Sockets':{'Listener':{'SockNodeName':'127.0.0.1','SockServiceName':str(port),'SockType':'stream'}},'StandardErrorPath':str(tmp/'activation.log')}
 plist.write_bytes(plistlib.dumps(job))
 def running():
  x=subprocess.run(['launchctl','print',domain+'/'+name],capture_output=True,text=True)
  return any(line.strip().startswith('pid =') for line in x.stdout.splitlines())
 subprocess.run(['launchctl','bootstrap',domain,str(plist)],check=True)
 try:
  assert not running(),'helper should not start at registration'
  with connect(port,target) as c:
   assert running();print('Testing 35 seconds of quiet active tunnel...',flush=True)
   time.sleep(35);assert running(),'long quiet active tunnel exited'
   c.sendall(b'hello');c.shutdown(socket.SHUT_WR);assert c.recv(100)==b'ACK'
  for _ in range(30):
   if not running():break
   time.sleep(.2)
  assert not running(),'helper did not exit after all tunnels closed'
  with connect(port,target) as c:
   assert running();c.shutdown(socket.SHUT_WR);assert c.recv(100)==b'ACK'
  print('PASS real launchd activation, 35s active silence, idle exit, reactivation',flush=True)
 finally:subprocess.run(['launchctl','bootout',domain+'/'+name],check=True)

with tempfile.TemporaryDirectory(prefix='FoxCodexProxy-test-') as d:
 tmp=pathlib.Path(d);server=destination();clash=fake_clash()
 try:
  target=server.getsockname()[1];upstream=clash.getsockname()[1]
  regular('direct',upstream,target,tmp);regular('clash',upstream,target,tmp);activation(target,tmp)
 finally:server.close();clash.close()
print('All native macOS network regression tests passed.',flush=True)
