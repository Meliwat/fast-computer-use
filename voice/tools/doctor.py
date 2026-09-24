#!/usr/bin/env python3
"""Offline bundle check. --smoke loads models using blank/test input; never captures a screen or sends input."""
import argparse,base64,binascii,hashlib,json,os,shlex,subprocess,sys,time
from pathlib import Path

def check_browser_installation(browser_root=None,home=None):
    """Read the setup.py installation only; never start Chrome or its native host."""
    browser_root=Path(browser_root) if browser_root else Path(__file__).resolve().parents[1]/'browser'
    home=Path(home) if home else Path.home()
    runtime=home/'Library/Application Support/LocalVoice/BrowserHost'
    registration=home/'Library/Application Support/Google/Chrome/NativeMessagingHosts/dev.localvoice.browser.json'
    checks=[]
    repair='Run python3.11 voice/browser/setup.py --install from this checkout, then reload the Local Voice Chrome extension.'
    def record(name,ok,detail):checks.append(dict(name=name,ok=ok,detail=detail))
    def read_json(path):
        data=json.loads(path.read_text())
        if not isinstance(data,dict):raise ValueError('Expected a JSON object')
        return data
    try:
        manifest=read_json(browser_root/'extension/manifest.json')
        key=base64.b64decode(manifest['key'],validate=True)
        if not key:raise ValueError('Empty extension key')
        hex_id=hashlib.sha256(key).hexdigest()[:32]
        identifier=''.join(chr(ord('a')+int(c,16)) for c in hex_id)
        record('Chrome extension source',True,dict(extensionID=identifier,version=manifest['version']))
    except (OSError,ValueError,KeyError,TypeError,binascii.Error):
        record('Chrome extension source',False,'Missing or invalid extension manifest/key. Restore the extension files from this source release.')
        return checks
    try:
        host=read_json(registration)
        expected_launcher=runtime/'native-host'
        if host.get('name')!='dev.localvoice.browser' or host.get('type')!='stdio':
            raise ValueError('Chrome host registration has the wrong name or transport.')
        if host.get('allowed_origins')!=['chrome-extension://'+identifier+'/']:
            raise ValueError('Chrome host registration does not match this extension ID.')
        if host.get('path')!=str(expected_launcher):
            raise ValueError('Registered launcher differs from the supported setup.py installation.')
        record('Chrome host registration',True,'Registration matches this extension and installed launcher.')
    except (OSError,ValueError) as error:
        record('Chrome host registration',False,('Native host registration is missing. ' if isinstance(error,FileNotFoundError) else str(error)+' ')+repair)
        return checks
    try:
        config=read_json(runtime/'host-config.json')
        if config.get('extension_id')!=identifier:raise ValueError('Installed host configuration has a different extension ID.')
        record('Chrome host configuration',True,'Installed extension ID matches.')
    except (OSError,ValueError) as error:record('Chrome host configuration',False,str(error)+' '+repair)
    try:
        installed=runtime/'native_host.py'
        expected=browser_root/'native_host.py'
        if installed.read_bytes()!=expected.read_bytes():raise ValueError('Installed native host is older than or differs from this checkout.')
        record('Chrome host source',True,'Installed host matches this checkout byte for byte.')
    except (OSError,ValueError) as error:record('Chrome host source',False,str(error)+' '+repair)
    try:
        if not expected_launcher.is_file() or not os.access(expected_launcher,os.X_OK):
            raise ValueError('Installed native host launcher is missing or not executable.')
        lines=expected_launcher.read_text().splitlines()
        command=shlex.split(lines[1]) if len(lines)==2 and lines[0]=='#!/bin/sh' else []
        if len(command)!=4 or command[0]!='exec' or command[-1]!='$@' or command[2]!=str(runtime/'native_host.py'):
            raise ValueError('Installed launcher does not match the setup.py command format.')
        python=Path(command[1])
        if not python.is_absolute() or not python.is_file() or not os.access(python,os.X_OK):
            raise ValueError('The Python interpreter recorded during browser setup is missing or not executable.')
        record('Chrome host launcher',True,'Launcher and its configured interpreter are present and executable; neither was run.')
    except (OSError,ValueError) as error:record('Chrome host launcher',False,str(error)+' '+repair)
    return checks

def probe_worker(name,python,worker,models,cwd):
    env={**os.environ,'HF_HUB_OFFLINE':'1','TRANSFORMERS_OFFLINE':'1','HF_HUB_DISABLE_TELEMETRY':'1','PYTHONDONTWRITEBYTECODE':'1','LOCALVOICE_MODEL_DIR':str(models)}
    args=[str(python),str(worker)]
    request={'text':'open Notes'}
    if name=='Grounded':
        args+=['--grounded-v2'];request={'id':'doctor','text':'Focus Reference number','observation':{'version':1,'documentId':'doctor','observationId':'doctor','truncated':False,'candidates':[{'id':'field','role':'input','labels':['reference number'],'enabled':True,'editable':True,'clickable':True}]}}
    if name=='Vision':args+=[str(models)];request={'id':'doctor','op':'warm'}
    started=time.perf_counter()
    child=subprocess.run(args,input=json.dumps(request)+'\n',capture_output=True,text=True,timeout=45,env=env,cwd=cwd)
    lines=child.stdout.splitlines()
    if child.returncode or len(lines)!=1:raise ValueError(f'Worker failed (exit {child.returncode}); no valid JSON reply')
    reply=json.loads(lines[0])
    valid=reply.get('action')=='openApp' if name=='Parser' else reply.get('id')=='doctor' and (reply.get('ok') is True if name=='Vision' else reply.get('command',{}).get('targetId')=='field')
    return valid,{'coldRoundTripMs':round((time.perf_counter()-started)*1000),'error':reply.get('error')}

def resolve(resources,value):
    p=Path(value)
    if p.is_absolute():return p
    p=(resources/p).resolve()
    if not p.is_relative_to(resources.resolve()):raise ValueError('Runtime path leaves bundle')
    return p

def check(app,smoke=False,verify_hashes=False,browser_files=False):
    resources=Path(app)/'Contents/Resources';checks=[]
    def record(name,ok,detail):checks.append(dict(name=name,ok=ok,detail=detail))
    try:
        runtime=resources/'Runtime';manifest=json.loads((runtime/'manifest.json').read_text())
        invalid=[]
        for relative,digest in manifest['files'].items():
            p=resolve(runtime,relative)
            if not p.is_file():invalid.append(relative)
            elif verify_hashes:
                with p.open('rb') as f:
                    if hashlib.file_digest(f,'sha256').hexdigest()!=digest:invalid.append(relative)
        record('bundle files',not invalid,invalid or f"{len(manifest['files'])} runtime files present"+(' and hashes checked' if verify_hashes else ''))
    except (OSError,ValueError,KeyError) as e:record('bundle files',False,str(e))
    for name in ['Parser','Grounded','Vision']:
        try:
            config=json.loads((resources/(name+'Config.json')).read_text())
            python=resolve(resources,config['python']);worker=resolve(resources,config['worker'])
            if not os.access(python,os.X_OK) or not worker.is_file():raise ValueError('Interpreter or worker missing')
            model_key='model' if name=='Vision' else 'models'
            models=resolve(resources,config[model_key])
            if not models.is_dir():raise ValueError('Model directory missing')
            record(name+' paths',True,'Configured local runtime and bundled models found')
            if not smoke:continue
            valid,detail=probe_worker(name,python,worker,models,resources)
            record(name+' offline inference',valid,detail)
        except (OSError,ValueError,KeyError,AttributeError,subprocess.TimeoutExpired) as e:record(name+' runtime',False,str(e))
    if browser_files:checks.extend(check_browser_installation())
    return dict(ok=all(row['ok'] for row in checks),scope='Local resources, optional synthetic inference and optional browser installation files only. No microphone, screen capture, input dispatch, Chrome connection, enabled-extension or permissions checks.',checks=checks)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--app',type=Path,default=Path(__file__).resolve().parents[1]/'dist/Local Voice.app');p.add_argument('--smoke',action='store_true');p.add_argument('--verify-hashes',action='store_true');p.add_argument('--browser-files',action='store_true',help='Also inspect Chrome host registration and installed files without starting Chrome or the host');a=p.parse_args()
    result=check(a.app.resolve(),a.smoke,a.verify_hashes,a.browser_files);print(json.dumps(result,indent=2));sys.exit(0 if result['ok'] else 1)
