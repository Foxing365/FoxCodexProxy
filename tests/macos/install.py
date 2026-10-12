#!/usr/bin/env python3
"""Real install/upgrade/uninstall on isolated home and launchd namespace."""
import pathlib,subprocess,tempfile,os,plistlib,json,socket,time,threading
binary=pathlib.Path(__file__).resolve().parents[2]/'bin/macos/fox-codex-proxy'
def free_port():
 with socket.socket() as s:s.bind(('127.0.0.1',0));return s.getsockname()[1]
with tempfile.TemporaryDirectory(prefix='FoxCodexProxy-install-') as d:
 root=pathlib.Path(d);env=root/'.codex/.env';env.parent.mkdir();env.write_text('USER_SETTING=keep\nHTTP_PROXY=http://previous.invalid:8888\nNO_PROXY=example.local\n')
 label='org.foxcodexproxy.test.'+root.name;domain='gui/'+str(os.getuid());port=free_port()
 def run(*args,ok=True):
  r=subprocess.run([str(binary),'--test-home',str(root),*args],capture_output=True,text=True)
  if ok:assert r.returncode==0,r.stderr
  else:assert r.returncode!=0,'expected safe refusal'
  return r
 try:
  run('--install','--port',str(port),'--clash-port','7897')
  text=env.read_text();assert 'USER_SETTING=keep' in text and 'example.local,localhost' in text and '# BEGIN fox-codex-proxy-macos' in text
  job=plistlib.loads((root/'Library/LaunchAgents'/ (label+'.plist')).read_bytes())
  assert 'RunAtLoad' not in job and 'KeepAlive' not in job
  run('--install');assert json.loads((root/'Library/Application Support/FoxCodexProxy/env-state.json').read_text())['port']==port
  # User override survives uninstall, and original non-managed keys are preserved.
  env.write_text(env.read_text().replace('HTTP_PROXY=http://127.0.0.1:'+str(port),'HTTP_PROXY=http://user-change.invalid:9999',1))
  run('--uninstall');assert 'HTTP_PROXY=http://user-change.invalid:9999' in env.read_text() and 'USER_SETTING=keep' in env.read_text()
  assert not (root/'Library/Application Support/FoxCodexProxy/env-state.json').exists()
  env.write_text('USER_SETTING=keep\nHTTP_PROXY=http://new-original.invalid:7777\n')
  run('--install','--port',str(port),'--mode','direct')
  remote=socket.socket();remote.bind(('127.0.0.1',0));remote.listen()
  def echo():
   c,_=remote.accept()
   with c:
    assert c.recv(10)==b'hi';assert c.recv(10)==b'';c.sendall(b'INSTALLED_OK');c.shutdown(socket.SHUT_WR)
  threading.Thread(target=echo,daemon=True).start()
  with socket.create_connection(('127.0.0.1',port)) as c:
   c.settimeout(10);c.sendall(('CONNECT 127.0.0.1:%s HTTP/1.1\r\n\r\n'%remote.getsockname()[1]).encode())
   h=b''
   while not h.endswith(b'\r\n\r\n'):
    v=c.recv(1);assert v,'installed helper failed to activate';h+=v
   assert b' 200 ' in h
   c.sendall(b'hi');c.shutdown(socket.SHUT_WR);assert c.recv(100)==b'INSTALLED_OK'
  remote.close()
  unchanged=env.read_bytes();run('--install',ok=False);run('--uninstall',ok=False);assert env.read_bytes()==unchanged
  print('PASS installed helper activation and active-upgrade/uninstall refusal; waiting for normal idle exit...',flush=True)
  for _ in range(40):
   x=subprocess.run(['launchctl','print',domain+'/'+label],capture_output=True,text=True)
   if not any(line.strip().startswith('pid =') for line in x.stdout.splitlines()):break
   time.sleep(1)
  before=env.read_bytes();env.write_text(env.read_text()+'HTTPS_PROXY=http://outside.invalid:9999\n')
  edited=env.read_bytes();run('--install',ok=False);assert env.read_bytes()==edited
  env.write_bytes(before)
  run('--uninstall');assert 'HTTP_PROXY=http://new-original.invalid:7777' in env.read_text()
  # Malformed ownership block must leave the file unchanged.
  env.write_text('USER_SETTING=keep\n# BEGIN fox-codex-proxy-macos\nHTTP_PROXY=x\n')
  before=env.read_bytes();run('--install','--port',str(port),ok=False);assert env.read_bytes()==before
  print('PASS install, upgrade preserving ports, ownership-aware uninstall, reinstall, user edits, malformed block refusal')
 finally:subprocess.run(['launchctl','bootout',domain+'/'+label],capture_output=True)
