"""Fault injection around app replacement; no real signing, models or app launch."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

BUILD=Path(__file__).resolve().parents[1]/'build.sh'

class BuildReplacementTests(unittest.TestCase):
    def build(self,failure=None,identity='fixture',available=''):
        with tempfile.TemporaryDirectory(prefix='voice replacement ') as temp:
            root=Path(temp);voice=root/'voice';voice.mkdir();shutil.copyfile(BUILD,voice/'build.sh')
            old=voice/'dist/Local Voice.app';old.mkdir(parents=True);(old/'old-marker').write_text('existing app')
            binary=voice/'.build/release/LocalVoice';binary.parent.mkdir(parents=True);binary.write_text('new app')
            staging=voice/'tools/stage_runtime.py';staging.parent.mkdir()
            staging.write_text("import json,os,sys\nwith open(os.environ['VOICE_TEST_TRACE'],'a') as f:f.write(json.dumps(['stage'])+'\\n')\nsys.exit(1 if os.environ.get('BUILD_FAILURE')=='models' else 0)\n")
            tools=root/'bin';tools.mkdir()
            for command in ['swift','codesign']:
                script=tools/command
                script.write_text('#!'+sys.executable+"\nimport json,os,sys\nwith open(os.environ['VOICE_TEST_TRACE'],'a') as f:f.write(json.dumps(sys.argv)+'\\n')\n")
                script.chmod(0o755)
            security=tools/'security'
            security.write_text('#!'+sys.executable+"\nimport os\nprint(os.environ.get('VOICE_TEST_IDENTITIES',''))\n")
            security.chmod(0o755)
            move=tools/'mv'
            move.write_text('#!'+sys.executable+'''\nimport os,sys,signal
source,dest=sys.argv[1:]
mode=os.environ.get('BUILD_FAILURE')
if mode=='install' and source.endswith('/Local Voice.app') and '/.voice-build-' in source:
 sys.exit(1)
os.rename(source,dest)
if mode=='interrupt' and dest.endswith('/previous.app'):
 os.kill(os.getppid(),signal.SIGTERM)
''')
            move.chmod(0o755)
            trace=root/'commands.jsonl'
            env={**os.environ,'PATH':str(tools)+os.pathsep+os.environ['PATH'],'VOICE_PYTHON':sys.executable,
                 'VOICE_TEST_TRACE':str(trace),'VOICE_TEST_IDENTITIES':available}
            if identity is None:env.pop('VOICE_SIGN_IDENTITY',None)
            else:env['VOICE_SIGN_IDENTITY']=identity
            if failure:env['BUILD_FAILURE']=failure
            result=subprocess.run(['/bin/sh',str(voice/'build.sh')],capture_output=True,text=True,env=env,timeout=10)
            commands=[json.loads(line) for line in trace.read_text().splitlines()] if trace.exists() else []
            return result.returncode,(old/'old-marker').exists(),(old/'Contents/MacOS/LocalVoice').exists(),list((voice/'dist').glob('.voice-build-*')),commands
    def test_success_replaces_only_after_staging(self):
        code,old,new,left,_=self.build()
        self.assertEqual(code,0);self.assertFalse(old);self.assertTrue(new);self.assertEqual(left,[])
    def test_missing_models_preserve_previous_app(self):
        code,old,new,left,_=self.build('models')
        self.assertNotEqual(code,0);self.assertTrue(old);self.assertFalse(new);self.assertEqual(left,[])
    def test_failed_final_move_restores_previous_app(self):
        code,old,new,left,_=self.build('install')
        self.assertNotEqual(code,0);self.assertTrue(old);self.assertFalse(new);self.assertEqual(left,[])
    def test_interrupt_during_replacement_restores_previous_app(self):
        code,old,new,left,_=self.build('interrupt')
        self.assertNotEqual(code,0);self.assertTrue(old);self.assertFalse(new);self.assertEqual(left,[])
    def test_missing_or_ad_hoc_identity_stops_before_compile_and_staging(self):
        for identity in [None,'-']:
            with self.subTest(identity=identity):
                code,old,new,left,commands=self.build(identity=identity)
                self.assertNotEqual(code,0);self.assertTrue(old);self.assertFalse(new)
                self.assertEqual(left,[]);self.assertEqual(commands,[])
    def test_existing_development_identity_keeps_priority(self):
        available='1) AAAAAAAA "Developer ID Application: Example"\n2) BBBBBBBB "Apple Development: Example"'
        code,_,new,_,commands=self.build(identity=None,available=available)
        signing=next(c for c in commands if '--sign' in c)
        self.assertEqual(code,0);self.assertTrue(new);self.assertEqual(signing[3],'BBBBBBBB')
    def test_developer_id_application_is_detected(self):
        code,_,new,_,commands=self.build(identity=None,available='1) AAAAAAAA "Developer ID Application: Example"')
        signing=next(c for c in commands if '--sign' in c)
        self.assertEqual(code,0);self.assertTrue(new);self.assertEqual(signing[3],'AAAAAAAA')
    def test_explicit_identity_is_passed_as_one_argument(self):
        code,_,new,_,commands=self.build(identity='Local Voice signing certificate')
        signing=next(c for c in commands if '--sign' in c)
        self.assertEqual(code,0);self.assertTrue(new);self.assertEqual(signing[3],'Local Voice signing certificate')

if __name__=='__main__':unittest.main()
