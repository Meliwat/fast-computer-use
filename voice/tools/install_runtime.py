#!/usr/bin/env python3
"""Install isolated inference dependencies and validated local model assets.

Packages download on first install. Model weights come from an explicitly supplied
Local Voice bundle or pinned asset pack; this command never retrains, captures, starts the app or changes
macOS permissions. Existing runtime configuration is replaced only after all three
offline worker checks succeed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile

from doctor import probe_worker
from stage_runtime import SOURCES
from model_assets import prepare, verify_pack

ROOT=Path(__file__).resolve().parents[2]
DEFAULT_HOME=Path.home()/'Library/Application Support/LocalVoice/Runtime'
MODEL_FILES={name for name in SOURCES if name.startswith('models/')}
VISION_FILES={'models/goclick/'+name for name in ['model.safetensors','config.json','preprocessor_config.json','tokenizer.json','tokenizer_config.json','vocab.json','generation_config.json']}
OPTIONAL_FILES={'models/goclick/'+name for name in ['README.md','LICENSE','LICENSE.txt']}

def digest(path):
    with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def verify_models(app):
    runtime=Path(app)/'Contents/Resources/Runtime'
    manifest=json.loads((runtime/'manifest.json').read_text())
    required=MODEL_FILES|VISION_FILES
    if manifest.get('visionIncluded') is not True or not required.issubset(manifest['files']):
        raise ValueError('The source bundle must contain all command models and GoClick vision')
    files={name:manifest['files'][name] for name in sorted(required|OPTIONAL_FILES.intersection(manifest['files']))}
    for name,expected in files.items():
        source=runtime/name
        if not source.resolve().is_relative_to(runtime.resolve()) or digest(source)!=expected:
            raise ValueError(f'Model file missing, outside the bundle or hash mismatch: {name}')
    return runtime,files

def environment(home,name,lock,base_python,version):
    # A stable final path matters: venv scripts contain absolute interpreter paths.
    folder=home/(name+'-py'+version.replace('.','')+'-'+digest(lock)[:12])
    python=folder/'bin/python'
    if not python.exists():subprocess.run([str(base_python),'-m','venv',str(folder)],check=True)
    uv=shutil.which('uv')
    if uv:
        command=[uv,'pip','sync','--python',str(python),str(lock)]
    else:
        command=[str(python),'-m','pip','install','--disable-pip-version-check','-r',str(lock)]
    subprocess.run(command,check=True)
    return python.absolute()

def install(app,home,vision_python=None,assets=None,commands=None,vision_cache=None):
    if sum(value is not None for value in [app,assets,commands])!=1:
        raise ValueError('Choose exactly one source: --from-app, --from-assets or --commands')
    if vision_cache is not None and commands is None:raise ValueError('--vision-cache requires --commands')
    if sys.version_info[:2]!=(3,11) or platform.system()!='Darwin' or platform.machine()!='arm64':
        raise ValueError('Run this installer with native Apple Silicon Python 3.11 on macOS 14 or newer')
    if int(platform.mac_ver()[0].split('.')[0])<14:raise ValueError('macOS 14 or newer is required')
    vision_python=vision_python or shutil.which('python3.12')
    if not vision_python:raise ValueError('Native Python 3.12 is required for vision; set --vision-python')
    details=json.loads(subprocess.check_output([str(vision_python),'-c',"import json,sys,platform;print(json.dumps([list(sys.version_info[:2]),platform.machine()]))"],text=True))
    if details!=[[3,12],'arm64']:raise ValueError('Vision Python must be native Apple Silicon Python 3.12')
    if commands is not None:
        home=Path(home).absolute();home.mkdir(parents=True,exist_ok=True);home.chmod(0o700)
        # Download only during setup. Temporary source copies are removed after
        # the verified model store and worker configuration are installed.
        with tempfile.TemporaryDirectory(prefix='.model-download-',dir=home) as temp:
            prepared=prepare(commands,Path(temp),vision_cache)
            return install(None,home,vision_python,assets=Path(prepared['assets']))
    # An asset pack is anchored to the source-controlled lock, including notices.
    # An existing local app retains the development migration path.
    source,files=verify_pack(assets) if assets is not None else verify_models(app)
    home=Path(home).absolute();home.mkdir(parents=True,exist_ok=True);home.chmod(0o700)
    parser=environment(home,'parser',ROOT/'voice/runtime/parser-requirements.lock',sys.executable,'3.11')
    vision=environment(home,'vision',ROOT/'voice/runtime/vision-requirements.lock',vision_python,'3.12')
    identity=hashlib.sha256(json.dumps(files,sort_keys=True).encode()).hexdigest()[:16]
    models=home/('models-'+identity)
    if not models.exists():
        with tempfile.TemporaryDirectory(prefix='.models-',dir=home) as temp:
            staged=Path(temp)/'models';staged.mkdir()
            for name in files:
                target=staged/Path(name).relative_to('models');target.parent.mkdir(parents=True,exist_ok=True)
                shutil.copyfile(source/name,target)
            # Copy may race a source rebuild. Hash the copy before publishing it.
            for name,expected in files.items():
                if digest(staged/Path(name).relative_to('models'))!=expected:raise ValueError('Source models changed during installation')
            staged.rename(models)
    for name,expected in files.items():
        if digest(models/Path(name).relative_to('models'))!=expected:raise ValueError('Installed model assets have changed')
    checks=[]
    for name,python,worker,weights in [
        ('Parser',parser,ROOT/'voice/parser/worker.py',models),
        ('Grounded',parser,ROOT/'voice/research/grounded/worker.py',models),
        ('Vision',vision,ROOT/'voice/vision/worker.py',models/'goclick')]:
        valid,detail=probe_worker(name,python,worker,weights,home)
        checks.append(dict(worker=name,ok=valid,**detail))
        if not valid:raise ValueError(name+' failed offline inference; previous configuration preserved')
    config=dict(version=1,parserPython=str(parser),visionPython=str(vision),models=str(models))
    # Only validated environments become the build default.
    config_path=home/'runtime.json'
    with tempfile.NamedTemporaryFile(mode='w',prefix='.runtime-',dir=home,delete=False) as stream:
        json.dump(config,stream,indent=2);stream.write('\n');temporary=Path(stream.name)
    os.replace(temporary,config_path)
    return dict(ok=True,configuration=str(config_path),checks=checks)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    source=parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--from-app',type=Path)
    source.add_argument('--from-assets',type=Path,help='Verified asset directory from model_assets.py prepare')
    source.add_argument('--commands',type=Path,help='Fresh setup: command-model archive; downloads pinned GoClick assets')
    parser.add_argument('--directory',type=Path,default=DEFAULT_HOME)
    parser.add_argument('--vision-python',type=Path,help='Native Python 3.12; defaults to python3.12 on PATH')
    parser.add_argument('--vision-cache',type=Path,help='Optional GoClick cache for --commands; every file is still verified')
    args=parser.parse_args()
    print(json.dumps(install(args.from_app,args.directory,args.vision_python,args.from_assets,args.commands,args.vision_cache),indent=2))
