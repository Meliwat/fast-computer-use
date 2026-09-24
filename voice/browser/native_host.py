"""Chrome native messaging <-> private local Unix socket. No HTTP or logging."""
import json,os,socket,struct,sys,threading,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parent
CONFIG=json.loads((ROOT/'host-config.json').read_text())
if len(sys.argv)<2 or sys.argv[1] != 'chrome-extension://'+CONFIG['extension_id']+'/':
    raise SystemExit('Unexpected extension origin')
base=Path.home()/'Library'/'Application Support'/'LocalVoice'
base.mkdir(parents=True,exist_ok=True);os.chmod(base,0o700)
path=str(base/'browser.sock')
# Never replace a live host belonging to another Chrome profile.
if os.path.exists(path):
    probe=socket.socket(socket.AF_UNIX);probe.settimeout(.2)
    try: probe.connect(path)
    except (ConnectionRefusedError,FileNotFoundError): os.unlink(path)
    else: raise SystemExit('Another Local Voice browser connection is active')
    finally: probe.close()
server=socket.socket(socket.AF_UNIX);server.bind(path);os.chmod(path,0o600);server.listen(4)
pending={};lock=threading.Lock();write_lock=threading.Lock()
def exact(stream,count):
    chunks=[]
    while count:
        data=stream.read(count)
        if not data: raise EOFError
        chunks.append(data);count-=len(data)
    return b''.join(chunks)
def native_read():
    try:
        while True:
            length=struct.unpack('<I',exact(sys.stdin.buffer,4))[0]
            if length>65536: raise ValueError('Oversized native response')
            response=json.loads(exact(sys.stdin.buffer,length))
            with lock: entry=pending.get(response.get('id'))
            if entry: entry[1].append(response.get('result'));entry[0].set()
    finally:
        try: os.unlink(path)
        except FileNotFoundError: pass
        os._exit(0)
threading.Thread(target=native_read,daemon=True).start()
def client(connection):
    ident=str(uuid.uuid4());event=threading.Event();result=[]
    try:
        connection.settimeout(3)
        file=connection.makefile('rb');line=file.readline(65537)
        if len(line)>65536 or not line.endswith(b'\n'): raise ValueError('Invalid request')
        request=json.loads(line)
        with lock: pending[ident]=(event,result)
        frame=json.dumps(dict(id=ident,request=request),separators=(',',':')).encode()
        with write_lock:
            sys.stdout.buffer.write(struct.pack('<I',len(frame))+frame);sys.stdout.buffer.flush()
        if not event.wait(2.5): raise TimeoutError('Browser did not acknowledge; not retrying')
        connection.sendall(json.dumps(result[0]).encode()+b'\n')
    except Exception as error:
        try: connection.sendall(json.dumps(dict(ok=False,error=str(error))).encode()+b'\n')
        except OSError: pass
    finally:
        with lock: pending.pop(ident,None)
        connection.close()
while True:
    connection,_=server.accept()
    threading.Thread(target=client,args=(connection,),daemon=True).start()
