// Protocol lifecycle checks only: no browser, user input, or real timers.
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
