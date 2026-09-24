#!/usr/bin/env python3
"""Stage inference code, command weights and required vision. Never downloads or starts models."""
import argparse,hashlib,json,os,shutil,sys,tempfile
from pathlib import Path

SOURCES={
    'parser/worker.py':'voice/parser/worker.py','parser/model.py':'voice/parser/model.py',
    **{'grounded/'+name:'voice/research/grounded/'+name for name in ['worker.py','pipeline.py','ranker.py','operation.py']},
    'models/base/config.json':'voice/parser/artifacts/base/config.json',
    'models/base/vocab.txt':'voice/parser/artifacts/base/vocab.txt',
    'models/parser.pt':'voice/parser/artifacts/parser.pt',
    'models/operation.pt':'.cache/grounded-operation/candidate.pt',
    'models/ranker.pt':'.cache/grounded-ranker/candidate.pt',
    'models/source.json':'voice/parser/artifacts/source.json',
    **{'licenses/'+name:'voice/licenses/'+name for name in ['BERT-Apache-2.0.txt','GoClick-MIT.txt','MODEL-NOTICES.txt','sources.json']},
}

def stage(root,resources,python=None,vision='required',runtime=None):
    root,resources=Path(root).resolve(),Path(resources)
    if runtime and runtime.get('version')!=1:raise ValueError('Unsupported installed runtime configuration')
    python=Path(python or (runtime['parserPython'] if runtime else sys.executable)).absolute()
    if not python.is_file() or not os.access(python,os.X_OK):raise FileNotFoundError('Choose an executable Python with --python')
    sources={dest:Path(runtime['models'])/Path(dest).relative_to('models') if runtime and dest.startswith('models/') else root/relative for dest,relative in SOURCES.items()}
    for name,path in sources.items():
        if not path.is_file():raise FileNotFoundError(f'Missing runtime input: {name}. Install the model assets before building.')
    vision_config=None
    vision_files={}
    if vision!='off':
        registry=root/'.cache/vision-model-paths.json'
        model=os.environ.get('VOICE_VISION_MODEL') or (str(Path(runtime['models'])/'goclick') if runtime else None)
        if not model and registry.is_file():model=json.loads(registry.read_text()).get('goclick',{}).get('path')
        vp=Path(os.environ.get('VOICE_VISION_PYTHON',runtime['visionPython'] if runtime else str(root/'.cache/vision-bench-venv/bin/python')))
        if model and Path(model).is_dir() and vp.is_file():
            if not (root/'voice/vision/worker.py').is_file():raise FileNotFoundError('Missing vision worker')
            model_root=Path(model).resolve()
            for name in ['model.safetensors','config.json','preprocessor_config.json','tokenizer.json','tokenizer_config.json','vocab.json','generation_config.json']:
                if not (model_root/name).is_file():raise FileNotFoundError(f'Missing GoClick model file: {name}')
                vision_files['models/goclick/'+name]=model_root/name
            for name in ['README.md','LICENSE','LICENSE.txt']:
                if (model_root/name).is_file():vision_files['models/goclick/'+name]=model_root/name
            vision_config=dict(python=str(vp.absolute()),worker='Runtime/vision/worker.py',model='Runtime/models/goclick')
        elif vision=='required' or os.environ.get('VOICE_VISION_MODEL') or os.environ.get('VOICE_VISION_PYTHON'):
            raise FileNotFoundError('Requested GoClick runtime/weights unavailable; see voice/vision/README.md')
    resources.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.runtime-stage-',dir=resources) as temp:
        staged=Path(temp)/'Runtime';staged.mkdir()
        manifest={'version':1,'files':{},'visionIncluded':vision_config is not None,'externalPython':True}
        for dest,source in sources.items():
            target=staged/dest;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
            manifest['files'][dest]=hashlib.sha256(target.read_bytes()).hexdigest()
        for dest,source in vision_files.items():
            target=staged/dest;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
            with target.open('rb') as f:manifest['files'][dest]=hashlib.file_digest(f,'sha256').hexdigest()
        if vision_config:
            target=staged/'vision/worker.py';target.parent.mkdir();shutil.copyfile(root/'voice/vision/worker.py',target)
            manifest['files']['vision/worker.py']=hashlib.sha256(target.read_bytes()).hexdigest()
        (staged/'manifest.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
        old=resources/'Runtime';backup=Path(temp)/'previous'
        if old.exists():old.rename(backup)
        try:staged.rename(old)
        except BaseException:
            if backup.exists():backup.rename(old)
            raise
    for name,worker in [('Parser','parser'),('Grounded','grounded')]:
        (resources/(name+'Config.json')).write_text(json.dumps(dict(python=str(python),worker=f'Runtime/{worker}/worker.py',models='Runtime/models'),indent=2)+'\n')
    config=resources/'VisionConfig.json'
    if vision_config:config.write_text(json.dumps(vision_config,indent=2)+'\n')
    else:config.unlink(missing_ok=True)
    # Earlier bundles kept a duplicate worker at the resource root.
    (resources/'GoClickWorker.py').unlink(missing_ok=True)
    return manifest

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project-root',type=Path,default=Path(__file__).resolve().parents[2])
    parser.add_argument('--resources',type=Path,required=True)
    parser.add_argument('--python',type=Path)
    parser.add_argument('--runtime-config',type=Path,help='Validated runtime.json (defaults to the installed Application Support runtime, if present)')
    parser.add_argument('--vision',choices=['auto','off','required'],default='required')
    args=parser.parse_args()
    explicit_config=args.runtime_config or os.environ.get('VOICE_RUNTIME_CONFIG')
    config=Path(explicit_config) if explicit_config else Path.home()/'Library/Application Support/LocalVoice/Runtime/runtime.json'
    runtime=json.loads(config.read_text()) if config.is_file() else None
    if explicit_config and runtime is None:raise FileNotFoundError('Specified runtime configuration is missing')
    result=stage(args.project_root,args.resources,args.python,args.vision,runtime)
    print(json.dumps(dict(files=len(result['files']),visionIncluded=result['visionIncluded'])))
