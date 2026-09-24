// Protocol lifecycle checks: controlled clocks and a fake CDP child; no Chrome or user input.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {EventEmitter}=require('node:events');
const {Headless}=require('./headless.cjs');
const deferred=()=>{let resolve;const promise=new Promise(r=>{resolve=r});return {promise,resolve}};
class ControlledClock extends Headless {
  constructor(){super({virtualTime:true});this.events??=new EventEmitter();this.started=deferred();this.advance=deferred();this.startGate=null;this.calls=[];}
  async evaluate(expression){
    if(expression.startsWith('globalThis.__localVoiceFixturePending=')){
      this.started.resolve();if(this.startGate)await this.startGate.promise;return true;
    }
    return {ok:true,outcome:'verified'};
  }
  async call(method,params){
    this.calls.push(params.policy);
    if(params.policy==='advance'){
      this.advance.resolve();
      if(this.failAdvance)throw Error('Transport rejected clock advancement');
    }
    return {};
  }
  finishBudget(){this.events.emit('Emulation.virtualTimeBudgetExpired',{});}
}
test('a resolved action still waits for the clock budget before pausing',async()=>{
  const browser=new ControlledClock();let settled=false;
  const pending=browser.run('observe').then(value=>{settled=true;return value});
  await browser.advance.promise;
  await new Promise(resolve=>setImmediate(resolve));
  try{assert.equal(settled,false,'Returning early can leave an older budget callback to pause the next action');}
  finally{browser.finishBudget();await pending;}
  assert.deepEqual(browser.calls,['advance','pause']);
  assert.equal(browser.events.listenerCount('Emulation.virtualTimeBudgetExpired'),0);
});
test('clock advancement waits for the action start acknowledgement',async()=>{
  const browser=new ControlledClock();browser.startGate=deferred();
  const pending=browser.run('click');await browser.started.promise;
  assert.deepEqual(browser.calls,[]);
  browser.startGate.resolve();await browser.advance.promise;browser.finishBudget();await pending;
});
test('a failed clock request removes its pending event listener',async()=>{
  const browser=new ControlledClock();browser.failAdvance=true;
  await assert.rejects(browser.run('click'),/Transport rejected/);
  assert.equal(browser.events.listenerCount('Emulation.virtualTimeBudgetExpired'),0);
  assert.deepEqual(browser.calls,['advance','pause']);
});
test('startup protocol failure closes its child and removes the temporary profile',async()=>{
  const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
  const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'localvoice-protocol-test-'));
  const binary=path.join(temporary,'fake-browser');
  fs.writeFileSync(binary,`#!/usr/bin/env node
const fs=require('node:fs');let buffer='';
fs.createReadStream(null,{fd:3}).on('data',data=>{
 buffer+=data.toString();let end;
 while((end=buffer.indexOf('\\0'))>=0){
  const request=JSON.parse(buffer.slice(0,end));buffer=buffer.slice(end+1);
  const response=request.method==='Network.enable'?{error:{message:'Intentional startup protocol failure'}}:
   {result:request.method==='Target.createTarget'?{targetId:'target'}:request.method==='Target.attachToTarget'?{sessionId:'session'}:{}};
  fs.writeSync(4,JSON.stringify({id:request.id,...response})+'\\0');
  if(request.method==='Browser.close')process.exit(0);
 }
});
`,{mode:0o755});
  const previous=process.env.VOICE_TEST_CHROME;process.env.VOICE_TEST_CHROME=binary;
  const browser=new Headless();
  try{
    await assert.rejects(browser.start(),/Intentional startup protocol failure/);
    assert.equal(fs.existsSync(browser.profile),false,'A failed start must release its profile');
    assert.notEqual(browser.child.exitCode,null,'A failed start must not leave a browser running');
  }finally{
    await browser.close();
    if(previous===undefined)delete process.env.VOICE_TEST_CHROME;else process.env.VOICE_TEST_CHROME=previous;
    fs.rmSync(temporary,{recursive:true,force:true});
  }
});
