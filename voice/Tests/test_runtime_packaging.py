import importlib.util,json,tempfile,unittest,os
from unittest.mock import patch
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('stage_runtime',ROOT/'voice/tools/stage_runtime.py')
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class RuntimePackagingTests(unittest.TestCase):
    def fixture(self,root):
        files=list(module.SOURCES.values())
        for name in files:
            p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('{}' if p.suffix=='.json' else 'fixture')
    def test_stage_uses_relative_workers_and_bundled_weights(self):
        with tempfile.TemporaryDirectory(prefix='voice package ') as d:
            root=Path(d)/'checkout';out=Path(d)/'App'/'Resources';self.fixture(root)
            module.stage(root,out,Path('/usr/bin/python3'),vision='off')
            for name in ['ParserConfig.json','GroundedConfig.json']:
                config=json.loads((out/name).read_text())
                self.assertFalse(Path(config['worker']).is_absolute())
                self.assertTrue((out/config['worker']).is_file())
                self.assertTrue((out/config['models']).is_dir())
            self.assertEqual(len(list((out/'Runtime/models').glob('*.pt'))),3)
            self.assertTrue((out/'Runtime/licenses/MODEL-NOTICES.txt').is_file())
            self.assertFalse((out/'VisionConfig.json').exists())
            self.assertNotIn(str(root), (out/'Runtime/manifest.json').read_text())
    def test_full_build_requires_vision_and_bundles_a_local_snapshot(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)/'checkout';out=Path(d)/'Resources';self.fixture(root)
            with self.assertRaises(FileNotFoundError):module.stage(root,out,Path('/usr/bin/python3'))
            model=root/'vision-model';model.mkdir()
            for name in ['model.safetensors','config.json','preprocessor_config.json','tokenizer.json','tokenizer_config.json','vocab.json','generation_config.json']:(model/name).write_text('{}')
            (root/'voice/vision').mkdir();(root/'voice/vision/worker.py').write_text('fixture')
            with patch.dict(os.environ,{'VOICE_VISION_PYTHON':'/usr/bin/python3','VOICE_VISION_MODEL':str(model)}):module.stage(root,out,Path('/usr/bin/python3'))
            config=json.loads((out/'VisionConfig.json').read_text())
            self.assertEqual(config['model'],'Runtime/models/goclick')
            self.assertTrue((out/config['model']/'model.safetensors').is_file())
    def test_preserves_virtualenv_interpreter_symlink_path(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)/'checkout';out=Path(d)/'Resources';self.fixture(root)
            python=Path(d)/'venv/bin/python';python.parent.mkdir(parents=True);python.symlink_to('/usr/bin/python3')
            module.stage(root,out,python,vision='off')
            self.assertEqual(json.loads((out/'ParserConfig.json').read_text())['python'],str(python))
    def test_installed_runtime_build_does_not_require_research_artifacts(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)/'checkout';out=Path(d)/'Resources';self.fixture(root)
            models=Path(d)/'installed models';models.mkdir()
            for name,source in module.SOURCES.items():
                if name.startswith('models/'):
                    target=models/Path(name).relative_to('models');target.parent.mkdir(parents=True,exist_ok=True)
                    (root/source).rename(target)
            runtime=dict(version=1,parserPython='/usr/bin/python3',visionPython='/unused/python',models=str(models))
            module.stage(root,out,vision='off',runtime=runtime)
            self.assertEqual(json.loads((out/'ParserConfig.json').read_text())['python'],'/usr/bin/python3')
            self.assertEqual((out/'Runtime/models/parser.pt').read_text(),'fixture')
    def test_missing_weights_fail_before_replacing_existing_runtime(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)/'checkout';out=Path(d)/'Resources';self.fixture(root)
            module.stage(root,out,Path('/usr/bin/python3'),vision='off')
            previous=(out/'Runtime/manifest.json').read_bytes()
            (root/'.cache/grounded-operation/candidate.pt').unlink()
            with self.assertRaises(FileNotFoundError):module.stage(root,out,Path('/usr/bin/python3'),vision='off')
            self.assertEqual((out/'Runtime/manifest.json').read_bytes(),previous)
    def test_optional_vision_clears_stale_config_and_copies_no_research_data(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)/'checkout';out=Path(d)/'Resources';self.fixture(root);out.mkdir()
            (out/'VisionConfig.json').write_text('{"stale":true}')
            (root/'voice/parser/artifacts/private.txt').write_text('do not bundle')
            module.stage(root,out,Path('/usr/bin/python3'),vision='auto')
            self.assertFalse((out/'VisionConfig.json').exists())
            self.assertFalse(any(p.name=='private.txt' for p in out.rglob('*')))
if __name__=='__main__':unittest.main()
