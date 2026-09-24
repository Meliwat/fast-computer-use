"""Brief foreground test in the disposable Text Fixture. No personal app input.

Requires already-granted Accessibility for the signed Local Voice app. The
fixture restores the prior app on exit if the user has not switched elsewhere.
"""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
import uuid

ROOT=Path(__file__).resolve().parents[3]
OUTPUT=ROOT/'.cache/native-text'
FIXTURE=OUTPUT/'Text Fixture.app'
APP=ROOT/'voice/dist/Local Voice.app'


def pids(name):
    result=subprocess.run(['pgrep','-x',name],capture_output=True,text=True)
    if result.returncode not in (0,1):raise RuntimeError('Could not check running test applications')
    return [int(value) for value in result.stdout.split()]


def stop_owned(name,bundle):
    expected=str(bundle/'Contents/MacOS'/name)
    for pid in pids(name):
        executable=subprocess.check_output(['ps','-p',str(pid),'-o','comm='],text=True).strip()
        if executable==expected:os.kill(pid,signal.SIGTERM)


def run():
    menus='--menus' in sys.argv
    grounded='--grounded' in sys.argv or menus
    existing_text='--existing-text' in sys.argv
    if existing_text and grounded:raise ValueError('Choose existing-text, grounded or menus as separate fixture runs')
    if pids('LocalVoice') or pids('TextFixture'):raise RuntimeError('Close Local Voice and Text Fixture before this developer check')
    if not APP.is_dir() or not FIXTURE.is_dir():raise RuntimeError('Build the app and text fixture first')
    report=OUTPUT/f'check-{uuid.uuid4().hex}.json';state=OUTPUT/'text-fixture-state.json'
    state.unlink(missing_ok=True)
    try:
        previous=subprocess.check_output([str(FIXTURE/'Contents/MacOS/TextFixture'),'--foreground-pid'],text=True).strip()
        if not previous.isdigit() or int(previous)<=0:raise RuntimeError('Could not identify the previous application')
        subprocess.run(['open','-n',str(FIXTURE),'--args','--return-to',previous]+(['--grounded'] if grounded else [])+(['--menus'] if menus else []),check=True)
        deadline=time.monotonic()+10
        while not state.exists() or not json.loads(state.read_text()).get('foreground'):
            if time.monotonic()>deadline:raise RuntimeError('Fixture did not become ready')
            time.sleep(.05)
        time.sleep(.2)
        flag='--native-menu-integration-check' if menus else '--native-grounded-integration-check' if grounded else '--native-existing-text-integration-check' if existing_text else '--native-text-integration-check'
        subprocess.run(['open','-n','-g',str(APP),'--args',flag,str(report)],check=True)
        deadline=time.monotonic()+20
        while not report.exists():
            if time.monotonic()>deadline:raise RuntimeError('Native text diagnostic timed out; no retry')
            time.sleep(.05)
        time.sleep(.1)
        result=json.loads(report.read_text());observed=json.loads(state.read_text())
        controls=observed['changes'];values=observed['values'];history=observed['history']
        untouched=all(controls[k]==0 for k in ['duplicateA','duplicateB','disabled','readonly','password','hidden'])
        effects=(history['destination']==['Original','Oslo','Oslo👋','Oslo and open Notes']
                 and history['reverting']==['Original','Changed','Original']
                 and history['moving']==['Original','Focus test']
                 and history['placeholder']==['Original','Paris']
                 and history['linked']==['Original','Hello'])
        if existing_text:
            effects=(history['destination']==['Original','Straße','STRASSE','strasse']
                     and history['placeholder']==['Original','Straße','Changed','Focus test']
                     and history['linked']==['Original','Before','Original']
                     and history['reverting']==['Original','Changed','Original']
                     and history['moving']==['Original','Focus test'])
        if grounded:
            untouched=all(count==0 for name,count in controls.items() if name!='linked')
            effects=(history['linked']==['','Native focus works']
                     and observed['clicks']=={'preferences':1,'help':0,'open':0,'save':0,'save-as':1,'details-a':0,'details-b':0,'unavailable':0}
                     and 'placeholder' in observed['focusHistory'] and 'linked' in observed['focusHistory']
                     and observed['helpRenamed'])
        if menus:
            untouched=all(count==0 for count in controls.values())
            effects=(observed['menuCommands']==['save-as','image','save'] and all(count==0 for count in observed['clicks'].values())
                     and 'linked' in observed['focusHistory'])
        result['independentFixtureState']=observed
        result['protectedAndAmbiguousFieldsUntouched']=untouched
        result['expectedFinalEffects']=effects
        result['passed']=result.get('ok') is True and result.get('check',{}).get('allPassed') is True and untouched and effects
        report.write_text(json.dumps(result,indent=2)+'\n')
        print(json.dumps(dict(passed=result['passed'],report=report.name,protectedFieldsUntouched=untouched,expectedFinalEffects=effects),indent=2))
        if not result['passed']:raise RuntimeError('Native text suite failed; inspect its report before retrying')
    finally:
        stop_owned('LocalVoice',APP);stop_owned('TextFixture',FIXTURE)


if __name__=='__main__':run()
