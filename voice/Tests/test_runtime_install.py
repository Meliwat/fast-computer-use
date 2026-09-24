import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import install_runtime
from doctor import probe_worker

class RuntimeInstallTests(unittest.TestCase):
    def bundle(self,root):
        app=root/'Local Voice.app';runtime=app/'Contents/Resources/Runtime'
        files={}
        for name in install_runtime.MODEL_FILES|install_runtime.VISION_FILES:
            target=runtime/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(b'fixture')
            files[name]=hashlib.sha256(b'fixture').hexdigest()
        (runtime/'manifest.json').write_text(json.dumps(dict(version=1,visionIncluded=True,files=files)))
        return app,runtime
    def test_accepts_only_declared_model_assets(self):
        with tempfile.TemporaryDirectory() as temp:
            app,runtime=self.bundle(Path(temp))
            manifest=json.loads((runtime/'manifest.json').read_text())
            manifest['files']['models/private.txt']='not-a-hash'
            (runtime/'manifest.json').write_text(json.dumps(manifest))
            source,files=install_runtime.verify_models(app)
            self.assertEqual(source,runtime)
            self.assertNotIn('models/private.txt',files)
    def test_changed_or_external_weight_cannot_install(self):
        with tempfile.TemporaryDirectory() as temp:
            app,runtime=self.bundle(Path(temp));weight=runtime/'models/parser.pt'
            weight.write_bytes(b'changed')
            with self.assertRaises(ValueError):install_runtime.verify_models(app)
            external=Path(temp)/'external';external.write_bytes(b'fixture');weight.unlink();weight.symlink_to(external)
            with self.assertRaises(ValueError):install_runtime.verify_models(app)
    def test_vision_is_required_even_when_command_weights_exist(self):
        with tempfile.TemporaryDirectory() as temp:
            app,runtime=self.bundle(Path(temp))
            manifest=json.loads((runtime/'manifest.json').read_text());manifest['visionIncluded']=False
            (runtime/'manifest.json').write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):install_runtime.verify_models(app)
    def test_worker_probe_requires_request_identity_and_runs_offline(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);script=root/'probe.py'
            script.write_text("import os,sys,json\nr=json.loads(sys.stdin.readline())\nassert os.environ['HF_HUB_OFFLINE']=='1'\nassert os.environ['PYTHONDONTWRITEBYTECODE']=='1'\nprint(json.dumps(dict(id=r['id'],ok=True)))\n")
            self.assertTrue(probe_worker('Vision',sys.executable,script,root,root)[0])
            script.write_text("import sys,json\nsys.stdin.readline()\nprint(json.dumps(dict(id='old',ok=True)))\n")
            self.assertFalse(probe_worker('Vision',sys.executable,script,root,root)[0])
    def test_venv_is_created_at_final_path(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);lock=root/'requirements.lock';lock.write_text('fixture==1\n')
            with patch('install_runtime.subprocess.run') as run,patch('install_runtime.shutil.which',return_value=None):
                python=install_runtime.environment(root,'vision',lock,'/python3.12','3.12')
            self.assertIn('vision-py312-',str(python))
            self.assertEqual(run.call_args_list[0].args[0],['/python3.12','-m','venv',str(python.parent.parent)])
            self.assertEqual(run.call_args_list[1].args[0][0],str(python))
    def test_asset_validation_precedes_environment_changes(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);config=root/'runtime.json';config.write_text('previous configuration')
            with patch.object(install_runtime.sys,'version_info',(3,11)), \
                 patch('install_runtime.platform.system',return_value='Darwin'), \
                 patch('install_runtime.platform.machine',return_value='arm64'), \
                 patch('install_runtime.platform.mac_ver',return_value=('15.5','','')), \
                 patch('install_runtime.subprocess.check_output',return_value='[[3, 12], "arm64"]'), \
                 patch('install_runtime.verify_pack',side_effect=ValueError('changed asset')) as verify, \
                 patch('install_runtime.environment') as environment:
                with self.assertRaises(ValueError):install_runtime.install(None,root,'/python3.12',root/'assets')
                verify.assert_called_once_with(root/'assets');environment.assert_not_called()
            self.assertEqual(config.read_text(),'previous configuration')
    def test_failed_vision_probe_preserves_previous_configuration(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);source=root/'assets';home=root/'runtime';home.mkdir()
            weight=source/'models/parser.pt';weight.parent.mkdir(parents=True);weight.write_bytes(b'fixture')
            files={'models/parser.pt':hashlib.sha256(b'fixture').hexdigest()}
            config=home/'runtime.json';config.write_text('previous configuration')
            with patch.object(install_runtime.sys,'version_info',(3,11)), \
                 patch('install_runtime.platform.system',return_value='Darwin'), \
                 patch('install_runtime.platform.machine',return_value='arm64'), \
                 patch('install_runtime.platform.mac_ver',return_value=('15.5','','')), \
                 patch('install_runtime.subprocess.check_output',return_value='[[3, 12], "arm64"]'), \
                 patch('install_runtime.verify_pack',return_value=(source,files)), \
                 patch('install_runtime.environment',return_value=Path('/python')), \
                 patch('install_runtime.probe_worker',side_effect=[(True,{}),(True,{}),(False,{})]):
                with self.assertRaisesRegex(ValueError,'Vision failed'):install_runtime.install(None,home,'/python3.12',source)
            self.assertEqual(config.read_text(),'previous configuration')

if __name__=='__main__':unittest.main()
