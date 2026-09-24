"""Prepare stable extension ID; --install registers the native host after approval."""
import base64,hashlib,json,os,shlex,shutil,subprocess,sys
from pathlib import Path
root=Path(__file__).resolve().parent
manifest_path=root/'extension'/'manifest.json'
manifest=json.loads(manifest_path.read_text())
if 'key' not in manifest:
    private=subprocess.run(['openssl','genrsa','2048'],capture_output=True,check=True).stdout
    public=subprocess.run(['openssl','rsa','-pubout','-outform','DER'],input=private,capture_output=True,check=True).stdout
    manifest['key']=base64.b64encode(public).decode();manifest_path.write_text(json.dumps(manifest,indent=2)+'\n')
digest=hashlib.sha256(base64.b64decode(manifest['key'])).hexdigest()[:32]
identifier=''.join(chr(ord('a')+int(c,16)) for c in digest)
(root/'host-config.json').write_text(json.dumps(dict(extension_id=identifier),indent=2)+'\n')
launcher=root/'native-host'
launcher.write_text('#!/bin/sh\nexec '+shlex.quote(sys.executable)+' '+shlex.quote(str(root/'native_host.py'))+' "$@"\n');launcher.chmod(0o755)
host=dict(name='dev.localvoice.browser',description='Local Voice browser bridge',path=str(launcher),type='stdio',allowed_origins=['chrome-extension://'+identifier+'/'])
(root/'native-host-manifest.json').write_text(json.dumps(host,indent=2)+'\n')
if '--install' in sys.argv:
    # Chrome must not depend on access to a development checkout in Documents.
    runtime=Path.home()/'Library'/'Application Support'/'LocalVoice'/'BrowserHost'
    runtime.mkdir(parents=True,exist_ok=True);runtime.chmod(0o700)
    for name in ['native_host.py','host-config.json']:
        shutil.copy2(root/name,runtime/name)
    installed_launcher=runtime/'native-host'
    installed_launcher.write_text('#!/bin/sh\nexec '+shlex.quote(sys.executable)+' '+shlex.quote(str(runtime/'native_host.py'))+' "$@"\n')
    installed_launcher.chmod(0o700)
    host['path']=str(installed_launcher)
    dest=Path.home()/'Library'/'Application Support'/'Google'/'Chrome'/'NativeMessagingHosts'
    dest.mkdir(parents=True,exist_ok=True);(dest/'dev.localvoice.browser.json').write_text(json.dumps(host,indent=2)+'\n')
print(json.dumps(dict(extension_id=identifier,extension_directory=str(root/'extension'),native_host_registered='--install' in sys.argv)))
