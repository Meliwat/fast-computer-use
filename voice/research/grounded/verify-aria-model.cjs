// Actual local operation/ranking models + browser discovery/dispatch; no personal UI.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {spawn}=require('node:child_process'),{createInterface}=require('node:readline');
const {Headless}=require('../../browser/tests/headless.cjs');
const source=fs.readFileSync(path.join(__dirname,'../../browser/extension/controller.js'),'utf8');
const args=process.argv.slice(2),option=name=>{const i=args.indexOf(name);if(i>=0&&!args[i+1])throw Error(`${name} needs a value`);return i<0?null:args[i+1];};
const output=option('--output'),worker=path.resolve(option('--worker')||path.join(__dirname,'worker.py'));
const child=spawn(process.env.PYTHON||'python3',[worker,'--grounded-v2'],{stdio:['pipe','pipe','inherit'],env:{...process.env,PYTHONDONTWRITEBYTECODE:'1',HF_HUB_OFFLINE:'1',TRANSFORMERS_OFFLINE:'1',HF_HUB_DISABLE_TELEMETRY:'1'}});
let pending=[];
createInterface({input:child.stdout}).on('line',line=>{const p=pending.shift();if(p){clearTimeout(p.timer);p.resolve(JSON.parse(line));}});
child.on('exit',code=>{for(const p of pending){clearTimeout(p.timer);p.reject(Error(`Worker exited ${code}`));}pending=[];});
const ask=request=>new Promise((resolve,reject)=>{const timer=setTimeout(()=>{reject(Error('Worker timeout'));child.kill();},15000);pending.push({resolve,reject,timer});child.stdin.write(JSON.stringify({id:'aria',...request})+'\n');});
const roles=['menuitem','menuitemcheckbox','menuitemradio','checkbox','switch','radio','option','link'];
(async()=>{const b=new Headless(),rows=[];try{
 await b.start();
 for(const role of roles){
  const state=role==='menuitem'?'aria-expanded':role==='option'?'aria-selected':role==='link'?null:'aria-checked';
  const attr=state?`${state}="false"`:'';
  for(const c of [{name:'named',text:'Click Notifications',source:'observed_label'},
                  {name:'semantic',text:'Bring up the alerts',source:'semantic_ranker'},
                  {name:'negated',text:"Don't click Notifications",negative:true},
                  {name:'disabled',text:'Click Notifications',negative:true,disabled:true}]){
   const html=`<div id="target" role="${role}" tabindex="0" ${attr} ${c.disabled?'aria-disabled="true"':''}>Notifications</div><button>Account</button><p id="effect"></p>`;
   const change=state?`document.querySelector('#target').setAttribute(${JSON.stringify(state)},'true')`:`document.querySelector('#effect').textContent='opened'`;
   await b.evaluate(`document.body.innerHTML=${JSON.stringify(html)};globalThis.actions=[];document.querySelector('#target').onclick=()=>{actions.push('target');${change}}`);
   await b.controller(source);
   const observation=(await b.run('observe')).observation;
   const proposal=await ask({text:c.text,observation});let result=null;
   if(proposal.command)result=await b.run(proposal.command.op,proposal.command);
   const actions=await b.evaluate('actions');
   if(c.negative){assert.equal(proposal.command,null,`${role}/${c.name}`);assert.deepEqual(actions,[]);}
   else{
    assert(proposal.command,`${role}/${c.name}: ${JSON.stringify(proposal)}`);
    assert.equal(proposal.source,c.source);assert.deepEqual(actions,['target']);assert.equal(result.outcome,state?'verified':'unverified');
    assert.equal(await b.evaluate(state?`document.querySelector('#target').getAttribute(${JSON.stringify(state)})`:`document.querySelector('#effect').textContent`),state?'true':'opened');
   }
   rows.push({role,case:c.name,text:c.text,source:proposal.source||null,reason:proposal.reason,outcome:result?.outcome||null,actions,rankingMs:proposal.rankingMs});
  }
 }
 const report={scope:'32 authored named/known-semantic/negated/disabled cases across eight ARIA roles. Real resident local models plus headless production controller. Semantic aliases were present in prior training; not unseen concept generalization. Plain custom link activation is observed independently but remains unverified by the controller. No speech/native host/app launch.',passed:rows.length,rows,controllerSHA256:crypto.createHash('sha256').update(source).digest('hex'),pipelineSHA256:crypto.createHash('sha256').update(fs.readFileSync(path.join(path.dirname(worker),'pipeline.py'))).digest('hex'),workerSHA256:crypto.createHash('sha256').update(fs.readFileSync(worker)).digest('hex'),testSHA256:crypto.createHash('sha256').update(fs.readFileSync(__filename)).digest('hex')};
 if(output)fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n',{flag:'wx'});console.log(JSON.stringify(report,null,2));
}finally{child.stdin.end();await b.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
