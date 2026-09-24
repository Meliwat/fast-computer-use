// Isolated browser + real resident worker + shipping DOM observer/executor.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {spawn}=require('node:child_process'),{createInterface}=require('node:readline');
const {Headless}=require('../../browser/tests/headless.cjs');
const source=fs.readFileSync(path.join(__dirname,'../../browser/extension/controller.js'),'utf8');
const child=spawn(process.env.PYTHON||'python3',[path.join(__dirname,'worker.py'),'--grounded-v2'],{stdio:['pipe','pipe','inherit']});
let pending=[];
createInterface({input:child.stdout}).on('line',line=>{const p=pending.shift();if(p){clearTimeout(p.timer);p.resolve(JSON.parse(line));}});
child.on('exit',code=>{for(const p of pending){clearTimeout(p.timer);p.reject(Error(`Worker exited ${code}`));}pending=[];});
const ask=request=>new Promise((resolve,reject)=>{const timer=setTimeout(()=>{reject(Error('Worker timeout'));child.kill();},15000);pending.push({resolve,reject,timer});child.stdin.write(JSON.stringify({id:'test',...request})+'\n');});
const fixture=noop=>`<button id="tools" aria-expanded="false" onclick="actions.push('tools');${noop?'':`this.setAttribute('aria-expanded','true');document.querySelector('#play').hidden=false;document.querySelector('#search').hidden=false;`}">Tools</button>
<button id="play" hidden aria-expanded="false" onclick="actions.push('playground');this.setAttribute('aria-expanded','true')">Playground</button><input id="search" aria-label="Reference number" hidden>`;
(async()=>{const b=new Headless(),rows=[];try{
 await b.start();
 for(const c of [
  {name:'revealed target',texts:['Show the tools menu','Open Playground'],expected:['tools','playground'],verified:2},
  {name:'revealed field',texts:['Show the tools menu','Focus Reference number'],expected:['tools'],verified:2,focus:'search'},
  {name:'unsupported later operation',texts:['Show the tools menu','Delete Account'],expected:[],verified:0},
  {name:'unverified first action',texts:['Show the tools menu','Open Playground'],expected:['tools'],verified:0,noop:true},
  {name:'missing later target',texts:['Show the tools menu','Open Notifications'],expected:['tools'],verified:1},
  {name:'native disclosure reveals the next target',texts:['Open Details','Open Playground'],expected:['details','playground'],verified:2,
   html:'<details><summary onclick="actions.push(\'details\')">Details</summary><button aria-expanded="false" onclick="actions.push(\'playground\');this.setAttribute(\'aria-expanded\',\'true\')">Playground</button></details>'},
  {name:'native popover reveals the next field',texts:['Open Filters','Focus Reference number'],expected:['filters'],verified:2,focus:'search',
   html:'<button popovertarget="panel" onclick="actions.push(\'filters\')">Filters</button><div id="panel" popover><input id="search" aria-label="Reference number"></div>'},
  {name:'ARIA menu item reveals the next field',texts:['Show the tools menu','Focus Reference number'],expected:['tools'],verified:2,focus:'search',
   html:'<div role="menuitem" aria-expanded="false" aria-controls="panel" onclick="actions.push(\'tools\');this.setAttribute(\'aria-expanded\',\'true\');document.querySelector(\'#panel\').hidden=false">Tools</div><div id="panel" hidden><input id="search" aria-label="Reference number"></div>'},
  {name:'ARIA switch reveals the next field',texts:['Click Filters switch','Focus Reference number'],expected:['filters'],verified:2,focus:'search',
   html:'<div role="switch" aria-checked="false" onclick="actions.push(\'filters\');this.setAttribute(\'aria-checked\',\'true\');document.querySelector(\'#search\').hidden=false">Filters</div><input id="search" aria-label="Reference number" hidden>'},
 ]){
  await b.evaluate(`document.body.innerHTML=${JSON.stringify(c.html || fixture(c.noop))};globalThis.actions=[];`);await b.controller(source);
  const initial=(await b.run('observe')).observation;
  assert(!initial.candidates.some(x=>x.labels.includes('playground')),'child must initially be absent');
  const gate=await ask({kind:'preflight',texts:c.texts});let verified=0,observations=[];
  if(gate.operations?.every(o=>['activate','focus'].includes(o.operation)&&o.confidence>=.99)){
   for(const text of c.texts){
    const observation=(await b.run('observe')).observation;observations.push(observation.observationId);
    const proposal=await ask({text,observation});if(!proposal.command)break;
    const result=await b.run(proposal.command.op,proposal.command);if(!result.ok||result.outcome!=='verified')break;
    verified++;
   }
  }
  assert.equal(verified,c.verified,c.name);assert.deepEqual(await b.evaluate('actions'),c.expected,c.name);
  if(c.focus)assert.equal(await b.evaluate('document.activeElement.id'),c.focus);
  assert.equal(new Set(observations).size,observations.length,'every step has a fresh observation');
  rows.push({name:c.name,verified,actions:c.expected});
 }
 console.log(JSON.stringify({passed:rows.length,rows},null,2));
}finally{child.stdin.end();await b.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
