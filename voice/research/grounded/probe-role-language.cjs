// Role-language diagnostic: fixed cases, real local worker and isolated Chrome.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {spawn}=require('node:child_process'),{createInterface}=require('node:readline');
const {Headless}=require('../../browser/tests/headless.cjs');
const args=process.argv.slice(2),oi=args.indexOf('--output');
if(oi<0||!args[oi+1])throw Error('Use --output with a fresh path');
const wi=args.indexOf('--worker'),worker=path.resolve(wi<0?path.join(__dirname,'worker.py'):args[wi+1]);
const source=fs.readFileSync(path.join(__dirname,'../../browser/extension/controller.js'),'utf8');
const child=spawn(process.env.PYTHON||'python3',[worker,'--grounded-v2'],{stdio:['pipe','pipe','inherit'],env:{...process.env,PYTHONDONTWRITEBYTECODE:'1',HF_HUB_OFFLINE:'1',TRANSFORMERS_OFFLINE:'1'}});
let pending=[];
createInterface({input:child.stdout}).on('line',line=>{const p=pending.shift();if(p){clearTimeout(p.timer);p.resolve(JSON.parse(line));}});
child.on('exit',code=>{for(const p of pending){clearTimeout(p.timer);p.reject(Error(`Worker exited ${code}`));}pending=[];});
const ask=request=>new Promise((resolve,reject)=>{const timer=setTimeout(()=>{reject(Error('Worker timeout'));child.kill();},15000);pending.push({resolve,reject,timer});child.stdin.write(JSON.stringify({id:'role-probe',...request})+'\n');});
const control=(id,role,label='Notifications')=>role==='native-checkbox'?`<label>${label}<input id="${id}" type="checkbox"></label>`:role==='native-radio'?`<label>${label}<input id="${id}" type="radio"></label>`:`<div id="${id}" role="${role}" tabindex="0">${label}</div>`;
const cases=[];
for(const [role,word] of [['button','button'],['link','link'],['checkbox','checkbox'],['switch','switch'],['radio','radio button'],['option','option'],['tab','tab'],['menuitem','menu item'],['native-checkbox','checkbox'],['native-radio','radio button']]){
 const wrong=role==='link'?'button':'link';
 cases.push({name:role+' matching role',text:`Click Notifications ${word}`,html:control('target',role),expected:'target'});
 cases.push({name:role+' conflicting role',text:`Click Notifications ${wrong}`,html:control('target',role),expected:null});
}
for(const [word,target] of [['button','button'],['link','link'],['checkbox','checkbox'],['switch','switch']])cases.push({name:'same labels / '+word,text:`Click Notifications ${word}`,html:['button','link','checkbox','switch'].map(r=>control(r,r)).join(''),expected:target});
cases.push({name:'same labels / unspecified',text:'Click Notifications',html:control('button','button')+control('link','link'),expected:null});
cases.push({name:'word inside label is literal',text:'Click Radio settings',html:control('target','button','Radio settings'),expected:'target'});
cases.push({name:'word inside label and qualifier',text:'Click Radio settings button',html:control('target','button','Radio settings'),expected:'target'});
cases.push({name:'leading link qualifier',text:'Click the link called Notifications',html:control('link','link')+control('button','button'),expected:'link'});
if(args.includes('--review')){
 for(const word of ['checkbox','switch','radio button','option']){
  const role=word==='radio button'?'radio':word;
  for(const prefix of ["Don't click",'Do not click','Delete'])cases.push({name:prefix+' / '+role,text:`${prefix} Notifications ${word}`,html:control('target',role),expected:null});
 }
 cases.push({name:'role noun is not another control mention',text:'Click Notifications link',html:control('target','link')+control('word','link','Link'),expected:'target'});
 cases.push({name:'role noun cannot disable mismatch check',text:'Click Notifications link',html:control('target','checkbox')+control('word','link','Link'),expected:null});
 cases.push({name:'mismatch cannot retarget another link',text:'Click Notifications link',html:control('target','checkbox')+control('other','link','Account'),expected:null});
 cases.push({name:'disabled matching role cannot use homonym',text:'Click Notifications link',html:control('target','link').replace('tabindex="0"','tabindex="0" aria-disabled="true"')+control('other','button'),expected:null});
 cases.push({name:'disabled unrelated role does not block requested role',text:'Click Notifications link',html:control('target','link')+control('other','button').replace('tabindex="0"','tabindex="0" aria-disabled="true"'),expected:'target'});
 for(const label of ['Help link','Switch','Radio button'])cases.push({name:'literal / '+label,text:'Click '+label,html:control('target','button',label),expected:'target'});
 cases.push({name:'prefix qualifier with role noun label',text:'Click the link called Button',html:control('target','link','Button')+control('other','button','Button'),expected:'target'});
 cases.push({name:'suffix qualifier with extra whitespace',text:'Click Notifications radio   button',html:control('target','radio'),expected:'target'});
 cases.push({name:'punctuated conflicting role',text:'Click Notifications link,',html:control('target','checkbox'),expected:null});
}
(async()=>{const b=new Headless(),rows=[];try{
 await b.start();
 for(const c of cases){
  await b.evaluate(`document.body.innerHTML=${JSON.stringify(c.html)};globalThis.actions=[];for(const e of document.querySelectorAll('[id]'))e.onclick=()=>actions.push(e.id)`);await b.controller(source);
  const observation=(await b.run('observe')).observation,proposal=await ask({text:c.text,observation});let result=null;
  if(proposal.command)result=await b.run(proposal.command.op,proposal.command);
  const actions=await b.evaluate('actions'),passed=JSON.stringify(actions)===JSON.stringify(c.expected?[c.expected]:[]);
  rows.push({name:c.name,text:c.text,expected:c.expected,actions,passed,wrongAction:actions.length>0&&!passed,proposal,result});
 }
 const report={scope:'28 original authored explicit-role/mixed-control requests plus optional review cases, actual worker and headless observer/executor; no speech or real websites. Delivered-target oracle, not application-result verification.',passed:rows.filter(r=>r.passed).length,total:rows.length,wrongActions:rows.filter(r=>r.wrongAction).length,rows,controllerSHA256:crypto.createHash('sha256').update(source).digest('hex'),pipelineSHA256:crypto.createHash('sha256').update(fs.readFileSync(path.join(path.dirname(worker),'pipeline.py'))).digest('hex'),workerSHA256:crypto.createHash('sha256').update(fs.readFileSync(worker)).digest('hex'),testSHA256:crypto.createHash('sha256').update(fs.readFileSync(__filename)).digest('hex')};
 fs.writeFileSync(args[oi+1],JSON.stringify(report,null,2)+'\n',{flag:'wx'});console.log(JSON.stringify({passed:report.passed,total:report.total,wrongActions:report.wrongActions,failures:rows.filter(r=>!r.passed).map(r=>({name:r.name,actions:r.actions,reason:r.proposal.reason,operation:r.proposal.operation}))},null,2));
 if(report.passed!==report.total)process.exitCode=1;
}finally{child.stdin.end();await b.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
