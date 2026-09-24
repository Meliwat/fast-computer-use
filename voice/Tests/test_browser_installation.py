"""Installation diagnostics against real setup.py output in a disposable home."""
import importlib.util
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('voice_doctor',ROOT/'voice/tools/doctor.py')
doctor=importlib.util.module_from_spec(spec);spec.loader.exec_module(doctor)


class BrowserInstallationTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix="voice browser's setup ")
        self.addCleanup(self.temp.cleanup)
        self.base=Path(self.temp.name)
        self.browser=self.base/'checkout/browser';(self.browser/'extension').mkdir(parents=True)
        for name in ['setup.py','native_host.py','extension/manifest.json']:
            shutil.copy2(ROOT/'voice/browser'/name,self.browser/name)
        self.home=self.base/'test home';self.home.mkdir()
        self.runtime=self.home/'Library/Application Support/LocalVoice/BrowserHost'
        self.registration=self.home/'Library/Application Support/Google/Chrome/NativeMessagingHosts/dev.localvoice.browser.json'
        subprocess.run([sys.executable,str(self.browser/'setup.py'),'--install'],
                       env={**os.environ,'HOME':str(self.home)},check=True,capture_output=True,text=True)

    def check(self):
        # File diagnosis must not execute its launcher or any subprocess.
        with patch.object(doctor.subprocess,'run',side_effect=AssertionError('Diagnostic attempted execution')):
            return doctor.check_browser_installation(self.browser,self.home)

    def failure(self,name,text):
        rows={r['name']:r for r in self.check()}
        self.assertFalse(rows[name]['ok']);self.assertIn(text,rows[name]['detail'])

    def test_real_setup_with_spaces_and_apostrophe_passes_without_execution(self):
        rows=self.check()
        self.assertEqual(len(rows),5)
        self.assertTrue(all(r['ok'] for r in rows),rows)

    def test_missing_registration_has_repair_instruction(self):
        self.registration.unlink()
        self.failure('Chrome host registration','setup.py --install')

    def test_mismatched_origin_fails(self):
        data=json.loads(self.registration.read_text());data['allowed_origins']=['chrome-extension://wrong/']
        self.registration.write_text(json.dumps(data))
        self.failure('Chrome host registration','does not match this extension ID')

    def test_unexpected_launcher_is_not_read_or_executed(self):
        data=json.loads(self.registration.read_text());data['path']=str(self.base/'not-a-host')
        self.registration.write_text(json.dumps(data))
        self.failure('Chrome host registration','differs from the supported')

    def test_stale_copied_host_is_detected(self):
        (self.runtime/'native_host.py').write_text('raise RuntimeError("must never execute")\n')
        self.failure('Chrome host source','differs from this checkout')

    def test_changed_installed_config_is_detected(self):
        (self.runtime/'host-config.json').write_text('{"extension_id":"wrong"}')
        self.failure('Chrome host configuration','different extension ID')

    def test_removed_interpreter_is_detected(self):
        launcher=self.runtime/'native-host'
        command=['exec',str(self.base/'removed python'),str(self.runtime/'native_host.py'),'$@']
        launcher.write_text('#!/bin/sh\n'+' '.join(map(shlex.quote,command))+'\n')
        self.failure('Chrome host launcher','Python interpreter recorded during browser setup')

    def test_non_executable_launcher_fails(self):
        (self.runtime/'native-host').chmod(0o600)
        self.failure('Chrome host launcher','not executable')

    def test_malformed_registration_is_a_diagnostic_not_a_crash(self):
        self.registration.write_text('[]')
        self.failure('Chrome host registration','JSON object')

    def test_malformed_extension_key_is_a_diagnostic_not_a_crash(self):
        p=self.browser/'extension/manifest.json';data=json.loads(p.read_text());data['key']='not a base64 key'
        p.write_text(json.dumps(data))
        self.failure('Chrome extension source','invalid extension manifest/key')


if __name__=='__main__':unittest.main()
