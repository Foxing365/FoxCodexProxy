#!/usr/bin/env python3
"""Regression: half-close while the peer waits 35 seconds must not spin/exit."""
import pathlib,socket,subprocess,threading,time,tempfile
binary=pathlib.Path(__file__).resolve().parents[2]/'bin/macos/fox-codex-proxy'
def header(c):
 b=b''
 while not b.endswith(b'\r\n\r\n'):b+=c.recv(1)
 return b
s=socket.socket();s.bind(('127.0.0.1',0));s.listen()
def remote():
 c,_=s.accept()
 with c:
  assert c.recv(10)==b'hello'
  assert c.recv(10)==b''
  time.sleep(35);c.sendall(b'AFTER_HALF_CLOSE');c.shutdown(socket.SHUT_WR)
threading.Thread(target=remote,daemon=True).start()
probe=socket.socket();probe.bind(('127.0.0.1',0));port=probe.getsockname()[1];probe.close()
def cpu(pid):
 raw=subprocess.check_output(['ps','-p',str(pid),'-o','time='],text=True).strip()
 fields=raw.split(':');return sum(float(v)*60**i for i,v in enumerate(reversed(fields)))
with tempfile.TemporaryDirectory(prefix='FoxCodexProxy-halfclose-') as root:
 with open(root+'/helper.log','w') as log:
  p=subprocess.Popen([str(binary),'--serve','--port',str(port),'--mode','direct','--idle-timeout','2','--status-file',root+'/status.json'],stderr=log)
  try:
   for _ in range(100):
    try:c=socket.create_connection(('127.0.0.1',port),.1);break
    except OSError:time.sleep(.05)
   c.settimeout(50)
   with c:
    c.sendall(('CONNECT 127.0.0.1:%s HTTP/1.1\r\n\r\n'%s.getsockname()[1]).encode());assert b' 200 ' in header(c)
    c.sendall(b'hello');c.shutdown(socket.SHUT_WR)
    before=cpu(p.pid);time.sleep(5);spent=cpu(p.pid)-before
    assert spent<1.0,('busy-loop CPU seconds',spent)
    assert c.recv(100)==b'AFTER_HALF_CLOSE'
    assert c.recv(100)==b''
   p.wait(timeout=5);assert p.returncode==0
   print('PASS: 35s delayed half-close response; <1 CPU second over 5 quiet seconds; clean idle exit')
  finally:
   if p.poll() is None:p.terminate();p.wait()
s.close()
