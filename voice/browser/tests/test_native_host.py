"""Transport-only verification: simulated Chrome, no browser actions."""
import json,os,socket,struct,subprocess,sys,tempfile,time,threading,statistics
from pathlib import Path
root=Path(__file__).resolve().parents[1]
origin='chrome-extension://'+json.loads((root/'host-config.json').read_text())['extension_id']+'/'
with tempfile.TemporaryDirectory(dir="/tmp",prefix="lv-") as home:
    p=subprocess.Popen([sys.executable,str(root/'native_host.py'),origin],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env={**os.environ,'HOME':home})
    path=Path(home)/'Library/Application Support/LocalVoice/browser.sock'
    def exact(n):
        data=b''
        while len(data)<n:
            chunk=p.stdout.read(n-len(data))
            if not chunk: raise EOFError()
            data+=chunk
        return data
    def chrome():
        try:
            while True:
                request=json.loads(exact(struct.unpack('<I',exact(4))[0]))
                result=json.dumps({'id':request['id'],'result':{'ok':True,'message':'simulated acknowledgement'}}).encode()
                p.stdin.write(struct.pack('<I',len(result))+result);p.stdin.flush()
        except (EOFError,ValueError,BrokenPipeError): pass
    threading.Thread(target=chrome,daemon=True).start()
    try:
        for _ in range(200):
            if path.exists():break
            time.sleep(.01)
        assert path.exists(),p.stderr.read().decode() if p.poll() is not None else 'No socket'
        assert path.stat().st_mode & 0o777 == 0o600
        times=[]
        for i in range(220):
            start=time.perf_counter()
            with socket.socket(socket.AF_UNIX) as client:
                client.settimeout(3);client.connect(str(path));client.sendall(b'{"op":"test"}\n')
                result=json.loads(client.makefile('rb').readline())
            assert result['ok']
            if i>=20:times.append((time.perf_counter()-start)*1000)
        print(json.dumps({'roundtrips':len(times),'median_ms':statistics.median(times),'p95_ms':sorted(times)[190],'scope':'Unix socket + Python relay + simulated Chrome acknowledgement; excludes actual browser and speech'}))
    finally:
        p.stdin.close();p.wait(timeout=3)
    assert not path.exists()
    denied=subprocess.run([sys.executable,str(root/'native_host.py'),'chrome-extension://wrong/'],capture_output=True,env={**os.environ,'HOME':home})
    assert denied.returncode != 0
    print('Origin rejection, socket permissions, framing and cleanup passed')
